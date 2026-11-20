#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v bun >/dev/null || { echo 'Install Bun 1.4.4 first.'; exit 1; }
[[ "$(bun --version)" == '1.4.4' ]] || { echo 'Use Bun 1.4.4 to match CI and image builds.'; exit 1; }
if [[ ! -f Config/Secrets.xcconfig ]]; then
    cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
fi
(cd Backend && bun install --frozen-lockfile)
echo 'Configure API_URL, POWERSYNC_URL and optional SENTRY_DSN in Config/Secrets.xcconfig.'
echo 'Escape URLs as https:/$()/... in xcconfig files.'
echo 'Backend/deploy/README.md documents isolated development and gated deployment.'
if [[ "${OSTYPE:-}" == darwin* ]]; then
    command -v xcodegen >/dev/null || { echo 'Install XcodeGen with brew install xcodegen.'; exit 1; }
    xcodegen generate
    echo 'Open Diald.xcodeproj to build and run.'
fi
# Setup deliberately does not connect to or change the source production backend.
