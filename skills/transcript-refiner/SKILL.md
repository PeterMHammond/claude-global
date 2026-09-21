---
name: transcript-refiner
description: |
  Distill YouTube video transcripts down to their pure actionable knowledge. Use this skill whenever the user wants to extract value from a video transcript, refine a transcript, distill a YouTube video, summarize a talk or lecture for learning purposes, or mentions "transcript" alongside words like "distill", "refine", "extract", "gold", "key points", "actionable", or "what did they actually say". Also trigger when the user uploads or pastes a transcript and asks what's worth knowing from it, or wants to turn a video into a learning resource. This is a multi-pass refinement process — not a simple summary. Think of it as smelting ore: multiple passes of heat to burn away dross and leave pure gold.
---

# Transcript Refiner — Distill by Fire

Performs multi-pass refinement on YouTube transcripts to extract pure actionable
knowledge. Dispatches Sonnet subagents to do the smelting — keeping the main
context clean while processing large transcripts.

**Not a summarizer.** A summarizer compresses everything equally. This skill
burns away dross (self-promotion, filler, engagement bait, sponsor reads,
repetition) and forges what remains into a dense, structured knowledge document.

---

## Step 1 — Resolve the input

Determine what the user provided and how to get the transcript text:

| Input | Action |
|---|---|
| File path to a `.txt` or `.md` transcript | Read the file directly |
| YouTube URL or video ID | Fetch transcript first using `~/.local/bin/yt-transcript <id>`, then refine |
| Pasted transcript text in conversation | Use the text directly |
| Directory of transcripts | Process each file, dispatch parallel subagents |
| "Refine the transcripts in [folder]" | Glob for `.txt`/`.md` files, batch process |

If the input is a YouTube URL, fetch the transcript first:
```bash
~/.local/bin/yt-transcript <video-id> > /tmp/transcript-raw.txt 2>/dev/null
```
If yt-transcript is not available, follow the youtube-transcript skill bootstrap.

---

## Step 2 — Determine output location

**Default output directory:** Same directory as the input file, with `-refined.md` suffix.

| Input location | Output location |
|---|---|
| `/path/to/channel/Some Video Title.txt` | `/path/to/channel/refined/some-video-title.md` |
| YouTube URL (no file) | `~/Projects/transcripts/refined/<descriptive-name>.md` |
| Pasted text | Print to conversation, offer to save |

Create the `refined/` subdirectory if it doesn't exist.

Name output files by content theme, not video ID:
- `hook-writing-framework.md` not `2byPP_9F0-Q.md`
- `storybrand-three-tips.md` not `video-transcript.md`

---

## Step 3 — Dispatch Sonnet subagent for refining

Use the Task tool to dispatch a Sonnet subagent with the transcript and refining
instructions. This keeps the main context clean — transcripts can be 5,000+ words
of raw text.

**For a single transcript:**

```
Task tool call:
  subagent_type: "general-purpose"
  model: "sonnet"
  description: "Refine transcript"
  prompt: [see prompt template below]
```

**For batch processing (multiple transcripts):**

Dispatch up to 4 subagents in parallel, each handling one transcript. Wait for
all to complete, then report results.

---

## Subagent Prompt Template

The prompt sent to each Sonnet subagent must include:

1. The full refining instructions (the three-pass process below)
2. The raw transcript text
3. The output file path
4. Any metadata (speaker name, video title) if available

### Prompt structure:

