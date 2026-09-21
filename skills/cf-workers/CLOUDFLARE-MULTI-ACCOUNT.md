# Cloudflare Multi-Account Skill System

Centralized management of multiple Cloudflare accounts from a single global `.claude/` location.

## Overview

**Problem**: You have multiple separate Cloudflare accounts. Previously, you'd need separate skills for each.

**Solution**: One registry-based system that manages all accounts with simple command-line switching.

## File Structure

```
~/.claude/
├── cf-accounts.yaml                    # Account registry (define all accounts here)
├── cf-accounts/                        # Per-account documentation (optional)
│   ├── egw.md                          # EveryGoodWork account notes
│   ├── personal.md
│   └── client-x.md
├── cf-billing-helper-multi.sh          # Smart billing helper (switches accounts)
├── cf-api-helper.sh                    # Generic API helper (unchanged)
├── cf-api-reference.md                 # General reference (unchanged)
└── cloudflare-multi-account-setup.md   # This file
```

## Setup (One-Time)

### 1. Define Your Accounts

Edit: `~/.claude/cf-accounts.yaml`

```yaml
accounts:
  egw:
    account_id: "e2ecc897eaa02effed7cb3cbc4beca1fa"
    display_name: "EveryGoodWork"
    token_env: "CLOUDFLARE_API_TOKEN_EGW"
    projects:
      - x402
      - orange
      - statetree

  personal:
    account_id: "your_personal_account_id"
    display_name: "Personal Projects"
    token_env: "CLOUDFLARE_API_TOKEN_PERSONAL"
    projects:
      - personal-worker

  client-x:
    account_id: "client_account_id"
    display_name: "Client X Account"
    token_env: "CLOUDFLARE_API_TOKEN_CLIENT_X"
    projects:
      - client-project
```

**Fields:**
- `account_id` - Your Cloudflare account ID
- `display_name` - Human-readable name
- `token_env` - Environment variable name for this account's token (must be unique)
- `projects` - Projects that belong to this account (optional, for documentation)

### 2. Create Tokens for Each Account

For each account in `cf-accounts.yaml`:

1. Go to: `https://dash.cloudflare.com/profile/api-tokens`
2. Create token with **Account → Billing → Read** permission
3. Copy token

### 3. Store Tokens as Environment Variables

Never store tokens in files. Set them in your shell profile or `.envrc`:

**In `~/.bashrc` or `~/.zshrc`:**
```bash
# Cloudflare API Tokens (keep private!)
export CLOUDFLARE_API_TOKEN_EGW="your_egw_token_here"
export CLOUDFLARE_API_TOKEN_PERSONAL="your_personal_token_here"
export CLOUDFLARE_API_TOKEN_CLIENT_X="your_client_token_here"
```

**Or use `.envrc` with direnv:**
```bash
export CLOUDFLARE_API_TOKEN_EGW="your_egw_token_here"
export CLOUDFLARE_API_TOKEN_PERSONAL="your_personal_token_here"
export CLOUDFLARE_API_TOKEN_CLIENT_X="your_client_token_here"
```

### 4. Test

```bash
# List all registered accounts
/home/peter/.claude/cf-billing-helper-multi.sh list-accounts

# Get billing profile from egw account
/home/peter/.claude/cf-billing-helper-multi.sh profile --account egw

# Get billing history from personal account
/home/peter/.claude/cf-billing-helper-multi.sh history --account personal
```

## Usage

### List All Accounts

```bash
/home/peter/.claude/cf-billing-helper-multi.sh list-accounts
```

Output:
```
Registered Cloudflare Accounts:

  egw - EveryGoodWork
    ID: e2ecc897eaa02effed7cb3cbc4beca1fa

  personal - Personal Projects
    ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  client-x - Client X Account
    ID: yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
```

### Get Billing Profile

```bash
# From default account (egw)
/home/peter/.claude/cf-billing-helper-multi.sh profile

# From specific account
/home/peter/.claude/cf-billing-helper-multi.sh profile --account personal
/home/peter/.claude/cf-billing-helper-multi.sh profile --account client-x
```

### Get Billing History

```bash
/home/peter/.claude/cf-billing-helper-multi.sh history --account egw
```

### Get Subscriptions

```bash
/home/peter/.claude/cf-billing-helper-multi.sh subscriptions --account personal
```

## Integration with Projects

### Per-Project wrangler.toml

Each project specifies its account_id in `wrangler.toml`:

**x402 (`/home/peter/Projects/EveryGoodWork/x402/wrangler.toml`):**
```toml
account_id = "e2ecc897eaa02effed7cb3cbc4beca1fa"
```

**personal-worker (`~/projects/personal-worker/wrangler.toml`):**
```toml
account_id = "your_personal_account_id"
```

