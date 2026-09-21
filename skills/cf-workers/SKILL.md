---
name: cf-workers
triggers:
  - wrangler deploy
  - cloudflare deploy
  - deploy worker
  - cloudflare billing
  - cloudflare api
description: Cloudflare Workers deployment patterns, API access, billing, and best practices. Automatically applies when deploying Workers or accessing Cloudflare APIs.
---

# Cloudflare Workers

## Deployment

**CRITICAL**: Always use `--keep-vars` when deploying if variables are set via dashboard:

```bash
wrangler deploy --keep-vars
```

Without this flag, wrangler **deletes all dashboard-set variables** (Text/JSON) and only keeps those in wrangler.toml.

**Note**: Secrets are NOT affected by this flag - they're managed separately and always preserved.

### Initial Setup Pattern (vars not in git)

To set up JSON vars without committing them to source control:

1. Add vars temporarily to wrangler.toml
2. Deploy normally: `wrangler deploy`
3. Remove vars from wrangler.toml before committing
4. Future deploys: `wrangler deploy --keep-vars`

## Variable Types

Cloudflare supports three variable types (set via dashboard):

| Type | Use Case | Access Method |
|------|----------|---------------|
| **Text** | Simple strings | `env.var("NAME")` → `Var` (string wrapper) |
| **JSON** | Structured config | `env.object_var::<T>("NAME")` → deserializes directly to struct |
| **Secret** | Sensitive data | `env.secret("NAME")` → `Secret` (string wrapper) |

### JSON Variables (Preferred for Config)

JSON type variables deserialize directly to Rust structs - no string parsing needed:

```rust
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SiteConfig {
    pub price: String,
    pub recipient_address: Option<String>,
    // ... fields match JSON keys (camelCase in JSON → snake_case in Rust)
}

// Clean access - no serde_json::from_str needed!
let config: SiteConfig = env.object_var("SITE_EXAMPLE_COM").unwrap_or_default();
```

### Text/Secret Variables

For text or secrets, you must parse strings manually:

```rust
// Text var
let value = env.var("NAME").map(|v| v.to_string()).unwrap_or_default();

// Secret (same pattern)
let secret = env.secret("API_KEY").map(|s| s.to_string()).unwrap_or_default();

// JSON stored as text/secret (avoid if possible - use JSON type instead)
let config: Config = env.secret("CONFIG")
    .map(|s| serde_json::from_str(&s.to_string()).unwrap_or_default())
    .unwrap_or_default();
```

## Variable Naming

Environment variable names cannot contain dots. Normalize hostnames:

```rust
// example.com → EXAMPLE_COM
// www.example.com → EXAMPLE_COM (strip www)
fn host_to_binding(host: &str) -> String {
    host.replace(['.', '-'], "_").to_uppercase()
}
```

**Namespace collision**: Service bindings and vars share a namespace. Use prefixes:
- Service binding: `EXAMPLE_COM`
- Site config var: `SITE_EXAMPLE_COM`

## Service Bindings

For worker-to-worker communication (faster than DNS):

```toml
# wrangler.toml
[[services]]
binding = "ORIGIN_WORKER"
service = "my-origin-worker"
```

```rust
// Try service binding first, fall back to DNS
let response = if let Ok(origin) = env.service("ORIGIN_WORKER") {
    origin.fetch_request(req).await?
} else {
    Fetch::Request(req).send().await?  // DNS passthrough
};
```

## wrangler.toml Best Practices

### JSON Variables via TOML Tables

TOML tables become JSON objects that work with `env.object_var()`:

```toml
[vars]
SIMPLE_VAR = "string"  # Text type

[vars.SITE_EXAMPLE_COM]  # JSON object - works with object_var!
price = "10000"
name = "Example Site"
recipientAddress = "0x..."
evmEnabled = true
```

This creates a JSON object accessible via `env.object_var::<SiteConfig>("SITE_EXAMPLE_COM")`.

