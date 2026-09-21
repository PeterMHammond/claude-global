#!/bin/bash
# Cloudflare Billing API Helper - Multi-Account
# Query billing data from any registered Cloudflare account
#
# Usage: cf-billing-helper-multi.sh [command] [--account NAME]
# Examples:
#   cf-billing-helper-multi.sh profile --account egw
#   cf-billing-helper-multi.sh history --account egw
#   cf-billing-helper-multi.sh list-accounts
#   cf-billing-helper-multi.sh help

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ACCOUNTS_FILE="${SCRIPT_DIR}/cf-accounts.yaml"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Parse arguments
COMMAND="${1:-profile}"
ACCOUNT="${3:-egw}"  # Default to 'egw' if --account not specified

# Override if --account appears first
if [ "$2" = "--account" ]; then
    ACCOUNT="$3"
    COMMAND="$1"
fi

BASE_URL="https://api.cloudflare.com/client/v4"

# Helper function to parse YAML using grep
get_account_value() {
    local account_name="$1"
    local field="$2"

    # Grep-based parsing: find account, then find field, extract value
    grep -A 30 "^  ${account_name}:" "$ACCOUNTS_FILE" | \
        grep "^\s*${field}:" | \
        head -1 | \
        sed 's/.*: *"\(.*\)".*/\1/' | \
        sed 's/.*: *\([^ ]*\) *#.*/\1/' | \
        sed 's/.*: *\([^ ]*\) *$/\1/' | \
        tr -d '"'
}

# Helper function to list all accounts
list_accounts() {
    echo -e "${BLUE}Registered Cloudflare Accounts:${NC}"
    echo ""
    # Extract account names from YAML (lines that start with "  name:")
    grep "^  [a-z].*:" "$ACCOUNTS_FILE" | sed 's/^  //g' | sed 's/:.*//g' | while read acct; do
        display=$(get_account_value "$acct" "display_name")
        id=$(get_account_value "$acct" "account_id")
        echo "  ${GREEN}$acct${NC} - $display"
        echo "    ID: $id"
        echo ""
    done
}

# Helper function to get token
get_token() {
    local account_name="$1"
    local token_type="${2:-billing_read}"  # Default to billing_read

    # Parse YAML to get env var name for the token type
    # Look for: account_name:, then tokens:, then token_type:, then env_var:
    local token_env
    token_env=$(awk "
        /^  ${account_name}:/{found=1}
        found && /^    tokens:/{in_tokens=1}
        in_tokens && /^      ${token_type}:/{in_token_type=1}
        in_token_type && /^        env_var:/{
            # Extract quoted string or unquoted value
            match(\$0, /\"([^\"]+)\"/, arr)
            if (arr[1]) {
                print arr[1]
            } else {
                gsub(/.*env_var:[[:space:]]*/, \"\")
                gsub(/[[:space:]]*#.*/, \"\")
                print
            }
            exit
        }
        # Exit if we hit next section
        /^  [a-z]/ && found && in_token_type {exit}
    " "$ACCOUNTS_FILE")

    if [ -z "$token_env" ]; then
        echo "Error: Token type '$token_type' not found for account '$account_name'"
        echo "Check: $ACCOUNTS_FILE"
        exit 1
    fi

    local token="${!token_env}"
    if [ -z "$token" ]; then
        echo "Error: $token_env environment variable not set"
        echo "Set it with: export $token_env=your_token"
        exit 1
    fi

    echo "$token"
}

# Main command handling
case "$COMMAND" in
    profile|billing-profile)
        ACCOUNT_ID=$(get_account_value "$ACCOUNT" "account_id")
        TOKEN=$(get_token "$ACCOUNT" "billing_read")

        if [ -z "$ACCOUNT_ID" ]; then
            echo "Error: Account '$ACCOUNT' not found"
            list_accounts
            exit 1
        fi

        ENDPOINT="accounts/${ACCOUNT_ID}/billing/profile"
        echo -e "${BLUE}Fetching billing profile for: ${GREEN}$ACCOUNT${NC}"
        ;;

    history|billing-history)
        TOKEN=$(get_token "$ACCOUNT" "billing_read")
        ENDPOINT="user/billing/history"
        echo -e "${BLUE}Fetching billing history for: ${GREEN}$ACCOUNT${NC}"
        ;;

    subscriptions)
        ACCOUNT_ID=$(get_account_value "$ACCOUNT" "account_id")
        TOKEN=$(get_token "$ACCOUNT" "billing_read")

        if [ -z "$ACCOUNT_ID" ]; then
            echo "Error: Account '$ACCOUNT' not found"
            exit 1
        fi

        ENDPOINT="accounts/${ACCOUNT_ID}/subscriptions"
        echo -e "${BLUE}Fetching subscriptions for: ${GREEN}$ACCOUNT${NC}"
        ;;

    list-accounts|list)
        list_accounts
        exit 0
        ;;

    help)
        echo "Cloudflare Billing API Helper - Multi-Account"
        echo ""
        echo "Usage: cf-billing-helper-multi.sh [command] [--account ACCOUNT_NAME]"
        echo ""
        echo "Commands:"
        echo "  profile             - Get billing profile (default)"
        echo "  history             - Get billing history and invoices"
        echo "  subscriptions       - Get account subscriptions"
        echo "  list-accounts       - List all registered accounts"
        echo "  help                - Show this help message"
        echo ""
        echo "Options:"
        echo "  --account NAME      - Account identifier (default: egw)"
        echo ""
        echo "Examples:"
        echo "  cf-billing-helper-multi.sh profile --account egw"
        echo "  cf-billing-helper-multi.sh history --account personal"
        echo "  cf-billing-helper-multi.sh list-accounts"
        echo ""
        echo "Setup:"
        echo "  1. Edit: $ACCOUNTS_FILE"
        echo "  2. Set token environment variables:"
        echo "     export CLOUDFLARE_API_TOKEN_EGW=your_token"
        echo "     export CLOUDFLARE_API_TOKEN_PERSONAL=your_other_token"
        echo ""
        exit 0
        ;;

    *)
        echo "Unknown command: $COMMAND"
        echo "Use 'cf-billing-helper-multi.sh help' for usage"
        exit 1
        ;;
esac

# Make API call
URL="${BASE_URL}/${ENDPOINT}"

if command -v jq &> /dev/null; then
    curl -s "$URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" | jq .
else
    curl -s "$URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json"
fi

echo ""
echo -e "${GREEN}✓ Request complete for account: ${ACCOUNT}${NC}"
