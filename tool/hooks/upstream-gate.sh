#!/usr/bin/env bash
# Staged half of the upstream .githooks/pre-commit gate: forbidden text,
# the 200-line budget, documentation voice, and dart format.
#
# Workspace-wide `dart analyze` is not run here. On the Flutter pin this
# fork uses for review (3.47.9), infos outside the maintained packages are
# not this gate's job. check_package analyzes the maintained packages with
# infos fatal. The patterns themselves still come from .githooks/_lib.sh,
# so deleting that file fails closed when .githooks is present.
#
# Written for bash 3.2 and newer: no mapfile.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
if [ ! -d .githooks ]; then
  exit 0
fi
if [ ! -f .githooks/_lib.sh ]; then
  echo "upstream gate: .githooks/_lib.sh is missing." >&2
  exit 1
fi
# shellcheck source=../../.githooks/_lib.sh
source .githooks/_lib.sh

fail=0

while IFS= read -r f; do
  [ -z "$f" ] && continue
  content="$(git show ":$f" 2>/dev/null || true)"
  for entry in "${FORBIDDEN_PATTERNS[@]}"; do
    pat="${entry%%|*}"
    msg="${entry#*|}"
    if grep -qE "$pat" <<<"$content"; then
      echo "✗ $f: $msg"
      fail=1
    fi
  done
  if [[ "$f" != packages/fluvie_lints/* ]]; then
    code_only="$(printf '%s\n' "$content" | strip_dart_comments_and_strings)"
    if [ "${#FORBIDDEN_CODE_PATTERNS[@]}" -gt 0 ]; then
      for entry in "${FORBIDDEN_CODE_PATTERNS[@]}"; do
        pat="${entry%%|*}"
        msg="${entry#*|}"
        if grep -qE "$pat" <<<"$code_only"; then
          echo "✗ $f: $msg"
          fail=1
        fi
      done
    fi
  fi
  if [[ "$f" != */test/* && "$f" != test/* && "$content" != *fluvie:large-file-ok* ]]; then
    lines="$(printf '%s\n' "$content" | wc -l | tr -d ' ')"
    if [ "$lines" -gt "$MAX_FILE_LINES" ]; then
      echo "✗ $f: $lines lines exceeds the $MAX_FILE_LINES-line budget — extract."
      fail=1
    fi
  fi
done < <(staged_dart_files)

while IFS= read -r f; do
  [ -z "$f" ] && continue
  content="$(git show ":$f" 2>/dev/null || true)"
  # python, not grep -P: the dash check has to run where PCRE grep is absent.
  if printf '%s' "$content" | python3 -c 'import sys; data=sys.stdin.read(); raise SystemExit(0 if ("\u2013" in data or "\u2014" in data) else 1)'; then
    echo "✗ $f: em/en-dash found. Use a comma, period, or parentheses."
    fail=1
  fi
  if grep -qiE "\\b($DOCS_BANNED_WORDS)\\b" <<<"$content"; then
    echo "✗ $f: marketing vocabulary found ($DOCS_BANNED_WORDS)."
    fail=1
  fi
  naked="$(printf '%s\n' "$content" | naked_dart_fences)"
  if [ -n "$naked" ]; then
    for ln in $naked; do
      echo "✗ $f:$ln: naked \`\`\`dart fence — add a <!-- code-excerpt \"<file> (<region>)\" --> directive (or code-excerpt-ignore)."
    done
    fail=1
  fi
done < <(staged_docs_files)

dart_files=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  dart_files+=("$f")
done < <(staged_dart_files)
if [ "${#dart_files[@]}" -gt 0 ]; then
  if ! dart format --output=none --set-exit-if-changed "${dart_files[@]}" >/dev/null 2>&1; then
    echo "✗ formatting — run 'melos run format:fix'"
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Upstream pre-commit gate failed (grep, size, docs voice, format)."
  exit 1
fi
