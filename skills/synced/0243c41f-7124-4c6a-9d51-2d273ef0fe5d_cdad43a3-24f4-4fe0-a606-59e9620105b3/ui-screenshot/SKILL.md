---
name: ui-screenshot
description: >
  Visual UI verification via headless Chrome screenshots. Use this skill whenever you need to
  confirm a UI looks correct, verify a page renders as intended, check styling or layout,
  or validate that frontend changes produce the expected visual result. Triggers on phrases
  like "check the UI", "does it look right", "screenshot", "verify the page", "what does it
  look like", "confirm the layout", "visual check", or any time you've made frontend changes
  and want to see the result. Also use after generating HTML, Datastar SSE fragments, or
  any server-rendered markup to confirm it renders correctly in a real browser.
---

# UI Screenshot Verification

Take a headless Chrome screenshot of a running local service and visually verify it matches intent.

## Prerequisites

Headless Chrome (or Chromium) must be installed on the dev machine. Nothing else is needed — no npm packages, no Playwright, no Puppeteer.

```bash
# Check availability
which google-chrome || which chromium-browser || which chromium
```

If not found, install:
```bash
# Debian/Ubuntu
sudo apt-get install -y chromium-browser
# macOS (already has Chrome typically, or)
brew install --cask google-chrome
```

## The Pattern

### 1. Ensure the dev server is running

If the service isn't already running, start it in the background:

```bash
# For Cloudflare Workers
npx wrangler dev &
WRANGLER_PID=$!
sleep 3  # Give it time to bind

# Verify it's up
curl -s -o /dev/null -w "%{http_code}" http://localhost:8787
```

### 2. Take the screenshot

```bash
# Find the Chrome binary
CHROME=$(which google-chrome || which chromium-browser || which chromium)

# Screenshot a specific URL
$CHROME \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --screenshot=/tmp/ui-check.png \
  --window-size=1280,800 \
  http://localhost:8787

# For a specific route:
$CHROME \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --screenshot=/tmp/ui-check.png \
  --window-size=1280,800 \
  http://localhost:8787/some/route
```

#### Mobile viewport
```bash
$CHROME \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --screenshot=/tmp/ui-mobile.png \
  --window-size=375,812 \
  http://localhost:8787
```

#### Capture after delay (for SSE/Datastar content that loads asynchronously)
```bash
# Use a tiny inline HTML page that waits, then screenshots via DevTools protocol
# OR simply: take screenshot, check if content is there, retry once if empty
$CHROME \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --screenshot=/tmp/ui-check.png \
  --window-size=1280,800 \
  --virtual-time-budget=5000 \
  http://localhost:8787
```

The `--virtual-time-budget=5000` flag gives the page 5 seconds of virtual time to settle before capture. This handles Datastar SSE patches, lazy-loaded content, and async rendering.

### 3. View the screenshot

Use the `view` tool to look at the screenshot:

```
view /tmp/ui-check.png
```

### 4. Evaluate against intent

After viewing, compare what you see against what was intended. Ask yourself:

- **Layout**: Are elements positioned correctly? Is spacing/alignment right?
- **Content**: Is the expected text/data visible? Are placeholders resolved?
- **Styling**: Do colors, fonts, borders match the design intent?
- **State**: Does the page reflect the correct initial state? (logged out, empty list, etc.)
- **Responsiveness**: If checking mobile, does it collapse/stack properly?
- **Errors**: Are there any visible error messages, broken images, or missing resources?

If something is wrong, describe specifically what you see vs. what was expected, fix the code, and re-screenshot.

### 5. Cleanup

```bash
# If you started wrangler
kill $WRANGLER_PID 2>/dev/null
rm /tmp/ui-check.png
```

## Multiple Pages / Routes

When verifying a multi-page app, screenshot each route:

```bash
ROUTES=("/" "/about" "/dashboard" "/login")
for route in "${ROUTES[@]}"; do
  SAFE_NAME=$(echo "$route" | tr '/' '-' | sed 's/^-//')
  [ -z "$SAFE_NAME" ] && SAFE_NAME="index"
  $CHROME \
    --headless=new \
    --disable-gpu \
    --no-sandbox \
    --screenshot="/tmp/ui-${SAFE_NAME}.png" \
    --window-size=1280,800 \
    "http://localhost:8787${route}"
done
```

Then view each one sequentially, evaluating as you go.

## Before/After Comparison

When making UI changes, screenshot BEFORE making changes, then AFTER:

```bash
# Before changes
$CHROME --headless=new --disable-gpu --no-sandbox \
  --screenshot=/tmp/ui-before.png --window-size=1280,800 \
  http://localhost:8787

# ... make your code changes ...

# After changes (may need to restart dev server)
$CHROME --headless=new --disable-gpu --no-sandbox \
  --screenshot=/tmp/ui-after.png --window-size=1280,800 \
  http://localhost:8787
```

View both and describe the differences.

## Troubleshooting

| Problem | Fix |
|---|---|
| Blank/white screenshot | Page needs more load time — increase `--virtual-time-budget` |
| Chrome not found | Install chromium: `sudo apt-get install -y chromium-browser` |
| GPU errors in CI/container | Already handled by `--disable-gpu --no-sandbox` |
| SSE content missing | Increase virtual-time-budget to 10000+ |
| Auth-gated page | Use `--screenshot` on the login page, or set cookies via a separate script |

## Key Principle

This skill exists because **the fastest feedback loop is: change → screenshot → look → fix**. No test framework, no assertion library, no DOM selectors. Just eyes on pixels. Claude's vision capability IS the assertion engine.
