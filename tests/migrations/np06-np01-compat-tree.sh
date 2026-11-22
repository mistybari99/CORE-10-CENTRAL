#!/usr/bin/env bash
set -euo pipefail

reviewed_sha="${1:?expected the reviewed NP01 commit SHA}"

# Once integrated, run against the actual checkout, including integration fixes.
if git merge-base --is-ancestor "$reviewed_sha" HEAD 2>/dev/null; then
  echo "NP01_COMPAT_INTEGRATED_SHA=$reviewed_sha"
  exit 0
fi

# Before integration, a moving PR must be reviewed again before it can enter CI.
git fetch --no-tags origin refs/pull/111/head
np01_sha="$(git rev-parse FETCH_HEAD)"
if [[ "$np01_sha" != "$reviewed_sha" ]]; then
  echo "NP01_REVIEW_HEAD_MOVED_REVERIFY_BEFORE_COMPAT expected=$reviewed_sha actual=$np01_sha" >&2
  exit 1
fi

git -c user.name='NP06 CI Reviewer' -c user.email='ci-review@example.invalid' \
  merge --no-commit --no-ff "$reviewed_sha"
test -z "$(git ls-files -u)"
echo "NP01_COMPAT_LOCAL_COMBINATION_SHA=$reviewed_sha"
