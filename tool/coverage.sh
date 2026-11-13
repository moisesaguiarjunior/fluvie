#!/usr/bin/env bash
# Line coverage for the two core SDK packages, excluding the CLI.
#
# Uses the same exclusions as tool/check.sh. Golden, snapshot, ffmpeg, wasm,
# render, and generative tests stay out. This is not the upstream 97%
# workspace gate.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

exclude='golden || snapshot || ffmpeg || wasm || render || generative'
for pkg in packages/fluvie packages/fluvie_mobile_encoder; do
  echo "coverage: $pkg"
  (
    cd "$pkg"
    flutter test --coverage --exclude-tags "$exclude"
  )
done

dart tool/check_coverage.dart --min 0 packages/fluvie packages/fluvie_mobile_encoder

mkdir -p coverage
{
  sed 's|^SF:|SF:packages/fluvie/|' packages/fluvie/coverage/lcov.info
  sed 's|^SF:|SF:packages/fluvie_mobile_encoder/|' packages/fluvie_mobile_encoder/coverage/lcov.info
} > coverage/lcov.info
echo "coverage: wrote coverage/lcov.info"
