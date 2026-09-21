#!/usr/bin/env python3
"""
Aggregate Claude Code session usage from ~/.claude/projects/**/*.jsonl.

Default output: project × day matrix with per-row, per-column, and grand totals,
followed by a by-model summary.

Usage:
  aggregate.py                  # rolling 7 days, project × day matrix (default)
  aggregate.py today            # UTC today only
  aggregate.py 2026-05-03       # specific UTC date
  aggregate.py week             # rolling 7 days (project × day matrix)
  aggregate.py month            # rolling 30 days (project × day matrix)
  aggregate.py all              # all time, by-month matrix
  aggregate.py --sessions [arg] # adds per-session detail table

Pricing calibrated against Claude Code /usage panel:
  opus-4-7    $5 / $25 / $0.50 / $6.25  per M  (in / out / cacheRead / cacheWrite)
  sonnet-4-6  $3 / $15 / $0.30 / $3.75  per M
  haiku-4-5   $1 / $5  / $0.10 / $1.25  per M
"""
from __future__ import annotations
import json, os, glob, sys, datetime
from collections import defaultdict

PRICES = {
    # Opus 5. Cache WRITE is 10.00, not 6.25: Claude Code runs a 1-HOUR prompt-cache TTL, billed at
    # 2x input, where the 5-minute TTL is 1.25x. Calibrated against a real /usage panel — 5.5k in,
    # 483.9k out, 165.3m cacheRead, 1.7m cacheWrite = $111.86 panel vs $111.78 here (rounding on the
    # panel's 0.1m-resolution figures). At 6.25 the same session computes $105.40, off by $6.46.
    # A session on the 5m TTL (usage overage) is therefore slightly over-counted; the 1h rate is the
    # right default because it is what every normal session uses.
    "claude-opus-5":             (5.00, 25.00, 0.50, 10.00),
    "claude-opus-5[1m]":         (5.00, 25.00, 0.50, 10.00),
    # Opus 4.8: 1M context at STANDARD pricing — no long-context premium (unlike 4.7[1m]).
    "claude-opus-4-8":           (5.00, 25.00, 0.50, 6.25),
    "claude-opus-4-8[1m]":       (5.00, 25.00, 0.50, 6.25),
    "claude-fable-5":            (10.00, 50.00, 1.00, 12.50),
    "claude-sonnet-5":           (3.00, 15.00, 0.30, 3.75),
    "claude-opus-4-7":           (5.00, 25.00, 0.50, 6.25),
    "claude-opus-4-7[1m]":       (10.00, 50.00, 1.00, 12.50),
    "claude-opus-4-6":           (5.00, 25.00, 0.50, 6.25),
    "claude-sonnet-4-6":         (3.00, 15.00, 0.30, 3.75),
    "claude-sonnet-4-5":         (3.00, 15.00, 0.30, 3.75),
    "claude-haiku-4-5":          (1.00,  5.00, 0.10, 1.25),
    "claude-haiku-4-5-20251001": (1.00,  5.00, 0.10, 1.25),
}


def parse_args(argv):
    show_sessions = False
    rest = []
    for a in argv[1:]:
        if a == "--sessions":
            show_sessions = True
        else:
            rest.append(a)
    arg = rest[0] if rest else "week"
    return arg, show_sessions


def resolve_window(arg):
    today = datetime.date.today()
    if arg == "today":
        days = [today]
        bucket = "day"
    elif arg == "week":
        days = [today - datetime.timedelta(days=i) for i in range(6, -1, -1)]
        bucket = "day"
    elif arg == "month":
        days = [today - datetime.timedelta(days=i) for i in range(29, -1, -1)]
        bucket = "day"
    elif arg == "all":
        days = None
        bucket = "month"
    else:
        try:
            d = datetime.date.fromisoformat(arg)
        except ValueError:
            print(f"bad date: {arg!r}; expected YYYY-MM-DD or today/week/month/all",
                  file=sys.stderr)
            sys.exit(2)
        days = [d]
        bucket = "day"
    return days, bucket


def short_proj(p):
    # Claude Code encodes the path with `-` as the separator. Strip the leading
    # home-dir prefix and reconstruct an abbreviated path.
    p = p.lstrip("-")
    if p.startswith("home-peter-"):
        p = p[len("home-peter-"):]
    elif p == "home-peter":
        return "~"
    if p.startswith("Projects-EveryGoodWork-"):
        return p[len("Projects-EveryGoodWork-"):]
    if p == "Projects-EveryGoodWork":
        return "EGW-root"
    # Keep the last 1-2 path segments for readability ("KCC-livestream" beats
    # "Projects-KCC-livestream" once the leading folder is implied).
    parts = p.split("-")
    return "/".join(parts[-2:]) if len(parts) > 2 else p


def cost_of(model, ti, to, cr, cw):
    p = PRICES.get(model)
    if not p:
        return 0.0
    pi, po, pcr, pcw = p
    return (ti * pi + to * po + cr * pcr + cw * pcw) / 1_000_000


