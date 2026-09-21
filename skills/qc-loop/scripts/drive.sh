#!/usr/bin/env bash
# qc-loop server driver. Fires ROUNDS x PINGS actions through the /agent gateway,
# records the t0/t1 window, settles, and prints the exact `GET /qc` window to query.
#
# Defaults reproduce the canonical ping/pong baseline ACTION SCRIPT (6 rounds x 10 pings,
# ~13s apart, cid=qc-synth). Override via env to drive a different hop:
#
#   ROUNDS=6 PINGS=10 SPACING=13 SETTLE=55 CID=qc-synth \
#   CAPS='["System:dispatch"]' \
#   ROUND_CODE='...JS that loops PINGS times calling this.env.<Binding>.<method>(...)...' \
#   bash drive.sh
#
# The default ROUND_CODE pings PINGS times via the generic command channel
# (System.dispatch("ping", …)) with a fresh (one-shot) key, cid=$CID.
# Run the Chrome client driver concurrently (see references/capture.md) for the full
# dual-driver table. Dependency-light: no `bc`, no `jq` math.
set -euo pipefail

TOKEN_FILE="$HOME/.craft/token.json"
[ -f "$TOKEN_FILE" ] || { echo "No token. Run: bash ~/.claude/skills/craft-agent/scripts/login.sh"; exit 1; }
BASE=$(jq -r '.base' "$TOKEN_FILE")
CID_HDR=$(jq -r '.client_id' "$TOKEN_FILE")
SEC=$(jq -r '.client_secret' "$TOKEN_FILE")

ROUNDS=${ROUNDS:-6}
PINGS=${PINGS:-10}
SPACING=${SPACING:-13}
SETTLE=${SETTLE:-55}
CID=${CID:-qc-synth}
CAPS=${CAPS:-'["System:dispatch"]'}
ROUND_CODE=${ROUND_CODE:-'import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const out = [];
    for (let i = 0; i < PINGS_PLACEHOLDER; i++) {
      // ping IS a dynamic command through the generic channel; one-shot key (minted), cid attributed via actor.
      const r = await this.env.System.dispatch("ping", "", "", "CID_PLACEHOLDER", undefined);
      out.push(r.event_id);
    }
    return { fired: out.length, last: out[out.length-1] };
  }
}'}
ROUND_CODE=${ROUND_CODE//PINGS_PLACEHOLDER/$PINGS}
ROUND_CODE=${ROUND_CODE//CID_PLACEHOLDER/$CID}

payload=$(jq -n --arg code "$ROUND_CODE" --argjson caps "$CAPS" '{code:$code, capabilities:$caps}')

T0=$(date +%s)
echo "t0=$T0  (ROUNDS=$ROUNDS PINGS=$PINGS SPACING=${SPACING}s SETTLE=${SETTLE}s CID=$CID)"
for round in $(seq 1 "$ROUNDS"); do
  resp=$(curl -s -w ' curl_total=%{time_total}s' -X POST "${BASE}/agent" \
    -H "CF-Access-Client-Id: ${CID_HDR}" -H "CF-Access-Client-Secret: ${SEC}" \
    -H "Content-Type: application/json" -d "$payload")
  echo "round=$round resp=$resp"
  [ "$round" -lt "$ROUNDS" ] && sleep "$SPACING"
done
T1=$(date +%s)
echo "t1=$T1  settling ${SETTLE}s..."
sleep "$SETTLE"
echo "DONE. Query: bash report.sh $T0 $((T1+60))"
