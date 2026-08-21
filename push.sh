#!/bin/bash
# RESC リポジトリ用 push スクリプト
#   ./push.sh "メッセージ"            … 変更を全部コミットして push
#   ./push.sh "メッセージ" samples/    … 指定したパスだけコミットして push
#   ./push.sh                         … いまの変更を確認するだけ

cd "$(dirname "$0")" || exit 1

# AIがgit操作をすると消せないロックが残るので、毎回まず消す
if [ -f .git/index.lock ]; then
  rm -f .git/index.lock && echo "🔓 残っていたロックを削除しました"
fi

# FUSEの残骸が混入していたら止める
if git status --porcelain | grep -q 'fuse_hidden'; then
  echo "⚠️  .fuse_hidden の残骸が検出されました。先に削除してください:"
  git status --porcelain | grep 'fuse_hidden'
  exit 1
fi

MSG="$1"
TARGET="${2:-.}"

if [ -z "$MSG" ]; then
  echo "▼ いまの変更"
  git status --short
  echo
  echo "使い方:"
  echo "  ./push.sh \"コミットメッセージ\""
  echo "  ./push.sh \"コミットメッセージ\" samples/"
  exit 0
fi

echo "▼ コミットする内容（対象: $TARGET）"
git add "$TARGET"
git status --short --cached
COUNT=$(git diff --cached --name-only | wc -l | tr -d ' ')
echo
if [ "$COUNT" -eq 0 ]; then
  echo "変更がありません。"
  exit 0
fi
echo "$COUNT ファイル"
echo
read -r -p "この内容で push しますか？ [y/N] " ans
if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
  git reset >/dev/null
  echo "中止しました（ステージも戻しました）"
  exit 0
fi

git commit -m "$MSG" || exit 1
git push || exit 1
echo
echo "✅ push 完了"
git log --oneline -1
