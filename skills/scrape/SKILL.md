---
name: scrape
description: Scrape websites using the Cloudflare Browser Rendering REST API. Triggers on /scrape or when asked to scrape, extract, or pull content from a website. Usage: /scrape <type> <url> [options]. Types: images, css, links, markdown, screenshot, html, or any CSS selector.
---

# Scrape

Scrape web content via Cloudflare Browser Rendering API (EveryGoodWork account).

## Usage

```
/scrape <type> <url> [--save <dir>] [--depth <n>]
```

- **Default behavior**: crawl all pages on the domain, then scrape each
- `--depth 1`: single page only (no crawl)
- `--save <dir>`: download scraped content to directory (default: current working directory)

## Auth

Read the OAuth token from `~/.config/.wrangler/config/default.toml`:

```bash
TOKEN=$(grep oauth_token ~/.config/.wrangler/config/default.toml | cut -d'"' -f2)
```

If API returns auth error, tell user to run `wrangler login` to refresh the token.

## API Details

**Account ID**: `e2ecc897eaa02efed7cb3cbc4beca1fa`
**Base URL**: `https://api.cloudflare.com/client/v4/accounts/e2ecc897eaa02efed7cb3cbc4beca1fa/browser-rendering`

All requests are POST with `Authorization: Bearer $TOKEN` and `Content-Type: application/json`.

## Crawl Strategy

Unless `--depth 1`, first discover all pages:

1. POST to `/links` with `{"url": "<start_url>"}` — returns array of URLs
2. Filter to same-domain links (exclude mailto:, external domains, cart, checkout, my-account)
3. For paginated sites, also fetch /links from discovered `/page/N/` URLs
4. Deduplicate the full URL set
5. Run the scrape type against each discovered page

## Scrape Types

### `images`
POST to `/scrape` with `{"url": "...", "elements": [{"selector": "img"}]}`

Response shape:
```json
{"success": true, "result": [{"selector": "img", "results": [
  {"attributes": [{"name": "src", "value": "..."}, {"name": "alt", "value": "..."}],
   "width": N, "height": N, "text": "", "html": ""}
]}]}
```

Post-processing:
- Extract `src` and `alt` from attributes array
- Filter OUT: `data:` URIs, tracking pixels (`g.gif`, `wpstats`), images with width <= 10
- Filter OUT thumbnails: URLs ending in `-NNNxNNN.ext` (e.g. `-100x100.jpg`, `-600x600.jpg`)
- Deduplicate across all pages
- Display as table: URL, alt text, dimensions
- With `--save`: download full-size images via curl

### `css`
POST to `/scrape` with selectors: `link[rel=stylesheet]` and `style`

- From `link` elements: extract `href` attribute (stylesheet URLs)
- From `style` elements: extract `html` (inline CSS content)
- With `--save`: download external stylesheets, save inline CSS to files

### `links`
POST to `/links` with `{"url": "..."}`

Returns flat array of URLs. Display grouped by domain (internal vs external).

### `markdown` (or `text`)
POST to `/markdown` with `{"url": "..."}`

Returns markdown content. Display or save to file.

### `screenshot`
POST to `/screenshot` with `{"url": "..."}`

Returns binary image data. Always save to file (default: `screenshot-<domain>-<timestamp>.png`).

### `html`
POST to `/content` with `{"url": "..."}`

Returns full rendered HTML. Display or save to file.

### Custom CSS selector
If type doesn't match any preset above, treat it as a CSS selector.

POST to `/scrape` with `{"url": "...", "elements": [{"selector": "<user-provided>"}]}`

Display results showing: matched element text, html, and attributes.

## Output

- Always show a summary: pages crawled, items found, any errors
- Format results as clean tables or lists
- When saving files, report: count saved, total size, destination directory
