# Patterns & Evidence

Before/after patterns for each principle, in Datastar + Askama idiom. Adapt to whatever stack you're auditing — the principle is the constant, the code is not.

## 1 — Smart defaults

**Before:** five empty `<input>` fields; button says "Search."
**After:** fields pre-filled with the most common choice; the action reports what's waiting.

```html
<!-- Askama + Datastar: seed signals with sensible defaults, not empty strings -->
<div data-signals="{guests: 2, nights: 1, city: '{{ default_city }}'}">
  <input data-bind="city">
  <input type="number" data-bind="guests">
  <!-- button carries the payoff, computed live -->
  <button data-on:click="@post('/search')">
    Search (<span data-text="$result_count"></span> results)
  </button>
</div>
```

Server pre-computes `default_city` and an initial `result_count` so the count is non-empty on first paint.

## 2 — Endowed progress

**Before:** onboarding meter at 0%, "0 of 5 complete."
**After:** account creation already counts as step one → 20%.

```html
<!-- meter starts non-zero because signing up IS step 1 -->
<div class="progress"><div class="bar" style="width: {{ percent }}%"></div></div>
<p>{{ done }} of {{ total }} — you're already started</p>
```

Server sets `percent = done * 100 / total` with `done >= 1` from the moment the account exists. LinkedIn's profile-strength meter is never at zero.

## 3 — Reciprocity

**Before:** result blurred behind "Create an account to see your report."
**After:** show the real score + top issues; gate only the full breakdown.

```html
{% if scan_done %}
  <div class="report">
    <p class="score">Score: {{ score }}/100</p>
    <ul>{% for issue in top_issues %}<li>{{ issue }}</li>{% endfor %}</ul>
  </div>
  <div class="upsell">
    <p>Want the complete breakdown with step-by-step fixes?</p>
    <button data-on:click="@post('/save-report')">Save your report</button>
  </div>
{% endif %}
```

Deliver something genuinely useful before asking. Costco samples, Spotify's 30 days, Notion's free tier — value first, ask second.

## 4 — Endowment / IKEA effect

**Before:** signup screen is email + password; nothing to lose by closing the tab.
**After:** user builds their thing (name, palette, first item) *before* any account ask.

```html
<!-- everything below is local state until they choose to persist it -->
<div data-signals="{name: '', palette: 'slate', style: 'card'}">
  <input data-bind="name" placeholder="Name your project">
  <!-- palette / style pickers bind to signals; live preview renders from them -->
  <div class="preview" data-text="$name"></div>
  <button data-on:click="@post('/continue')">Continue</button>  <!-- not "Sign up" -->
</div>
```

By the signup screen they've invested effort — leaving now means abandoning something they made. Duolingo: pick language, set goal, finish lesson one, *then* the account ask.

## 5 — Loss aversion

**Before:** "Upgrade now" / "Maybe later" — nothing at stake.
**After:** name what's actually at risk; the dismiss owns the risk.

```html
<div class="upgrade">
  <p>These files exceed your free storage and will be deleted:</p>
  <ul>{% for f in at_risk_files %}<li>{{ f.name }}</li>{% endfor %}</ul>
  <button data-on:click="@post('/upgrade')">Keep my files</button>
  <button data-on:click="$dismissed = true">I'll risk it</button>
</div>
```

Only truthful when the loss is real (`at_risk_files` genuinely will be removed per policy). If nothing is actually lost, do not use this framing — see the truthfulness guardrail.

## 6 — Anchoring / contrast

**Before:** protection plan shown alone at $50/mo → reads as "$600/year, no."
**After:** shown right under the $1,900 item, expressed as a fraction of it.

```html
<div class="cart-item">{{ product.name }} — ${{ product.price }}</div>
<div class="addon">
  Protection plan — ${{ addon_monthly }}/mo
  <span class="ratio">just {{ addon_pct }}% of your purchase</span>
</div>
```

Server computes `addon_pct` from the real item price. Restaurants anchor the $40 salmon with a $90 steak; agents show the overpriced house first. Control the first number the eye lands on — but the anchor must be a real price, not a fake strikethrough.

## Research citations

- **Choice overload** — Iyengar & Lepper (Columbia): 24 jam flavors → 3% bought; 6 → 30%.
- **Goal-gradient / endowed progress** — Nunes & Drèze car-wash study: pre-stamped cards nearly doubled completion.
- **Reciprocity** — Cialdini, *Influence*; free samples lift purchases dramatically.
- **Endowment / IKEA effect** — Norton, Mochon & Ariely; Kahneman/Knetsch/Thaler on endowment.
- **Loss aversion** — Kahneman & Tversky, prospect theory: losses ≈ 2× the weight of equivalent gains.
- **Anchoring / contrast** — Tversky & Kahneman; the contrast effect in judgment.

Source: UXPeak — "The UX Psychology Behind Apps People Can't Stop Using."