def main():
    arg, show_sessions = parse_args(sys.argv)
    days, bucket = resolve_window(arg)
    in_window = (lambda iso: True) if days is None \
        else (lambda iso, s={d.isoformat() for d in days}: iso in s)

    root = os.path.expanduser("~/.claude/projects")
    # bucket_key: "YYYY-MM-DD" for day bucket, "YYYY-MM" for month bucket.
    cell = defaultdict(float)             # (project, bucket_key) -> $
    by_project = defaultdict(float)       # project -> $
    by_bucket = defaultdict(float)        # bucket_key -> $
    by_model = defaultdict(lambda: [0, 0, 0, 0, 0.0])  # model -> [in,out,cR,cW,$]
    seen_msg_ids = set()   # API message ids already counted — see the dedupe note in the read loop
    sessions = defaultdict(lambda: {      # (project, session_id) -> stats
        "msgs": 0, "tok": [0, 0, 0, 0], "cost": 0.0,
        "first": None, "last": None,
    })
    bucket_keys = set()
    grand = 0.0

    for path in glob.glob(f"{root}/**/*.jsonl", recursive=True):
        project = path.split("/.claude/projects/")[1].split("/")[0]
        if "/subagents/" in path:
            sid = os.path.basename(path).replace(".jsonl", "")[:24] + " (sub)"
        else:
            sid = os.path.basename(path).replace(".jsonl", "")
        try:
            f = open(path, errors="replace")
        except OSError:
            continue
        with f:
            for line in f:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                ts = d.get("timestamp")
                if not ts or not in_window(ts[:10]):
                    continue
                msg = d.get("message") if isinstance(d.get("message"), dict) else None
                if not msg or msg.get("role") != "assistant":
                    continue
                # ONE assistant message can be written to the transcript several times (streaming
                # updates, retries, post-compact replay). Summing every occurrence roughly DOUBLED
                # the bill: one 7h session logged 1,050 usage records for 553 distinct ids, and
                # reported $220.43 against a $111.89 /usage panel. Dedupe on the API's message id —
                # that is the unit Anthropic actually billed once. Deduped output for that session
                # was 482,513 tokens vs the panel's 483.9k; raw was 1,136,105.
                mid = msg.get("id")
                if mid is not None:
                    if mid in seen_msg_ids:
                        continue
                    seen_msg_ids.add(mid)
                u = msg.get("usage") or {}
                ti = u.get("input_tokens", 0)
                to = u.get("output_tokens", 0)
                cr = u.get("cache_read_input_tokens", 0)
                cw = u.get("cache_creation_input_tokens", 0)
                model = msg.get("model", "?")
                c = cost_of(model, ti, to, cr, cw)
                bk = ts[:10] if bucket == "day" else ts[:7]
                cell[(project, bk)] += c
                by_project[project] += c
                by_bucket[bk] += c
                bucket_keys.add(bk)
                grand += c
                m = by_model[model]
                m[0] += ti; m[1] += to; m[2] += cr; m[3] += cw; m[4] += c
                s = sessions[(project, sid)]
                s["msgs"] += 1
                s["tok"][0] += ti; s["tok"][1] += to
                s["tok"][2] += cr; s["tok"][3] += cw
                s["cost"] += c
                if s["first"] is None or ts < s["first"]:
                    s["first"] = ts
                if s["last"] is None or ts > s["last"]:
                    s["last"] = ts

    label = arg if arg in ("today", "week", "month", "all") else arg
    if days is not None:
        cols = [d.isoformat() for d in days]
        # only keep populated columns when arg is "all" (n/a) — in day mode show
        # every day in the window even if zero, so trends are visible.
    else:
        cols = sorted(bucket_keys)
    print(f"Window: {label} (UTC)\n")

    # Project × bucket matrix
    if cols:
        col_w = max(len(c) for c in cols + [" Total"])
        col_w = max(col_w, 9)
        proj_w = max([len(short_proj(p)) for p in by_project] + [12])
        proj_w = min(proj_w, 32)
        header = f"{'Project':<{proj_w}}"
        for c in cols:
            header += f" {c:>{col_w}}"
        header += f" {'Total':>{col_w+1}}"
        print(header)
        print("-" * len(header))
        for proj in sorted(by_project, key=lambda p: -by_project[p]):
            row = f"{short_proj(proj)[:proj_w]:<{proj_w}}"
            for c in cols:
                v = cell.get((proj, c), 0.0)
                row += f" {('' if v == 0 else f'${v:.2f}'):>{col_w}}"
            row += f" {('$' + format(by_project[proj], '.2f')):>{col_w+1}}"
            print(row)
        print("-" * len(header))
        tot_row = f"{'Total':<{proj_w}}"
        for c in cols:
            v = by_bucket.get(c, 0.0)
            tot_row += f" {('' if v == 0 else f'${v:.2f}'):>{col_w}}"
        tot_row += f" {('$' + format(grand, '.2f')):>{col_w+1}}"
        print(tot_row)
    else:
        print("(no usage in window)")

    # By-model (skip rows with zero spend — synthetic placeholder messages etc.)
    by_model_real = {m: v for m, v in by_model.items() if v[4] > 0}
    if by_model_real:
        print("\nBy model:")
        for m, (ti, to, cr, cw, c) in sorted(by_model_real.items(), key=lambda x: -x[1][4]):
            print(f"  {m:<28} in={ti:>7,}  out={to:>8,}  cacheR={cr:>11,}  "
                  f"cacheW={cw:>10,}  ${c:>7.2f}")

    # Per-session detail (opt-in)
    if show_sessions and sessions:
        print(f"\n{'Project':<28} {'Session':<26} {'Span (UTC)':<13} {'msgs':>5} "
              f"{'in':>7} {'out':>8} {'cR':>11} {'cW':>10} {'$':>7}")
        print("-" * 122)
        rows = sorted(sessions.items(), key=lambda kv: -kv[1]["cost"])
        for (proj, sid), s in rows:
            span = (f"{s['first'][11:16]}-{s['last'][11:16]}"
                    if s["first"] and s["first"][:10] == s["last"][:10]
                    else (f"{s['first'][:10]}→{s['last'][:10]}" if s["first"] else ""))
            t = s["tok"]
            print(f"{short_proj(proj)[:28]:<28} {sid[:26]:<26} {span:<13} "
                  f"{s['msgs']:>5} {t[0]:>7,} {t[1]:>8,} {t[2]:>11,} {t[3]:>10,} "
                  f"{s['cost']:>7.2f}")


if __name__ == "__main__":
    main()