```
You are a transcript refiner. Your job is to distill a raw YouTube transcript
into pure actionable knowledge through a three-pass process.

**IMPORTANT:** Write the refined output to: {output_path}
Use the Write tool to create the file.

## Source metadata
- Speaker: {speaker_name or "Unknown"}
- Original title: {video_title or "Unknown"}
- Source file: {input_path or "pasted text"}

## The Three-Pass Refining Process

### Pass 1: Classify and Strip (Dross Removal)

Read the full transcript and classify every section:

**DROSS (remove entirely):**
- Self-promotion ("I have a million followers", "I've done billions of views")
- Product/service pitches ("check out my course", "use my tool at...")
- Channel engagement bait ("like and subscribe", "leave a comment")
- Community/discord/newsletter plugs
- Sponsor segments
- Vague hype with no substance ("this is going to blow your mind")
- Repetitive recaps that add nothing new (keep the first clear statement)
- Credibility posturing that doesn't teach anything
- Filler transitions ("all right", "now look", "so guys")
- Meta-commentary about the video itself ("in this video I'm going to...")
- Sign-offs and outros

**GOLD (preserve and refine):**
- Core principles and frameworks
- Definitions of key concepts
- Concrete examples that illustrate a principle
- Specific techniques or methods
- Cause-and-effect explanations
- Contrasts and comparisons that clarify thinking
- Actionable steps or checklists
- Mental models or decision frameworks
- Data points or evidence
- Counterintuitive insights

### Pass 2: Structure and Synthesize (Smelting)

Take all the gold from Pass 1 and forge it:

1. **Identify the core thesis** — the one big idea
2. **Map the framework** — most good videos teach a system, find it, name its parts
3. **Order by logic, not video sequence** — reorganize for clarity
4. **Compress examples** — 2-minute examples become 2-sentence illustrations
5. **Extract implicit knowledge** — unstated principles that make the advice work
6. **Resolve redundancy** — same point three ways? pick the clearest, discard the rest

### Pass 3: Polish and Verify (Assay)

- **Completeness** — scan the original for missed insights
- **Accuracy** — faithfully represent what the speaker said, don't add opinions
- **Density** — every sentence earns its place or gets cut
- **Actionability** — can someone act on this without watching the video?

## Output Format

Write a markdown file with this exact structure:

```markdown
# [Descriptive Title — What This Actually Teaches]

**Source:** [Speaker Name] — "[Original Video Title]"

## Core Thesis

[1-3 sentences capturing the central argument]

## Key Principles

### [Principle Name]

[Explanation — what it is, why it matters, how it works]

[Compressed example if it clarifies]

### [Next Principle...]

## Actionable Takeaways

[Numbered list of concrete things to do with this knowledge.
Each specific enough to act on without the video.]

## Mental Models

[Optional — only if the video introduces reusable thinking frameworks.
Skip entirely if the video is purely tactical.]
```

**Formatting rules:**
- Headers separate distinct ideas, not decoration
- Paragraphs: 2-4 sentences max
- Plain, direct language — technical reference density, not blog post
- No bullet points for things that should be prose
- No filler phrases ("it's important to note that...")
- Preserve the speaker's terminology when it names a useful concept

## Quality Test

The output must pass: **If someone reads only your distillation and never watches
the video, they walk away with every piece of actionable knowledge — and none of
the noise.**

Secondary test: **A reader can scan it in 2 minutes and know if this knowledge
is relevant to them.**

## Raw Transcript

{transcript_text}
```

---

## Step 4 — After subagent returns

1. Verify the output file was written
2. Report to the user:
   - Output file path
   - Brief summary of what was extracted (1-2 sentences)
   - Word count comparison: original vs refined (shows compression ratio)

For batch processing, report a table:

```
| Source | Output | Compression |
|---|---|---|
| 3 Tips for Telling a Better Story.txt | refined/storybrand-storytelling-tips.md | 2,847 → 412 words (86%) |
| Why Great Leaders Speak in Soundbites.txt | refined/soundbite-leadership.md | 1,923 → 287 words (85%) |
```

---

## Step 5 — Handle edge cases

| Situation | Action |
|---|---|
| Transcript is "[No transcript available]" | Skip, report "no transcript" |
| Transcript is <100 words | Too short to refine, skip |
| Transcript has YAML frontmatter | Parse speaker/title from frontmatter for attribution |
| Multiple transcripts from same channel | Process in parallel, create channel summary if requested |
| User asks to refine a video URL | Chain: yt-transcript fetch → refine pipeline |
| Transcript is not English | Refine in the transcript's language, or ask user preference |

---

## Examples

**Single file:**
```
User: "distill this transcript" + provides file path
→ Read file
→ Dispatch Sonnet subagent with transcript + refining prompt
→ Write refined output to refined/ subdirectory
→ Report results
```

**YouTube URL:**
```
User: "extract the gold from https://youtube.com/watch?v=ABC123"
→ Fetch transcript: yt-transcript ABC123
→ Dispatch Sonnet subagent
→ Write refined output
→ Report results
```

**Batch:**
```
User: "refine all the StoryBrand transcripts"
→ Glob ~/Projects/transcripts/StoryBrand*/**/*.txt
→ Filter out "[No transcript available]" files
→ Dispatch up to 4 Sonnet subagents in parallel
→ Write each to refined/ subdirectory
→ Report batch results table
```

**Chained with youtube-transcript skill:**
```
User: "get the transcript from this video and distill it" + URL
→ Use yt-transcript to fetch
→ Then dispatch refiner subagent
→ Single seamless pipeline
```
