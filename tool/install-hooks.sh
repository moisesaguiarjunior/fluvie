#!/usr/bin/env bash
# Points git to the versioned hooks in tool/hooks.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
chmod +x tool/hooks/*
git config core.hooksPath tool/hooks
echo "Hooks installed (core.hooksPath=tool/hooks)."
