#!/usr/bin/env bash
# usage: conflicts.sh [name] [--quiet]
# Warns about files changed by more than one active task, and (git >= 2.38)
# predicts merge conflicts with the integration branch. Exit 1 if any found.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
target=""; quiet=0
for a in "$@"; do case "$a" in --quiet) quiet=1;; *) target=$a;; esac; done
active() {
  local d n
  for d in "$AGENT_HOME"/tasks/*/; do
    [ -f "$d/state" ] || continue; n=$(basename "$d")
    case "$(state_get "$n" status)" in integrated|abandoned) continue;; esac
    echo "$n"
  done
}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for n in $(active); do changed_files "$n" > "$tmp/$n"; done
found=0
for a in $(active); do
  for b in $(active); do
    [ "$a" \< "$b" ] || continue
    [ -z "$target" ] || [ "$a" = "$target" ] || [ "$b" = "$target" ] || continue
    both=$(comm -12 "$tmp/$a" "$tmp/$b")
    if [ -n "$both" ]; then found=1; echo "overlap $a <-> $b: $(echo "$both" | tr '\n' ' ')"; fi
  done
done
if git merge-tree --write-tree HEAD HEAD >/dev/null 2>&1; then
  for n in $(active); do
    [ -z "$target" ] || [ "$n" = "$target" ] || continue
    out=$(git -C "$REPO_ROOT" merge-tree --write-tree --name-only "$INTEGRATION_BRANCH" "$(state_get "$n" branch)" 2>/dev/null) && continue
    files=$(printf '%s\n' "$out" | sed -n '2,/^$/p' | grep . | tr '\n' ' ')
    [ -n "$files" ] && { found=1; echo "merge conflict predicted $n -> $INTEGRATION_BRANCH: $files"; }
  done
fi
[ $found = 0 ] && [ $quiet = 0 ] && echo "no overlaps or predicted conflicts"
[ $found = 0 ]
