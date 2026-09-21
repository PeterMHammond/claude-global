#!/usr/bin/env bash
# Cloudflare Access service tokens, one per app, in the login keyring. Run it as a CLI; source it for cf_token.
#   cf-token.sh set <app> [url]   # hidden prompts, proven against url (must answer 200), stored; url reused on rotation
#   cf-token.sh check <app>       # re-prove the stored token against its url
#   cf-token.sh list              # apps and their urls, never secrets
#   cf-token.sh rm <app>
# Sourced: `cf_token <app>` sets CF_ACCESS_CLIENT_ID/SECRET; a pair already in the env (cloud sessions) wins.

_cft_get() { secret-tool lookup service cf-service-token app "$1" key "$2" 2>/dev/null; }

cf_token() {
  [[ -n "${CF_ACCESS_CLIENT_ID:-}" && -n "${CF_ACCESS_CLIENT_SECRET:-}" ]] && return 0
  CF_ACCESS_CLIENT_ID=$(_cft_get "$1" client_id || true)
  CF_ACCESS_CLIENT_SECRET=$(_cft_get "$1" client_secret || true)
  [[ -n "$CF_ACCESS_CLIENT_ID" && -n "$CF_ACCESS_CLIENT_SECRET" ]] && return 0
  echo "no Access token for '$1' — in a terminal: bash ~/.claude/skills/cf-service-token/scripts/cf-token.sh set $1 <url>" >&2
  return 1
}

# Access answers a bad token with a 302 to its login page, not a 401 — only a 200 proves it. Prints "code location".
_cft_probe() {
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$1" -H "CF-Access-Client-Id: $2" \
    -H @<(printf 'CF-Access-Client-Secret: %s\n' "$3") || true
}

# Names why a non-200 happened; Access's login redirect carries a meta JWT whose service_token_status says if it knew the token.
_cft_why() {
  local st
  [[ -z "$1" ]] && return
  [[ "$1" == *cloudflareaccess.com* ]] || { echo "the app itself redirected to $1 — prove against a url that answers 200"; return; }
  st=$(python3 -c 'import sys,base64,json,urllib.parse as u
m=u.parse_qs(u.urlparse(sys.argv[1]).query)["meta"][0].split(".")[1]
print(json.loads(base64.urlsafe_b64decode(m+"="*(-len(m)%4))).get("service_token_status"))' "$1" 2>/dev/null || true)
  case "$st" in
    False) echo "Access did not recognize this token for this app's account — wrong account, rotated, or revoked" ;;
    True) echo "Access recognized the token but refused it — add it to the app's Service Auth policy" ;;
    *) echo "Access sent it to its login page" ;;
  esac
}

# A * per character so a paste is visible; Backspace deletes, Ctrl-U clears, Enter ends and shows the count.
_cft_ask() {
  local v="" c junk i
  printf '\e[?2004l✔ Enter %s: ' "$1" >/dev/tty
  while IFS= read -rsn1 c </dev/tty; do
    case "$c" in
      "") break ;;
      $'\x7f'|$'\b') if [[ -n "$v" ]]; then v="${v%?}"; printf '\b \b' >/dev/tty; fi ;;
      $'\x15') for ((i = 0; i < ${#v}; i++)); do printf '\b \b' >/dev/tty; done; v="" ;;
      $'\e') read -rsn5 -t 0.05 junk </dev/tty || true ;;
      [[:cntrl:]]) ;;
      *) v+="$c"; printf '*' >/dev/tty ;;
    esac
  done
  v="${v//[[:space:]]/}"
  printf '  (%d characters)\n' "${#v}" >/dev/tty
  printf '%s' "$v"
}

_cft_store() { printf '%s' "$3" | secret-tool store --label="cf-service-token $1 $2" service cf-service-token app "$1" key "$2"; }

_cft_rm() { local k; for k in client_id client_secret url; do secret-tool clear service cf-service-token app "$1" key "$k" || true; done; }

_cft_main() {
  set -euo pipefail
  local cmd="${1:-}" app="${2:-}" url id secret code
  die() { echo "✘ $*" >&2; exit 1; }
  command -v secret-tool >/dev/null || die "secret-tool not found (pacman -S libsecret)"
  case "$cmd" in
    set)
      [[ -n "$app" ]] || die "usage: cf-token.sh set <app> [url]"
      url="${3:-$(_cft_get "$app" url || true)}"
      [[ "$url" == https://* ]] || die "give the Access-protected https url to prove the token against"
      { : </dev/tty; } 2>/dev/null || die "needs a terminal — run it yourself; never paste the secret into a chat"
      echo "Zero Trust → Access → Service Auth → Service Tokens → the $app token" >&2
      id=$(_cft_ask CF_ACCESS_CLIENT_ID)
      [[ "$id" == *.access ]] || die "a Client ID ends in .access — nothing stored"
      secret=$(_cft_ask CF_ACCESS_CLIENT_SECRET)
      [[ -n "$secret" ]] || die "empty secret — nothing stored"
      read -r code loc <<<"$(_cft_probe "$url" "$id" "$secret")"
      [[ "$code" == 200 ]] || die "http $code, nothing stored (Client ID ${id:0:8}…): $(_cft_why "$loc")"
      # Secret first, all-or-nothing: a new id must never pair with an old secret.
      if ! { _cft_store "$app" client_secret "$secret" && _cft_store "$app" client_id "$id" && _cft_store "$app" url "$url"; }; then
        _cft_rm "$app"; die "keyring write failed — cleared '$app'; run set again"
      fi
      echo "✔ $app: verified against $url and stored in the login keyring" ;;
    check)
      [[ -n "$app" ]] || die "usage: cf-token.sh check <app>"
      url=$(_cft_get "$app" url || true); id=$(_cft_get "$app" client_id || true); secret=$(_cft_get "$app" client_secret || true)
      [[ -n "$id" && -n "$secret" && -n "$url" ]] || die "no token stored for '$app' — cf-token.sh set $app <url>"
      read -r code loc <<<"$(_cft_probe "$url" "$id" "$secret")"
      echo "  $app  ${id:0:8}…  $url  http $code"
      [[ "$code" == 200 ]] || die "$app: $(_cft_why "$loc") — rotate with: cf-token.sh set $app"
      echo "✔ $app: token accepted" ;;
    list)
      secret-tool search --all service cf-service-token key url 2>&1 | sed -n 's/^attribute\.app = //p' | sort -u \
        | while read -r a; do printf '%-16s %s\n' "$a" "$(_cft_get "$a" url)"; done ;;
    rm)
      [[ -n "$app" ]] || die "usage: cf-token.sh rm <app>"
      _cft_rm "$app"; echo "✔ removed $app" ;;
    *) sed -n '3,6s/^# *//p' "${BASH_SOURCE[0]}" >&2; exit 64 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then _cft_main "$@"; fi
