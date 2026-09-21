---
name: world-briefing
description: Delivers a concise, curated world news briefing — top headlines across geopolitics, economy, technology, and security — with title and one-sentence context for each. Use this skill whenever the user asks for: current events, top headlines, world news, what's happening today, news briefing, catch me up, what do I need to know, morning briefing, news summary, or anything implying they want a snapshot of significant world events. ALWAYS trigger this skill when the user's intent is to get oriented on what's happening in the world right now, even if phrased casually.
---

# World Briefing Skill

Deliver a crisp, signal-rich news briefing. No fluff. Think briefing officer, not news anchor.

## Execution Steps

### 1. Parallel Search Sweep

Run these web searches simultaneously (all in one turn):

- `top world news today`
- `geopolitical developments today`
- `global economy markets news today`
- `technology AI news today`
- `security conflict news today`

### 2. Filter for Significance

From results, select only stories that meet at least one of:
- Affects multiple nations or global systems
- Involves a head of state, major institution, or military action
- Has material economic impact (markets, trade, energy, supply chains)
- Advances or disrupts a major technology (AI, semiconductors, space, cyber)
- Represents a meaningful escalation or de-escalation of an ongoing situation

Drop: celebrity, sports, local crime, lifestyle, opinion pieces.

### 3. Output Format

Present exactly **8–12 stories**, grouped under these headers (omit a category only if genuinely nothing significant):

```
## 🌍 Geopolitics & Security
## 📈 Economy & Markets  
## 💡 Technology
## ⚡ Flash (fast-moving / breaking)
```

Each story:
```
**[Headline — concise, factual]**  
One sentence: what happened, why it matters.
```

No bullet points within the one-liner. No source names in the headline. Citation link at end of the one-liner is fine if helpful.

### 4. Closing Line

End with a single sentence: the one thread connecting the most consequential stories, if one exists. Label it **Signal:** in bold. Omit if forced.

## Tone

- Briefing officer, not broadcaster
- Factual, neutral, zero editorializing
- Compression over completeness — if you can't say why it matters in one sentence, cut it
- Use LSB-style directness: say the thing plainly

## Example Output Shape

```
## 🌍 Geopolitics & Security

**NATO Activates Article 4 Consultations Over Baltic Incident**  
Three member states invoked the alliance's consultation clause after a cable-cutting incident in the Baltic Sea, raising the prospect of a collective response.

**Israel-Hamas Ceasefire Talks Stall in Cairo**  
Mediators reported a breakdown over prisoner exchange ratios, extending the conflict into its Nth month.

---

## 📈 Economy & Markets

**Fed Holds Rates; Signals Two Cuts Possible in H2**  
Powell cited cooling inflation but warned of labor market resilience as the primary obstacle to faster easing.

---

**Signal:** Elevated military friction in the Baltic and stalled Middle East talks both reinforce a broader pattern of institutional diplomacy under stress.
```

## Notes

- Today's date is always available in your system context — use it to anchor temporal references.
- If a story is more than 48 hours old, flag it only if it is still actively developing.
- Do not fabricate. If searches return thin results on a category, say so briefly and move on.
