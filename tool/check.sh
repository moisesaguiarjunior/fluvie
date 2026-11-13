#!/usr/bin/env bash
# The CI/local entry point. It checks this checkout, not an arbitrary package
# inferred from the caller's current directory. Git hooks use snapshots.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tool/hooks/lib.sh"

check_hook_suite "$root" || exit 1
# The upstream grep-gate self-test. A checkout that still has .githooks but
# lost the suite fails closed. Fixture repos have no .githooks and skip this.
if [ -d "$root/.githooks" ]; then
  if [ ! -f "$root/.githooks/test_hooks.sh" ]; then
    echo "hook checks: the upstream hook suite is missing." >&2
    exit 1
  fi
  (
    clear_git_environment
    cd "$root" || exit 1
    bash .githooks/test_hooks.sh || exit 1
  ) </dev/null || exit 1
fi
# Schemas are optional here. A tree with schemas and no suite fails closed.
check_spec "$root" || exit 1
status=0
pkglist="$(mktemp)"
if ! packages_for_check "$root" >"$pkglist"; then
  rm -f "$pkglist"
  exit 1
fi
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  echo "repository checks: ${pkg#"$root"/}"
  check_package "$pkg" || status=1
done <"$pkglist"
rm -f "$pkglist"
exit "$status"
