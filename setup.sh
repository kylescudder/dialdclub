#!/usr/bin/env bash
# Diald - first-run setup
#
# Mirrors the Deadwax Club setup shape:
#   1. Required CLI tools
#   2. Local secrets file
#   3. Supabase migrations
#   4. PowerSync sync rules pointer
#   5. Xcode project generation
#   6. Sanity verification

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
step() { printf "\n${BLUE}${BOLD}==>${NC} ${BOLD}%s${NC}\n" "$1"; }
ok()   { printf "${GREEN}ok${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }
err()  { printf "${RED}x${NC} %s\n" "$1"; }
note() { printf "${DIM}  %s${NC}\n" "$1"; }

is_mac() { [[ "${OSTYPE:-}" == darwin* ]]; }

if ! is_mac; then
  warn "This script is designed for macOS. Supabase steps work elsewhere; Xcode steps will be skipped."
fi

step "Checking required tools"
MISSING_TOOLS=()
need() {
  local cmd="$1"
  local hint="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd present"
  else
    err "$cmd not found - $hint"
    MISSING_TOOLS+=("$cmd")
  fi
}

if is_mac; then
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew is required on macOS - install from https://brew.sh"
    MISSING_TOOLS+=("brew")
  fi
  need xcodegen "brew install xcodegen"
fi
need supabase "brew install supabase/tap/supabase"

if command -v psql >/dev/null 2>&1; then
  ok "psql present (optional)"
else
  note "psql not installed. Migrations can be applied via 'supabase db push'."
fi

if (( ${#MISSING_TOOLS[@]} > 0 )); then
  err "Install the missing tools above and re-run setup.sh."
  exit 1
fi

step "Local secrets"

if [[ ! -f Config/Secrets.xcconfig ]]; then
  cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
  warn "Created Config/Secrets.xcconfig from the example - fill in real values before building."
  note "  SUPABASE_URL, SUPABASE_ANON_KEY, optional SENTRY_DSN"
else
  ok "Config/Secrets.xcconfig already exists"
fi

if grep -q "your-supabase-anon-key\|your-project.supabase.co" Config/Secrets.xcconfig 2>/dev/null; then
  warn "Config/Secrets.xcconfig still contains placeholders. Edit it before building."
fi

step "Supabase project"

if [[ ! -f supabase/config.toml ]]; then
  note "Creating supabase/config.toml via supabase init"
  supabase init >/dev/null
fi

if ! supabase projects list >/dev/null 2>&1; then
  warn "supabase CLI is not logged in. Run 'supabase login' and 'supabase link --project-ref <ref>', then re-run."
  note "Find the project ref at: supabase.com -> your project -> Settings -> General"
else
  ok "supabase CLI is logged in"

  read -p "Apply Supabase migrations from supabase/migrations/ to your linked project now? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    supabase db push
    ok "Migrations applied"
  else
    note "Skipped. To apply manually:"
    note "  supabase db push"
    note "Or paste each file in supabase/migrations/ into the Supabase SQL editor in order."
  fi
fi

step "PowerSync"
note "Sync rules live at supabase/powersync/sync_rules.yaml."
note "Apply them in the PowerSync dashboard when the app is ready for the offline-first pass."

if is_mac; then
  step "Generate Xcode project"
  if [[ -d Diald.xcodeproj ]]; then
    rm -rf Diald.xcodeproj
  fi
  xcodegen generate
  ok "Generated Diald.xcodeproj"

  if command -v xcodebuild >/dev/null 2>&1; then
    read -p "Run a sanity simulator build now? Takes a couple of minutes. [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      xcodebuild build \
        -project Diald.xcodeproj \
        -scheme Diald \
        -destination 'generic/platform=iOS Simulator' \
        -quiet
      ok "Simulator build succeeded"
    else
      note "Skipped. Run later with: xcodebuild build -project Diald.xcodeproj -scheme Diald -destination 'generic/platform=iOS Simulator'"
    fi
  fi
fi

step "Done - what's next"
cat <<'EOF'

Local setup is finished. The remaining work needs Apple Developer access:

  1. Register App ID club.diald with Sign in with Apple,
     Push Notifications, App Groups, and Associated Domains if you add web links.
  2. Create APNs/Auth keys as needed for Apple sign-in and server-side reminders.
  3. Supabase -> Authentication -> Providers: enable Email, Apple, and Google.
     Set redirect URLs to diald://auth-callback.
  4. Supabase -> Edge Functions -> Secrets:
       SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
     Add APNs secrets before replacing notify-brew-reminder's placeholder fan-out.
  5. Deploy the reminder function when ready:
       supabase functions deploy notify-brew-reminder
  6. In Xcode -> Signing & Capabilities, pick your paid team,
     plug your phone in, Command-R.

See README.md for the full step-by-step.
EOF
