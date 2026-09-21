# Cloudflare Billing & API Access (curl)

Simple curl-based access to Cloudflare APIs. Facts that matter (absorbed from the archived /cf-api command):

- General API token env var: `CLOUDFLARE_API_TOKEN`; account ID env var: `CLOUDFLARE_ACCOUNT_ID`
- General helper: `/home/peter/.claude/cf-api-helper.sh "accounts/${CLOUDFLARE_ACCOUNT_ID}/..."`
- Full endpoint reference: `/home/peter/.claude/cloudflare-api-reference.md`

## Setup

1. **Create token** (one-time):
   - Go to: https://dash.cloudflare.com/profile/api-tokens
   - Create token with: **Account → Billing → Read**
   - Copy token

2. **Set environment variable**:
   ```bash
   export CF_EGW_BILLING_READ="your_token_here"
   ```

## Quick Commands

**Get billing history**:
```bash
curl -s "https://api.cloudflare.com/client/v4/user/billing/history" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | jq .
```

**Get billing profile** (account ID: `e2ecc897eaa02effed7cb3cbc4beca1fa`):
```bash
curl -s "https://api.cloudflare.com/client/v4/accounts/e2ecc897eaa02effed7cb3cbc4beca1fa/billing/profile" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | jq .
```

## Helper Script

Use the bash helper for easier access:
```bash
/home/peter/.claude/cf-billing-helper-multi.sh profile --account egw
/home/peter/.claude/cf-billing-helper-multi.sh history --account egw
```

## Full Documentation

See: `~/.claude/CLOUDFLARE-MULTI-ACCOUNT.md`
