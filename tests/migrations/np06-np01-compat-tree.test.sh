#!/usr/bin/env bash
set -euo pipefail

prepare="$(cd "$(dirname "$0")" && pwd)/np06-np01-compat-tree.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

git init -q --initial-branch=finance "$scratch/source"
cd "$scratch/source"
git config user.name 'Compatibility fixture'
git config user.email 'compatibility@example.invalid'
git commit -q --allow-empty -m base
git switch -qc np01
echo reviewed > np01.sql
git add np01.sql
git commit -qm reviewed
reviewed_sha="$(git rev-parse HEAD)"
git update-ref refs/pull/111/head "$reviewed_sha"
git switch -q finance
echo finance > finance.sql
git add finance.sql
git commit -qm finance

git clone -q "$scratch/source" "$scratch/check"
cd "$scratch/check"
finance_sha="$(git rev-parse HEAD)"
bash "$prepare" "$reviewed_sha"
test "$(cat np01.sql)" = reviewed
test "$(git rev-parse HEAD)" = "$finance_sha"
git merge --abort

git -C "$scratch/source" commit -q --allow-empty -m 'changed PR head'
git -C "$scratch/source" update-ref refs/pull/111/head HEAD
if bash "$prepare" "$reviewed_sha" > "$scratch/moved.log" 2>&1; then
  echo 'Unreviewed NP01 PR revision was accepted' >&2
  exit 1
fi
grep -q NP01_REVIEW_HEAD_MOVED_REVERIFY_BEFORE_COMPAT "$scratch/moved.log"
test ! -e np01.sql
test -z "$(git status --porcelain)"

git -c user.name='Compatibility fixture' -c user.email='compatibility@example.invalid' \
  merge -q --no-ff -m integrated "$reviewed_sha"
echo 'integrated revision' > np01.sql
git -c user.name='Compatibility fixture' -c user.email='compatibility@example.invalid' \
  commit -qam 'integration correction'
git remote remove origin
bash "$prepare" "$reviewed_sha"
test "$(cat np01.sql)" = 'integrated revision'
test -z "$(git status --porcelain)"
echo NP06_NP01_COMPAT_TREE_PASS