### Per-Project .dev.vars

Each project has its own `.dev.vars` with its account's token:

**x402 (`.dev.vars`):**
```
CLOUDFLARE_API_TOKEN=content_of_CLOUDFLARE_API_TOKEN_EGW
```

**personal-worker (`.dev.vars`):**
```
CLOUDFLARE_API_TOKEN=content_of_CLOUDFLARE_API_TOKEN_PERSONAL
```

## Advanced Usage

### Create a Bash Alias

Add to `~/.bashrc` or `~/.zshrc`:

```bash
alias cf-billing='~/.claude/cf-billing-helper-multi.sh'
alias cf-api='~/.claude/cf-api-helper.sh'
```

Then use:
```bash
cf-billing profile --account egw
cf-billing history --account personal
```

### Shell Function for Quick Access

```bash
# ~/.bashrc or ~/.zshrc
cf() {
    case "$1" in
        egw)
            account="egw"
            shift
            /home/peter/.claude/cf-billing-helper-multi.sh "$@" --account "$account"
            ;;
        personal)
            account="personal"
            shift
            /home/peter/.claude/cf-billing-helper-multi.sh "$@" --account "$account"
            ;;
        *)
            /home/peter/.claude/cf-billing-helper-multi.sh list-accounts
            ;;
    esac
}
```

Usage:
```bash
cf egw profile
cf personal history
cf list-accounts
```

### Scripted Account Switching

```bash
#!/bin/bash
# Deploy to all accounts
for account in egw personal client-x; do
    echo "Deploying to: $account"
    /home/peter/.claude/cf-billing-helper-multi.sh profile --account "$account"
done
```

## Security Best Practices

✅ **Tokens in environment, not files** - Never add `CLOUDFLARE_API_TOKEN_*` to `.dev.vars`
✅ **One token per account** - Separate `CLOUDFLARE_API_TOKEN_EGW`, `CLOUDFLARE_API_TOKEN_PERSONAL`
✅ **Registry in git, secrets in environment** - `cf-accounts.yaml` can be checked in, tokens are private
✅ **Read-only tokens** - Each token has only **Billing → Read** permission
✅ **Rotate quarterly** - Update environment variables with new tokens
✅ **Use direnv** - Automatically load tokens when entering project directory

## Troubleshooting

### "Account not found" Error

```bash
# Check if account is registered
/home/peter/.claude/cf-billing-helper-multi.sh list-accounts

# Verify it's in cf-accounts.yaml with correct name
```

### "Token not set" Error

```bash
# Verify environment variable is set
echo $CLOUDFLARE_API_TOKEN_EGW

# If empty, set it
export CLOUDFLARE_API_TOKEN_EGW=your_token_here

# Or add to ~/.bashrc permanently
```

### "Invalid token" Error (401)

```bash
# Token might be expired or wrong
# Regenerate in Cloudflare dashboard
# https://dash.cloudflare.com/profile/api-tokens

# Verify you updated the environment variable
echo $CLOUDFLARE_API_TOKEN_EGW
```

### YAML Parsing Issues

The script works with or without `yq` installed:
- **With yq**: Full YAML parsing
- **Without yq**: Fallback grep-based parsing

Install `yq` for better reliability:
```bash
# macOS
brew install yq

# Linux (Arch)
sudo pacman -S yq

# Linux (Ubuntu)
sudo apt install yq
```

## File Locations

| File | Purpose | Location |
|------|---------|----------|
| `cf-accounts.yaml` | Account registry | `~/.claude/` |
| `cf-billing-helper-multi.sh` | Multi-account billing helper | `~/.claude/` |
| `cf-api-helper.sh` | Generic API helper | `~/.claude/` |
| `wrangler.toml` | Project config with account_id | Per project |
| `.dev.vars` | Project secrets (token) | Per project |

## Adding New Accounts

1. Edit `~/.claude/cf-accounts.yaml`
2. Add account section:
   ```yaml
   new-account:
     account_id: "account_id_here"
     display_name: "Display Name"
     token_env: "CLOUDFLARE_API_TOKEN_NEW_ACCOUNT"
   ```
3. Create token in Cloudflare dashboard
4. Set environment variable:
   ```bash
   export CLOUDFLARE_API_TOKEN_NEW_ACCOUNT=your_token
   ```

## Removing Accounts

1. Edit `~/.claude/cf-accounts.yaml`
2. Remove account section
3. Optionally unset environment variable:
   ```bash
   unset CLOUDFLARE_API_TOKEN_ACCOUNT_NAME
   ```

---

**Status**: ✅ Production Ready
**Last Updated**: 2026-01-05
**Supports**: Multiple separate Cloudflare accounts with single registry
