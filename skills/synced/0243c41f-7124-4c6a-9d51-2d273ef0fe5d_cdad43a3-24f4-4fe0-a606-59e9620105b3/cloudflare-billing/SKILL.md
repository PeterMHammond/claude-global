---
name: cloudflare-billing
description: Proactive Cloudflare billing monitor for EveryGoodWork account. Analyzes usage trends, predicts end-of-cycle costs, and warns before exceeding free tiers. Use when checking billing status, analyzing spend trends, or getting cost alerts. Triggers on queries about Cloudflare costs, usage, billing, or budget concerns.
---

# Cloudflare Billing Monitor

Access billing data via Cloudflare MCP at `https://bindings.mcp.cloudflare.com/sse`.

## Account: EveryGoodWork, Inc.

## Free Tier Limits (Workers Standard Plan)

| Product | Monthly Free Tier | Overage Rate |
|---------|-------------------|--------------|
| Workers Requests | 10,000,000 | $0.30/M |
| Workers CPU | 30,000,000 ms | $0.02/M ms |
| KV Storage | 1 GB | $0.50/GB-mo |
| KV Reads | 10,000,000 | $0.50/M |
| KV Writes | 1,000,000 | $5.00/M |
| KV Lists | 1,000,000 | $5.00/M |
| KV Deletes | 1,000,000 | $5.00/M |
| DO Requests | 1,000,000 | $0.15/M |
| DO Duration | 400,000 GB-s | $12.50/M GB-s |
| DO Storage | 1 GB-mo | $0.20/GB-mo |
| DO Reads | 1,000,000 | $0.20/M |
| DO Writes | 1,000,000 | $1.00/M |
| D1 Storage | 5 GB | $0.75/GB-mo |
| R2 Storage | 10 GB-mo | $0.015/GB-mo |
| R2 Class B Ops | 10,000,000 | $0.36/M |
| Vectorize Stored | 10,000,000 dim-mo | $0.01/M |
| Vectorize Queried | 50,000,000 | $0.04/M |
| Logs (Observability) | 20,000,000 | $0.05/M |
| Log Explorer | 10 GB | $0.60/GB |

### Stream (No Free Tier)
| Product | Rate |
|---------|------|
| Minutes Viewed | $1.00/1K min |
| Storage | $5.00/1K min stored |

## Trend Analysis Protocol

When analyzing billing data, execute this workflow:

### 1. Determine Billing Cycle Position
```
days_elapsed = current_date - billing_cycle_start
days_remaining = billing_cycle_end - current_date
cycle_progress = days_elapsed / total_days_in_cycle
```

### 2. Calculate Projected Usage
For each product with usage:
```
daily_average = total_usage / days_elapsed
projected_eom = daily_average * total_days_in_cycle
```

### 3. Assess Risk Level
Compare projected usage to free tier:
```
utilization_pct = (projected_eom / free_tier_limit) * 100

SAFE:     utilization_pct < 70%
WATCH:    utilization_pct 70-90%
WARNING:  utilization_pct 90-100%
OVERAGE:  utilization_pct > 100%
```

### 4. Calculate Potential Overage Cost
```
if projected_eom > free_tier_limit:
    overage_units = projected_eom - free_tier_limit
    projected_cost = overage_units * overage_rate
```

## Alert Output Format

Generate alerts for any product at WARNING or OVERAGE:

```
⚠️ BILLING ALERT: [Product Name]
   Current: [X] / [Free Limit] ([Y]% of limit)
   Projected EOM: [Z] ([W]% of limit)
   Risk: [WATCH|WARNING|OVERAGE]
   Est. Overage: $[amount] if trend continues
   
   Daily avg: [N] | Days remaining: [D]
```

## Trend Indicators

When comparing day-over-day:
- 📈 Increasing: today > 7-day avg
- 📉 Decreasing: today < 7-day avg  
- ➡️ Stable: within 10% of 7-day avg

## Analysis Checklist

1. Fetch current billing period usage from MCP
2. Calculate days elapsed/remaining in cycle
3. For each product:
   - Compute daily average and EOM projection
   - Compare to free tier limit
   - Flag if WARNING or OVERAGE risk
4. Identify day-over-day trend direction
5. Summarize: 
   - Products safely within limits
   - Products requiring attention
   - Total projected overage cost

## Quick Health Check Response

When asked "how's my billing?" or similar:

```
Cloudflare Billing Health - [Date]
Cycle: [Start] to [End] ([X]% complete)

✅ Within Limits: [list products]
⚠️ Watch: [list products approaching 70%+]
🚨 Action Needed: [list products projecting overage]

Projected Total Overage: $[X.XX]
```
