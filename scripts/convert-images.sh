#!/bin/bash
#
# convert-images.sh — Gemini生成画像のリネーム→WebP変換→配置を自動化する
#
# ■ 置き場所
#   このリポジトリの scripts/convert-images.sh に置く（このファイル自体）。
#
# ■ 事前準備（一度だけ）
#   chmod +x scripts/convert-images.sh
#
# ■ 使い方（1業種ずつ実行。一度に全業種は処理しない）
#   ./scripts/convert-images.sh cafe
#
#   リポジトリのルートから実行しても、scripts/ の中から実行しても動く
#   （スクリプト自身の場所を基準にパスを解決しているため）。
#
# ■ 入力フォルダの準備
#   下記 INPUT_ROOT（デフォルト: ~/Desktop/gemini-input）の中に、
#   業種フォルダ→用途サブフォルダの構造でPNGを置く。
#     ~/Desktop/gemini-input/cafe/hero/    ← ヒーロー画像（PNGちょうど1枚）
#     ~/Desktop/gemini-input/cafe/menu/    ← メニュー画像（複数可、品目ごとに1枚）
#     ~/Desktop/gemini-input/cafe/gallery/ ← ギャラリー画像（複数可）
#   置き場所を変えたい場合は、下の INPUT_ROOT を書き換えるか、
#   環境変数 GEMINI_INPUT_ROOT で上書きする：
#     GEMINI_INPUT_ROOT=/path/to/dir ./scripts/convert-images.sh cafe
#
# ■ 処理内容（用途ごとにルールが違う）
#   hero    : リサイズなし。WebP変換のみ（品質82、RGBA→RGB）
#   menu    : 幅800pxにリサイズ（縦は比率維持）＋WebP変換
#   gallery : 幅1200pxにリサイズ（縦は比率維持）＋WebP変換
#             ファイル更新日時の古い順に gallery1, gallery2... と採番する
#             （Gemini生成順＝ダウンロード順に対応させるため。CLAUDE.md 8章の
#             「stat コマンドで生成順を判定する」運用に合わせている）
#
# ■ 命名規則（retail/nail/techの実物を調査して確定したものに完全準拠）
#   {業種}_hero.webp
#   {業種}_menu_{品目名}.webp   … 品目名は入力ファイル名（拡張子抜き・小文字化）をそのまま使う
#   {業種}_gallery{1..N}.webp
#
# ■ WebP変換ツールについて（重要な注意）
#   当初 sips での変換を想定していたが、このMac（macOS 26.5）の sips は
#   WebPの「書き込み」に対応していないことを実機検証で確認した
#   （sips --formats には webp が出るが、実際に書き込むと
#   "Error: Can't write format: org.webmproject.webp" で失敗する）。
#   代わりに、このMacに標準で入っている python3 + Pillow を使っている。
#   追加インストールは不要。Pillow (libwebp) の出力は、本番の
#   retail_menu_basket.webp と実測バイト数まで一致することを確認済み。
#
# ■ PNG原本の扱い
#   入力フォルダのPNGには一切触れない（読み取り専用でアクセスする）。
#   コピーも移動もしない。リポジトリに置かれるのは変換後のWebPのみ。
#
set -euo pipefail

# ---- 設定 ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INPUT_ROOT="${GEMINI_INPUT_ROOT:-$HOME/Desktop/gemini-input}"
MENU_WIDTH=800
GALLERY_WIDTH=1200
QUALITY=82

# ---- 引数チェック ----------------------------------------------------------
if [ $# -ne 1 ]; then
  echo "使い方: $0 <業種名>　（例: $0 cafe）" >&2
  echo "一度に処理できるのは1業種だけです。" >&2
  exit 1
fi
BUSINESS="$1"

INPUT_DIR="$INPUT_ROOT/$BUSINESS"
OUTPUT_DIR="$REPO_ROOT/samples/images/$BUSINESS"

if [ ! -d "$INPUT_DIR" ]; then
  echo "エラー: 入力フォルダが見つかりません: $INPUT_DIR" >&2
  echo "  ${BUSINESS}/hero/ ${BUSINESS}/menu/ ${BUSINESS}/gallery/ を用意してください。" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "== convert-images.sh: $BUSINESS =="
echo "入力: $INPUT_DIR"
echo "出力: $OUTPUT_DIR"
echo

# ---- Python変換ヘルパー ----------------------------------------------------
# 引数: 入力パス 出力パス 目標幅(0=リサイズなし) 品質
convert_one() {
  local src="$1" dst="$2" width="$3" quality="$4"
  python3 - "$src" "$dst" "$width" "$quality" <<'PYEOF'
import sys
from PIL import Image

src, dst, width, quality = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])

