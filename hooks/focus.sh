#!/usr/bin/env bash
# Record this session's focus, colour, root and date; the UserPromptSubmit hook renames the session.
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: focus.sh <focus words> [red|green|yellow|blue|purple|cyan]" >&2; exit 1; }
slug(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '_ ' '--' | tr -cd 'a-z0-9-' | tr -s '-' | sed 's/^-//;s/-$//'; }
# A pasted example carries its own output after an arrow; keep only what precedes it.
words=$(slug "$(printf '%s' "$*" | sed 's/[-=]*>.*//; s/→.*//')")
# Every word is a focus word; only a trailing known colour is taken as the colour.
color=""
case "${words##*-}" in
  red|green|yellow|blue|purple|cyan) case "$words" in *-*) color="${words##*-}"; words="${words%-*}" ;; esac ;;
esac
focus=$(printf '%s' "$words" | cut -c1-48 | sed 's/-$//')
[ -n "$focus" ] || { echo "empty focus" >&2; exit 1; }
if [ -z "$color" ]; then
  case "$focus" in
    *fix*|*bug*|*debug*|*incident*) color=red ;;
    *review*|*audit*|*triage*)      color=yellow ;;
    *deploy*|*ship*|*release*)      color=green ;;
    *doc*|*write*|*plan*|*spec*)    color=blue ;;
    *test*|*mutat*|*gate*)          color=cyan ;;
    *)                              color=purple ;;
  esac
