#!/usr/bin/env bash
set -euo pipefail

missing=0
for tool in xcodegen supabase; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing: $tool"
    missing=1
  fi
done

if [ ! -f Config/Secrets.xcconfig ]; then
  cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
  echo "created Config/Secrets.xcconfig; fill Supabase values before building"
fi

if [ "$missing" -eq 1 ]; then
  echo "install missing tools, then rerun"
  exit 1
fi

xcodegen generate
echo "generated Diald.xcodeproj"