### Sensitive Config Pattern

For config with sensitive data (addresses, keys), use TOML tables temporarily:

1. Add TOML table to wrangler.toml
2. Deploy: `wrangler deploy`
3. Remove from wrangler.toml, keep in `.dev.vars` as template
4. Future deploys: `wrangler deploy --keep-vars`

```toml
# .dev.vars (not committed) - template for reference
# [vars.SITE_EXAMPLE_COM]
# price = "10000"
# recipientAddress = "0x..."
```

## Queue Configuration

```toml
[[queues.producers]]
binding = "my_queue"
queue = "my-queue-name"

[[queues.consumers]]
queue = "my-queue-name"
max_batch_size = 10
max_retries = 5
dead_letter_queue = "my-queue-dlq"
```

## Common Patterns

### Boolean Environment Variables

```rust
// Clean pattern with map_or
let enabled = env.var("FEATURE_ENABLED")
    .map_or(false, |v| v.to_string().eq_ignore_ascii_case("true"));
```

### Request Forwarding to Durable Objects

**NEVER** create new Request objects when forwarding - preserves telemetry:

```rust
// GOOD: Use original request
let stub = env.durable_object("STATE")?.get_by_name(&id)?;
stub.fetch_with_request(req).await

// BAD: Creates new request, loses telemetry
stub.fetch_with_request(Request::new_with_init(...))?
```

## Secrets (Actual Sensitive Data)

Only use secrets for truly sensitive data:
- API keys (CDP_KEY_NAME, CDP_KEY_SECRET)
- Private keys (SOLANA_FEE_PAYER_KEY)
- Auth tokens (HELIUS_API_KEY)

Public data like blockchain addresses should use JSON type vars, not secrets.

---

# Cloudflare Billing & API Access

## When to Use

Apply this section when:
- Accessing Cloudflare API endpoints (especially billing data)
- Managing multiple Cloudflare accounts with different permission scopes
- Creating or using API tokens
- Querying billing history, profiles, or usage data
- Setting up monitoring or automation for Cloudflare resources

## Core Principles

1. **Scoped Tokens by Purpose** - Each token has ONE specific purpose (billing_read, workers_deploy, d1_admin, etc.)
   - Naming: `CF_{ACCOUNT}_{PURPOSE}_{PERMISSION}`
   - Example: `CF_EGW_BILLING_READ` for billing-only access
   - Principle: If compromised, only that function is exposed

2. **Environment Variable Storage** - Tokens NEVER in code or files
   - Store in shell environment: `export CF_EGW_BILLING_READ="token"`
   - OR in `.envrc` for direnv
   - OR via `wrangler secret` for production
   - Never in `.dev.vars`, `.env`, or version control

3. **Account Registry** - Single YAML source of truth
   - Location: `~/.claude/cf-accounts.yaml`
   - Defines all accounts, their IDs, and which tokens they need
   - Safe to commit (no secrets in it)

4. **Curl-Based Access** - Simple, no dependencies
   - Use curl with Bearer token in Authorization header
   - Base URL: `https://api.cloudflare.com/client/v4/`
   - All responses are JSON

## Multi-Account Setup

### 1. Define Accounts (cf-accounts.yaml)

```yaml
accounts:
  egw:
    account_id: "e2ecc897eaa02effed7cb3cbc4beca1fa"
    display_name: "EveryGoodWork"
    email: "peter@everygoodwork.dev"
    projects:
      - x402
      - orange
      - statetree
    tokens:
      billing_read:
        env_var: "CF_EGW_BILLING_READ"
        permissions: ["Account:Billing:Read"]
        purpose: "Read billing profile, invoices, subscriptions"

      workers_deploy:
        env_var: "CF_EGW_WORKERS_DEPLOY"
        permissions: ["Account:Workers Scripts:Edit"]
        purpose: "Deploy and manage Worker scripts"
```

### 2. Create Tokens