fi
# Root is pinned once, here — never re-derived from the cwd, which drifts as the session works.
root=$(slug "$(basename "$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")")")
day=$(date +%Y%m%d)
# One emoji per kind of work — first match wins, so the specific patterns lead.
case "$focus" in
  *incident*|*outage*|*emergency*|*prod-down*)           mark="🚨" ;;
  *crash*|*coredump*|*segfault*|*panic*)                 mark="💥" ;;
  *fix*|*bug*|*debug*|*repro*)                           mark="🐛" ;;
  *hotfix*|*patch*|*bandaid*)                            mark="🩹" ;;
  *security*|*cve*|*vuln*|*pentest*|*hardening*)         mark="🛡️" ;;
  *sign*|*gpg*|*yubikey*|*ceremony*|*cert*)              mark="🔑" ;;
  *token*|*secret*|*credential*|*vault*|*rotate*)        mark="🔐" ;;
  *auth*|*oauth*|*login*|*consent*|*dpop*)               mark="🪪" ;;
  *permission*|*grant*|*scope*|*acl*)                    mark="🎫" ;;
  *review*|*audit*|*inspect*|*verdict*)                  mark="🔍" ;;
  *triage*|*backlog*|*groom*)                            mark="🗂️" ;;
  *issue*|*ticket*|*gitlab*|*glab*)                      mark="📋" ;;
  *release*|*tag*|*bump*|*changelog*)                    mark="🏷️" ;;
  *deploy*|*ship*|*rollout*|*launch*|*cutover*)          mark="🚀" ;;
  *rollback*|*revert*|*undo*|*restore*)                  mark="⏪" ;;
  *migrat*|*backfill*|*import*|*seed*)                   mark="📦" ;;
  *test*|*mutat*|*gate*|*coverage*|*harness*)            mark="🧪" ;;
  *perf*|*speed*|*optimi*|*bench*|*latency*|*qc*)        mark="⚡" ;;
  *cost*|*billing*|*budget*|*invoice*|*price*)           mark="💰" ;;
  *remove*|*retire*|*delete*|*purge*|*cleanup*)          mark="🔥" ;;
  *archive*|*attic*|*history*)                           mark="🗃️" ;;
  *refactor*|*rewrite*|*restructur*|*tidy*)              mark="♻️" ;;
  *doc*|*write*|*note*|*handoff*|*readme*)               mark="📝" ;;
  *plan*|*spec*|*design*|*architect*|*rfc*)              mark="📐" ;;
  *research*|*investigat*|*explor*|*recon*)              mark="🧭" ;;
  *brainstorm*|*idea*|*concept*)                         mark="💡" ;;
  *config*|*setup*|*settings*|*hook*|*dotfile*)          mark="🔧" ;;
  *skill*|*prompt*|*instruction*|*memory*)               mark="📜" ;;
  *agent*|*swarm*|*subagent*|*spawn*|*workflow*)         mark="🤖" ;;
  *coordinat*|*command*|*control*|*ops*|*c2*)            mark="🎖️" ;;
  *relay*|*route*|*bridge*|*message*|*handoff-line*)     mark="📡" ;;
  *monitor*|*watch*|*alert*|*telemetry*|*observ*)        mark="👁️" ;;
  *log*|*trace*|*tail*|*journal*)                        mark="🧾" ;;
  *metric*|*usage*|*report*|*dashboard*|*stats*)         mark="📊" ;;
  *lab*|*sandbox*|*airlock*|*landlock*|*island*)         mark="🧱" ;;
  *watchman*)                                            mark="🗼" ;;
  *craft*|*construct*|*room*|*facet*|*statetree*)        mark="🧩" ;;
  *cloudflare*|*worker*|*durable*|*edge*|*wrangler*)     mark="☁️" ;;
  *queue*|*consumer*|*dlq*|*pipeline*)                   mark="🚚" ;;
  *database*|*sqlite*|*d1*|*kv*|*r2*|*storage*)          mark="🗄️" ;;
  *sse*|*datastar*|*hypermedia*|*stream*)                mark="🌊" ;;
  *rust*|*cargo*|*clippy*|*crate*)                       mark="🦀" ;;
  *zig*|*wasm*)                                          mark="⚙️" ;;
  *git*|*rebase*|*merge*|*branch*|*commit*)              mark="🌿" ;;
  *ci*|*pipeline-job*|*runner*|*build*)                  mark="🏗️" ;;
  *ui*|*css*|*layout*|*style*|*theme*)                   mark="🎨" ;;
  *screenshot*|*visual*|*render-check*)                  mark="📸" ;;
  *browser*|*chrome*|*scrape*|*crawl*)                   mark="🕸️" ;;
  *dns*|*zone*|*domain*|*record*)                        mark="🧿" ;;
  *mail*|*email*|*smtp*|*dkim*|*otp*)                    mark="📮" ;;
  *network*|*wireguard*|*vpn*|*tunnel*|*firewall*)       mark="🛰️" ;;
  *host*|*hardware*|*usb*|*disk*|*drive*|*bios*)         mark="🖥️" ;;
  *printer*|*label*|*ptouch*)                            mark="🖨️" ;;
  *omarchy*|*hyprland*|*desktop*|*waybar*|*keybind*)     mark="🪟" ;;
  *package*|*pacman*|*yay*|*install*|*upgrade*)          mark="📥" ;;
  *backup*|*snapshot*|*restic*)                          mark="🧳" ;;
  *video*|*render*|*resolve*|*clip*|*edit*)              mark="🎬" ;;
  *audio*|*whisper*|*transcri*|*podcast*|*mic*)          mark="🎙️" ;;
  *youtube*|*channel*|*thumbnail*)                       mark="📺" ;;
  *sermon*|*gospel*|*scripture*|*kcc*|*church*|*bible*)  mark="✝️" ;;
  *story*|*script*|*hook-writing*|*narrative*|*copy*)    mark="📖" ;;
  *market*|*storybrand*|*funnel*|*landing*|*brand*)      mark="📣" ;;
  *game*|*chess*|*play*|*puzzle*)                        mark="🎮" ;;
  *map*|*atlas*|*globe*|*geo*)                           mark="🗺️" ;;
  *upwork*|*client*|*contract*|*invoice-client*)         mark="🤝" ;;
  *calendar*|*schedule*|*cron*|*reminder*)               mark="📅" ;;
  *feat*|*implement*|*add*|*new*)                        mark="✨" ;;
  *)                                                     mark="🧰" ;;
esac
sid="${CLAUDE_CODE_SESSION_ID:?no CLAUDE_CODE_SESSION_ID}"
mkdir -p "$HOME/.claude/session-focus"
printf '%s\n%s\n%s\n%s\n%b\n' "$focus" "$color" "$root" "$day" "$mark" > "$HOME/.claude/session-focus/$sid"
printf '%s-%s-%s  (status line: %b %s)\n' "$root" "$focus" "$day" "$mark" "$color"
