#!/usr/bin/env bash
# Diald — first-run setup
#
# Walks through local setup and connected-service guidance:
#   1. Required CLI tools (bun, Supabase CLI, and XcodeGen on macOS)
#   2. Optional CLI tools (Netlify CLI and psql)
#   3. Local iOS secrets
#   4. Supabase migrations
#   5. PowerSync guidance
#   6. Xcode project generation and optional simulator build
#
# Steps that depend on Supabase, PowerSync, App Store Connect, or Apple
# Developer access are clearly flagged at the end.

set -euo pipefail

cd "$(dirname "$0")"

# --- pretty printing -------------------------------------------------------
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
step()  { printf "\n${BLUE}${BOLD}==>${NC} ${BOLD}%s${NC}\n" "$1"; }
ok()    { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$1"; }
err()   { printf "${RED}✗${NC} %s\n" "$1"; }
note()  { printf "${DIM}  %s${NC}\n" "$1"; }

# --- platform check --------------------------------------------------------
is_mac() { [[ "${OSTYPE:-}" == darwin* ]]; }

if ! is_mac; then
    warn "This script is designed primarily for macOS. Web/Supabase steps work elsewhere; Xcode steps will be skipped."
fi

# --- 1. Required and optional tools ----------------------------------------
step "Checking required tools"
need() {
    local cmd="$1"; local hint="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd present"
    else
        err "$cmd not found — $hint"
        MISSING_TOOLS+=("$cmd")
    fi
}
MISSING_TOOLS=()

if is_mac; then
    if ! command -v brew >/dev/null 2>&1; then
        err "Homebrew is required on macOS — install from https://brew.sh"
        MISSING_TOOLS+=("brew")
    fi
    need xcodegen "install with: brew install xcodegen"
    need supabase "install with: brew install supabase/tap/supabase"
    need bun "install with: brew install oven-sh/bun/bun"
else
    need supabase "follow https://supabase.com/docs/guides/local-development/cli/getting-started"
    need bun "follow https://bun.sh/docs/installation"
fi

# Optional tools — report them but do not fail.
if command -v netlify >/dev/null 2>&1; then
    ok "netlify CLI present (optional)"
else
    note "netlify CLI not installed (optional). Use \`bunx netlify\` or, on macOS, \`brew install netlify-cli\`."
fi
if command -v psql >/dev/null 2>&1; then
    ok "psql present (optional)"
else
    note "psql not installed (optional). Migrations are applied with 'supabase db push'."
fi

if (( ${#MISSING_TOOLS[@]} > 0 )); then
    err "Install the missing tools above and re-run setup.sh."
    exit 1
fi

# --- 2. Local configuration ------------------------------------------------
step "Local configuration"

if [[ ! -f Config/Secrets.xcconfig ]]; then
    cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
    warn "Created Config/Secrets.xcconfig from the example — fill in real values before building."
else
    ok "Config/Secrets.xcconfig already exists; leaving it unchanged"
fi

note "Expected values: SUPABASE_URL, SUPABASE_ANON_KEY, and optional SENTRY_DSN."
note 'xcconfig warning: write literal "//" as "/$()/" (for example, https:/$()/…) because "//" starts a comment.'
note "OpenAI and Anthropic API keys are entered in Diald at runtime and stored in the Keychain, not in xcconfig."

# Detect the placeholders used by the committed example in either a newly
# created file or an existing local configuration.
if grep -Eq 'your-supabase-anon-key|your-project\.supabase\.co' Config/Secrets.xcconfig 2>/dev/null; then
    warn "Config/Secrets.xcconfig still contains placeholders. Edit it before building."
fi

# --- 3. Supabase project ---------------------------------------------------
step "Supabase project"

if [[ ! -f supabase/config.toml ]]; then
    note "Creating supabase/config.toml via supabase init"
    supabase init >/dev/null
fi

if ! supabase projects list >/dev/null 2>&1; then
    warn "supabase CLI is not logged in."
    note "Run: supabase login"
    note "Then link this repository: supabase link --project-ref <ref>"
    note "Find the project ref at: supabase.com → your project → Settings → General"
else
    ok "supabase CLI is logged in"

    if [[ ! -s supabase/.temp/project-ref ]]; then
        warn "This repository is not linked to a Supabase project."
        note "Run: supabase link --project-ref <ref>"
        note "Then re-run setup.sh to be offered the migration step."
    else
        ok "Supabase project link present"

        REPLY=""
        read -p "Apply Supabase migrations from supabase/migrations/ to your linked project now? [y/N] " -n 1 -r || true
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
fi

# --- 4. PowerSync ----------------------------------------------------------
step "PowerSync"

note "The future sync rules live at supabase/powersync/sync_rules.yaml."
note "Diald currently talks directly to Supabase; it is not offline-first."
note "No PowerSync client, local SQLite database, upload queue, or conflict lifecycle is wired into the app."
note "Applying these rules alone does not make Diald offline-first, and POWERSYNC_URL is not a required xcconfig value."
note "When a separate application implementation is ready, apply the rules via the PowerSync dashboard:"
note "  1. https://powersync.com → your instance → Sync rules"
note "  2. Paste the contents of supabase/powersync/sync_rules.yaml"
note "  3. Validate, then Deploy"

# --- 5. Xcode project ------------------------------------------------------
if is_mac; then
    step "Generate Xcode project"
    if [[ -d Diald.xcodeproj ]]; then
        rm -rf -- Diald.xcodeproj
    fi
    xcodegen generate
    ok "Generated Diald.xcodeproj"

    # Quick unsigned build against the simulator to catch major SDK breakage.
    if command -v xcodebuild >/dev/null 2>&1; then
        REPLY=""
        read -p "Run an unsigned simulator sanity build now? Takes a couple of minutes. [y/N] " -n 1 -r || true
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            xcodebuild build \
                -project Diald.xcodeproj \
                -scheme Diald \
                -configuration Debug \
                -destination 'generic/platform=iOS Simulator' \
                CODE_SIGNING_ALLOWED=NO \
                -quiet
            ok "Simulator build succeeded"
        else
            note "Skipped. Run later with:"
            note "  xcodebuild build -project Diald.xcodeproj -scheme Diald -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet"
        fi
    else
        note "xcodebuild is unavailable; skipping the optional simulator build."
    fi
fi

# --- 6. Summary ------------------------------------------------------------
step "Done — what's next"
cat <<'EOF'

Local setup is finished. Complete the applicable external-service and Apple
Developer tasks:

  1. Register the main App ID club.diald and the widget App ID
     club.diald.widgets.
  2. Enable Sign in with Apple and Push Notifications for the main app. Add
     both targets to App Group group.club.diald.
  3. In Supabase Authentication, enable Email, Apple, and Google providers
     and allow the callback URL diald://auth-callback.
  4. In Supabase Edge Functions, configure:
       SUPABASE_URL
       SUPABASE_SERVICE_ROLE_KEY
       APPLE_APP_ID (the numeric App Store app ID)
     Never place the service-role key in either app target or xcconfig.
  5. Verify the existing StoreKit/App Store Connect setup for
     club.diald.supporter.monthly, signing profiles for both targets, and
     App Store Server Notifications for iap-app-store-notifications as needed.
  6. In Xcode → Signing & Capabilities, select the correct paid signing team
     for Diald and DialdWidgets before running on a device or archiving.
  7. Deploy notify-brew-reminder only when its current behavior is appropriate:
       supabase functions deploy notify-brew-reminder
     It currently identifies and logs intended recipients; it does not perform
     production APNs delivery.

See README.md for the project setup overview.
EOF
