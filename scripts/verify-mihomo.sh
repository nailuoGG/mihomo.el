#!/bin/sh
set -eu
unset CDPATH

MIHOMO_VERSION=v1.19.33
MIHOMO_ASSET="mihomo-darwin-arm64-${MIHOMO_VERSION}.gz"
MIHOMO_SHA256=060b64b0f2c9a310831db0fe4adb2878de67bfa606c311813c1f13966aa504b6
MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/${MIHOMO_ASSET}"

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo "error: this verifier supports only Darwin arm64" >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repository_dir=$(dirname -- "$script_dir")
fixture="$repository_dir/test/fixtures/minimal.yaml"
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/mihomo-el-verify.XXXXXX")
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM

archive=${1:-"$temporary_dir/$MIHOMO_ASSET"}
binary="$temporary_dir/mihomo"
invalid_config="$temporary_dir/invalid.yaml"
invalid_output="$temporary_dir/invalid-output.log"

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [mihomo-release.gz]" >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  if [ ! -f "$archive" ]; then
    echo "error: archive not found: $archive" >&2
    exit 2
  fi
  echo "Using local Mihomo archive: $archive"
else
  echo "Downloading Mihomo $MIHOMO_VERSION for Darwin arm64"
  curl --fail --location --silent --show-error \
    --http1.1 --retry 3 --retry-delay 2 \
    --output "$archive" "$MIHOMO_URL"
fi

actual_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
if [ "$actual_sha256" != "$MIHOMO_SHA256" ]; then
  echo "error: checksum mismatch for $MIHOMO_ASSET" >&2
  echo "expected: $MIHOMO_SHA256" >&2
  echo "actual:   $actual_sha256" >&2
  exit 1
fi

gzip -dc "$archive" >"$binary"
chmod 700 "$binary"

"$binary" -v
"$binary" -t -f "$fixture"
echo "Valid fixture accepted: $fixture"

printf '%s\n' 'mode: [' >"$invalid_config"
if "$binary" -t -f "$invalid_config" >"$invalid_output" 2>&1; then
  echo "error: Mihomo accepted the intentionally invalid fixture" >&2
  exit 1
fi

if ! grep -Eiq 'line[[:space:]]+[0-9]+|yaml|unmarshal' "$invalid_output"; then
  echo "error: invalid fixture failed without a recognizable syntax diagnostic" >&2
  cat "$invalid_output" >&2
  exit 1
fi

echo "Invalid fixture rejected with real Mihomo output:"
cat "$invalid_output"