img = Image.open(src)

# RGBA/パレット/LA → RGB（白背景で合成してアルファを除去）
if img.mode in ("RGBA", "LA", "P"):
    base = img.convert("RGBA") if img.mode == "P" else img
    bg = Image.new("RGB", base.size, (255, 255, 255))
    bg.paste(base, mask=base.split()[-1])
    img = bg
elif img.mode != "RGB":
    img = img.convert("RGB")

if width > 0 and img.width != width:
    height = round(img.height * width / img.width)
    img = img.resize((width, height), Image.LANCZOS)

img.save(dst, "WEBP", quality=quality)
print(f"{img.width}x{img.height}")
PYEOF
}

# ---- hero: PNGちょうど1枚を想定、リサイズなし ------------------------------
HERO_DIR="$INPUT_DIR/hero"
HERO_COUNT=0
if [ -d "$HERO_DIR" ]; then
  HERO_COUNT=$(find "$HERO_DIR" -maxdepth 1 -iname "*.png" | wc -l | tr -d ' ')
fi

if [ "$HERO_COUNT" -eq 1 ]; then
  SRC=$(find "$HERO_DIR" -maxdepth 1 -iname "*.png")
  DST="$OUTPUT_DIR/${BUSINESS}_hero.webp"
  DIM=$(convert_one "$SRC" "$DST" 0 "$QUALITY")
  SIZE=$(ls -la "$DST" | awk '{print $5}')
  echo "[hero]    $(basename "$SRC")  ->  $(basename "$DST")   ${DIM}px  ${SIZE} bytes  (リサイズなし)"
elif [ "$HERO_COUNT" -eq 0 ]; then
  echo "[hero]    スキップ（$HERO_DIR にPNGが見つかりません）"
else
  echo "エラー: [hero] $HERO_DIR に複数のPNGがあります（${HERO_COUNT}枚）。1枚だけにしてください。" >&2
  exit 1
fi
echo

# ---- menu: 幅800pxリサイズ。ファイル名(拡張子抜き)を品目名に使う -------------
MENU_DIR="$INPUT_DIR/menu"
if [ -d "$MENU_DIR" ] && [ -n "$(find "$MENU_DIR" -maxdepth 1 -iname '*.png')" ]; then
  while IFS= read -r SRC; do
    STEM=$(basename "$SRC" | sed -E 's/\.[Pp][Nn][Gg]$//' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    if [ -z "$STEM" ]; then
      echo "エラー: [menu] ファイル名から品目名を作れません: $SRC（英数字のファイル名にしてください）" >&2
      exit 1
    fi
    DST="$OUTPUT_DIR/${BUSINESS}_menu_${STEM}.webp"
    DIM=$(convert_one "$SRC" "$DST" "$MENU_WIDTH" "$QUALITY")
    SIZE=$(ls -la "$DST" | awk '{print $5}')
    echo "[menu]    $(basename "$SRC")  ->  $(basename "$DST")   ${DIM}px  ${SIZE} bytes"
  done < <(find "$MENU_DIR" -maxdepth 1 -iname "*.png" | sort)
else
  echo "[menu]    スキップ（$MENU_DIR にPNGが見つかりません）"
fi
echo

# ---- gallery: 幅1200pxリサイズ。更新日時の古い順に gallery1..N を採番 -------
GALLERY_DIR="$INPUT_DIR/gallery"
if [ -d "$GALLERY_DIR" ] && [ -n "$(find "$GALLERY_DIR" -maxdepth 1 -iname '*.png')" ]; then
  N=1
  while IFS= read -r SRC; do
    DST="$OUTPUT_DIR/${BUSINESS}_gallery${N}.webp"
    DIM=$(convert_one "$SRC" "$DST" "$GALLERY_WIDTH" "$QUALITY")
    SIZE=$(ls -la "$DST" | awk '{print $5}')
    echo "[gallery] $(basename "$SRC")  ->  $(basename "$DST")   ${DIM}px  ${SIZE} bytes"
    N=$((N + 1))
  done < <(find "$GALLERY_DIR" -maxdepth 1 -iname "*.png" -print0 | xargs -0 stat -f "%m %N" | sort -n | cut -d' ' -f2-)
else
  echo "[gallery] スキップ（$GALLERY_DIR にPNGが見つかりません）"
fi
echo

echo "== 完了: $BUSINESS =="
echo "出力先: $OUTPUT_DIR"
echo "入力フォルダのPNG原本は変更していません。"