For each token type:
1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. Create token with appropriate permission
3. Copy immediately (won't see it again)
4. Set environment variable

Example: For billing_read token
```bash
# In Cloudflare dashboard:
# - Create Token
# - Name: "EGW Billing - Read Only"
# - Permission: Account → Billing → Read
# - Resources: Include > EveryGoodWork account

# In shell:
export CF_EGW_BILLING_READ="v1.0_abc123..."
```

### 3. Access via Curl

```bash
# Get billing history
curl -s "https://api.cloudflare.com/client/v4/user/billing/history" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | jq .

# Get billing profile
curl -s "https://api.cloudflare.com/client/v4/accounts/e2ecc897eaa02effed7cb3cbc4beca1fa/billing/profile" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | jq .

# Get subscriptions
curl -s "https://api.cloudflare.com/client/v4/accounts/e2ecc897eaa02effed7cb3cbc4beca1fa/subscriptions" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | jq .
```

## Common API Patterns

### Pattern: Check if Token is Available
```bash
if [ -z "$CF_EGW_BILLING_READ" ]; then
    echo "Error: Token not set"
    exit 1
fi
```

### Pattern: Fetch JSON and Parse
```bash
response=$(curl -s "https://api.cloudflare.com/client/v4/user/billing/history" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ")

# Check success
if echo "$response" | jq -e '.success' > /dev/null; then
    echo "$response" | jq '.result'
else
    echo "API error:"
    echo "$response" | jq '.errors'
fi
```

### Pattern: Multiple Accounts
When accessing different accounts, switch tokens:
```bash
# For EGW account (billing_read)
curl -s "https://api.cloudflare.com/client/v4/accounts/e2ecc897eaa02effed7cb3cbc4beca1fa/..." \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ"

# For personal account (different token, different account_id)
curl -s "https://api.cloudflare.com/client/v4/accounts/$PERSONAL_ACCOUNT_ID/..." \
  -H "Authorization: Bearer $CF_PERSONAL_BILLING_READ"
```

## API Endpoints Reference

### Billing Endpoints

**Get Billing History (user-level)**
```
GET /user/billing/history
Returns: Array of invoices and transactions
Required Token: Account:Billing:Read
```

**Get Billing Profile (account-level)**
```
GET /accounts/{account_id}/billing/profile
Returns: Billing contact, email, plan details
Required Token: Account:Billing:Read
```

**Get Subscriptions**
```
GET /accounts/{account_id}/subscriptions
Returns: All current subscriptions and plan details
Required Token: Account:Billing:Read
```

### Standard Response Format

All endpoints return:
```json
{
  "success": true/false,
  "errors": [],
  "messages": [],
  "result": { ... }  // or [ ... ] for arrays
}
```

Always check `"success"` field before using `"result"`.

## Constraints & What to Avoid

### Do NOT
- Hardcode tokens in code
- Store tokens in `.dev.vars`, `.env`, or version control
- Create one token for multiple purposes
- Use API keys (older auth) instead of API tokens
- Query the billing profile endpoint when you only need history (save bandwidth)
- Assume GraphQL Analytics API billing data matches actual billing (it doesn't)

### Do
- Use environment variables for all tokens
- Create separate tokens for separate purposes
- Use tokens scoped to specific accounts
- Check response success status before parsing result
- Include error details in any monitoring/logging
- Rotate tokens quarterly or if compromised
- Document which token each tool/script uses

## Troubleshooting

### 401 Unauthorized
- Token expired or incorrect format
- Token doesn't have required permission
- Wrong account_id for the token
- Solution: Create new token with correct permissions

### 403 Forbidden
- Token lacks permission for this endpoint
- Solution: Check token permissions in dashboard

### 404 Not Found
- Invalid account_id
- Wrong endpoint path
- Solution: Verify account_id and endpoint in API docs

### Empty Result
- Account may be new or have no data
- Query parameters might filter out all results
- Solution: Check account setup in Cloudflare dashboard

## Related Files

- Configuration: `cf-accounts.yaml` (in this skill folder)
- Helper Script: `cf-billing-helper-multi.sh` (bash wrapper)
- Documentation: `CLOUDFLARE-MULTI-ACCOUNT.md` (detailed setup)
- x402 Config: `/home/peter/Projects/EveryGoodWork/x402/wrangler.toml` (account_id)

## Examples

### Example 1: Fetch Billing History
```bash
curl -s "https://api.cloudflare.com/client/v4/user/billing/history" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | jq '.result'
```

Returns array of all invoices and transactions with structure:
```json
{
  "id": "unique-id",
  "type": "invoice|credit",
  "occurred_at": "2025-12-21T10:03:35Z",
  "amount": 43.05,
  "amount_to_pay": 0,
  "currency": "usd",
  "receipt_id": "IN-53746151",
  "status": "CLOSED|CREDIT_FULLY_APPLIED"
}
```

### Example 2: Analyze Recent Invoices & Calculate Expected Next Bill

**Get last 5 invoices with key details:**
```bash
curl -s "https://api.cloudflare.com/client/v4/user/billing/history" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | \
  jq '.result[:5] | .[] | {date: .occurred_at[0:10], amount: .amount, status: .status, type: .type}'
```

**Extract invoices only (ignore credits):**
```bash
curl -s "https://api.cloudflare.com/client/v4/user/billing/history" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | \
  jq '.result[] | select(.type=="invoice") | {date: .occurred_at[0:10], amount: .amount, status: .status, receipt: .receipt_id}'
```

**Calculate average monthly bill (last 10 invoices):**
```bash
curl -s "https://api.cloudflare.com/client/v4/user/billing/history" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | \
  jq '[.result[] | select(.type=="invoice") | .amount] | .[0:10] | add / length'
```

### Example 3: Find Outstanding Balance
```bash
curl -s "https://api.cloudflare.com/client/v4/user/billing/history" \
  -H "Authorization: Bearer $CF_EGW_BILLING_READ" | \
  jq '.result[] | select(.amount_to_pay > 0) | {date: .occurred_at[0:10], amount: .amount_to_pay, receipt: .receipt_id}'
```

### Example 4: Bash Helper Usage
```bash
# List accounts
/home/peter/.claude/cf-billing-helper-multi.sh list-accounts

# Get history for specific account
/home/peter/.claude/cf-billing-helper-multi.sh billing history --account egw
```

### Example 5: Complete Billing Analysis

When asked to check current expected bill:

1. **Fetch billing history** via `/user/billing/history`
2. **Extract recent invoices** (filter by type=="invoice")
3. **Calculate patterns**:
   - Average monthly amount (last 10 invoices)
   - Outstanding balance (sum amount_to_pay > 0)
   - Frequency of invoices (date gaps)
4. **Report findings**:
   - Recent amounts (last 5 invoices)
   - Average expected: Show range based on trend
   - Outstanding amounts: List items to be paid
5. **Important caveat**: API doesn't provide real-time current daily usage. For accurate "next bill" projection, direct user to: https://dash.cloudflare.com/e2ecc897eaa02effed7cb3cbc4beca1fa/billing/billable-usage

## Account Details (EveryGoodWork)

- **Account ID**: `e2ecc897eaa02effed7cb3cbc4beca1fa`
- **Token Variable**: `CF_EGW_BILLING_READ`
- **Available Tokens**: billing_read, workers_deploy, d1_admin, r2_admin
- **Projects**: x402, orange, statetree, quickmeet, quickmeetai

## Quick Links

**Real-time Billable Usage (Current Cycle)**:
https://dash.cloudflare.com/e2ecc897eaa02effed7cb3cbc4beca1fa/billing/billable-usage

This dashboard shows:
- Daily usage breakdown for current billing period
- Real-time cost projections
- Service-specific usage (Workers, D1, R2, KV, etc.)
- Most accurate source for "next bill" forecast
