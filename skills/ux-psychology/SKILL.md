---
name: ux-psychology
description: Audit and improve any UI for user psychology — conversion, retention, drop-off, onboarding. Applies six research-backed principles (smart defaults, endowed progress, reciprocity, endowment/IKEA effect, loss aversion, anchoring) to a screen or flow, reports where each is missing, and proposes concrete fixes in the codebase's own stack. Trigger when the user says "audit this screen/flow", "apply UX psychology", "why won't users convert / sign up", "reduce drop-off / friction", "make this stickier", "improve onboarding / retention / the funnel", or when building signup, onboarding, pricing, checkout, or upgrade screens.
---

# UX Psychology

Six principles that make users act and stay. Use to audit an existing screen/flow and apply fixes, or to guide a new one.

## Process

1. **Locate the target.** Find the screen, flow, template, or component in question. If unclear which, ask.
2. **Detect the stack.** Read the actual files. Datastar + Askama + workers-rs? React? Plain HTML? Adapt every fix to the idiom you find — see `references/patterns.md` for Datastar/Askama patterns, but match whatever is there.
3. **Audit against the six.** For each principle: does it apply to this screen? PASS or GAP? Only judge principles that fit the screen's job — a settings page isn't a funnel.
4. **Report, then apply.** List gaps with the specific fix. Apply the fixes on request, in the codebase's style.

## The Six Principles

| # | Principle | Rule | Audit question | Fix direction |
|---|---|---|---|---|
| 1 | **Smart defaults** | 70–90% never change a default; they read it as a recommendation. | Any blank field, empty form, or unset choice the user must fill from scratch? | Pre-fill the most common value. Turn "fill this out" into "scan and adjust." Show live result counts on the action button. |
| 2 | **Endowed progress** | The closer to done people feel, the faster they finish (goal-gradient effect). | Does any progress indicator start at 0%? Is onboarding framed as "nothing done yet"? | Never start at zero. Count something already done as step one. Show a non-zero progress meter from first load. |
| 3 | **Reciprocity** | Give value first and users feel pulled to return it; the strongest driver of behavior. | Does the screen demand signup/email/payment *before* delivering anything useful? | Deliver real (partial) value first — a usable result, then "save/unlock the rest." Never gate the first taste behind a wall. |
| 4 | **Endowment / IKEA effect** | People value what they build or feel they own; effort creates attachment. | Is there anything the user has created/customized before the commitment ask? | Let them build first — pick, name, customize, complete step one — *before* the signup screen. Label the button "Continue," not "Sign up." |
| 5 | **Loss aversion** | Losing hurts ~2× as much as gaining pleases (status-quo bias). | Is a call-to-action framed as what the user *gains*? Is the dismiss option cost-free? | Frame the cost of inaction — what they lose by not acting — truthfully. Make the dismiss option name the risk being accepted. |
| 6 | **Anchoring / contrast** | Every value is judged relative to the one seen just before. | Is a price or cost shown in isolation, with no reference point? | Control what the user sees first. Place the cost beside a larger relevant number (as a %, or after a big-ticket item) so it reads small. |

## Truthfulness guardrail

Persuasion, not manipulation. Every technique here must rest on something **true**: real defaults, real progress, real value given, real loss, real proportion. Never fabricate scarcity, fake a countdown, invent losses, or anchor against a number that doesn't exist. A dark pattern that tricks the user violates the whole standard — build what is true and genuinely helpful, or don't ship it.

## Output

Report per screen:

```
Screen: <name>
1 Smart defaults    — GAP: 5 empty booking fields → pre-fill common values, button "Search (12 results)"
2 Endowed progress  — PASS
3 Reciprocity       — GAP: report blurred behind signup → show score + top issues, gate the full breakdown
...
```

Then apply the fixes to the code on request.
