---
name: transcript-refiner
description: |
  Distill YouTube video transcripts down to their pure actionable knowledge. Use this skill whenever the user wants to extract value from a video transcript, refine a transcript, distill a YouTube video, summarize a talk or lecture for learning purposes, or mentions "transcript" alongside words like "distill", "refine", "extract", "gold", "key points", "actionable", or "what did they actually say". Also trigger when the user uploads or pastes a transcript and asks what's worth knowing from it, or wants to turn a video into a learning resource. This is a multi-pass refinement process — not a simple summary. Think of it as smelting ore: multiple passes of heat to burn away dross and leave pure gold.
---

# Transcript Refiner — Distill by Fire

## Purpose

YouTube transcripts are full of noise: self-promotion, channel plugs, sponsor reads, repetition for emphasis, filler phrases, audience engagement bait ("smash that like button"), sales pitches for courses/products, recaps of what was just said, and transitional fluff. Buried inside is genuine knowledge — principles, frameworks, techniques, and actionable insights that the speaker actually knows and is teaching.

This skill performs a multi-pass refinement to extract that pure gold and produce a clean, dense markdown document that captures everything worth learning and nothing that isn't.

## Input

The transcript will typically be provided as:
- A text file in `/mnt/user-data/uploads/`
- Pasted directly in the conversation
- A document attachment with YAML frontmatter containing video metadata

If YAML frontmatter is present (video_id, title, speaker, etc.), preserve the speaker name and original title for attribution in the output.

## The Refining Process — Three Passes

### Pass 1: Classify and Strip (Dross Removal)

Read the full transcript and mentally classify every section into one of these categories:

**DROSS (remove entirely):**
- Self-promotion ("I have a million followers", "I've done billions of views")
- Product/service pitches ("check out my course", "use my tool at...")
- Channel engagement bait ("like and subscribe", "leave a comment", "smash that bell")
- Community/discord/newsletter plugs
- Sponsor segments
- Vague hype with no substance ("this is going to blow your mind")
- Repetitive recaps that add nothing new (but keep the first clear statement of each idea)
- Credibility posturing that doesn't teach anything
- Filler transitions ("all right", "now look", "so guys")
- Meta-commentary about the video itself ("in this video I'm going to...")

**GOLD (preserve and refine):**
- Core principles and frameworks
- Definitions of key concepts
- Concrete examples that illustrate a principle
- Specific techniques or methods
- Cause-and-effect explanations (why something works or doesn't)
- Contrasts and comparisons that clarify thinking
- Actionable steps or checklists
- Mental models or decision frameworks
- Data points or evidence that support a principle
- Counterintuitive insights

### Pass 2: Structure and Synthesize (Smelting)

Take all the gold fragments from Pass 1 and forge them into a coherent structure:

1. **Identify the core thesis** — What is the one big idea this entire video teaches?
2. **Map the framework** — Most good videos teach a framework or system. Find it. Name its parts.
3. **Order by logic, not by video sequence** — The speaker may have presented ideas in a suboptimal order for learning. Reorganize for maximum clarity. If the video's own structure is already logical, keep it.
4. **Compress examples** — The speaker may spend 2 minutes on an example that illustrates a point in 2 sentences. Compress to the essential illustration.
5. **Extract implicit knowledge** — Sometimes the speaker demonstrates expertise without stating it explicitly. If you can identify an unstated principle that makes the advice make sense, include it.
6. **Resolve redundancy** — If the same point is made three different ways, pick the clearest formulation and discard the rest.

### Pass 3: Polish and Verify (Assay)

Review the structured output and verify:

- **Completeness** — Did you capture every distinct idea? Go back to the transcript and scan for anything you missed. It's easy to lose small but valuable insights during compression.
- **Accuracy** — Does your distillation faithfully represent what the speaker said? Don't add your own opinions or interpretations beyond what the speaker taught. If you infer an implicit principle, mark it clearly.
- **Density** — Is every sentence in your output earning its place? Could any sentence be cut without losing knowledge? If so, cut it.
- **Actionability** — Can someone who reads only your output actually apply this knowledge? If a principle lacks enough context to act on, add the minimum necessary context back.

## Output Format

Produce a markdown file with this structure:

```markdown
# [Descriptive Title — What This Actually Teaches]

**Source:** [Speaker Name] — "[Original Video Title]"

## Core Thesis

[1-3 sentences capturing the central argument or insight of the entire video]

## Key Principles

### [Principle Name]

[Explanation of the principle — what it is, why it matters, how it works]

[Compressed example if it clarifies the principle]

### [Principle Name]

[Continue for each major principle...]

## Actionable Takeaways

[Numbered list of concrete things the reader can do with this knowledge.
Each item should be specific enough to act on without referring back to the video.]

## Mental Models

[Optional section — include only if the video introduces reusable
thinking frameworks that apply beyond the specific topic.
Skip this section if the video is purely tactical.]
```

**Formatting rules:**
- Use headers to separate distinct ideas, not for visual decoration
- Keep paragraphs tight — 2-4 sentences max
- Use plain, direct language — match the density of a good technical reference, not a blog post
- No bullet points for things that should be prose
- No filler phrases ("it's important to note that...", "interestingly...")
- Preserve the speaker's specific terminology when it names a useful concept

## Quality Standard

The output should pass this test: **If someone reads only your distillation and never watches the video, they should walk away with every piece of actionable knowledge the video contained — and none of the noise.**

A secondary test: **A reader should be able to scan the document in 2 minutes and identify whether this knowledge is relevant to them.** This is the same "topic clarity + on-target curiosity" principle — applied to the document itself.

## Working with Claude Code

When invoked via Claude Code:

1. Read the transcript file from the path provided
2. Perform all three passes (this happens in your reasoning — the user sees only the final output)
3. Write the refined markdown to the output location
4. If the transcript has YAML frontmatter, use the metadata for attribution
5. Name the output file based on the content theme, not the video ID (e.g., `hook-writing-framework.md` not `2byPP_9F0-Q.md`)
