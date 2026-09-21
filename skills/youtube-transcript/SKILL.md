---
name: youtube-transcript
description: Fetch YouTube video transcripts as plain text and list channel videos using a local Rust CLI tool. Use this skill whenever the user provides a YouTube URL or video ID and wants the transcript, captions, subtitles, or spoken content of the video. Also trigger when the user wants to list all videos from a channel, discover a channel from a video, or analyze/summarize YouTube content. The skill bootstraps the required Rust binary automatically on first use — no manual setup required.
---

# YouTube Transcript Skill

Fetches YouTube transcripts and lists channel videos using a local Rust binary
(`yt-transcript`). The binary scrapes YouTube pages for InnerTube data, calls
the InnerTube API with appropriate client contexts, and handles pagination.
No API key, no Whisper, no audio download.

Source is fully local at `~/.local/share/yt-transcript/` — we own and maintain it.

---

## Step 1 — Resolve the input

Determine what the user wants:

| User intent | Command |
|---|---|
| Get transcript of a video | `yt-transcript <video-id-or-url> [lang]` |
| List available transcript languages | `yt-transcript --list <video-id-or-url>` |
| List all videos from a channel | `yt-transcript --channel <video-or-@handle-or-url>` |
| Get channel ID/name from a video | `yt-transcript --channel-id <video-id-or-url>` |
| Get rich video metadata as JSON | `yt-transcript --video-meta <video-id-or-url>` |
| Batch download archive from TSV | `yt-transcript --archive <tsv-file> [--workers N] [--limit N]` |

**Input format resolution:**

| Input format | Accepted by |
|---|---|
| `https://www.youtube.com/watch?v=ABC123` | all commands |
| `https://youtu.be/ABC123` | all commands |
| bare 11-char ID (e.g. `dQw4w9WgXcQ`) | all commands |
| `@handle` | `--channel`, `--channel-id` |
| `https://www.youtube.com/@handle` | `--channel`, `--channel-id` |
| `https://www.youtube.com/channel/UCxxx` | `--channel`, `--channel-id` |
| `https://www.youtube.com/customname` | `--channel`, `--channel-id` |

---

## Step 2 — Check for the binary

```bash
~/.local/bin/yt-transcript --version 2>/dev/null
```

- **Exit 0 with `yt-transcript 0.5.1`** → binary exists, skip to Step 4
- **Any other result** → binary missing or outdated, proceed to Step 3

---

## Step 3 — Bootstrap the binary (first run only)

Inform the user: *"Building the yt-transcript tool for the first time — this takes
about 60 seconds."*

### 3a. Verify Rust is installed

```bash
cargo --version 2>/dev/null || echo "CARGO_MISSING"
```

If output contains `CARGO_MISSING`, stop and tell the user:

> **Rust is not installed.** Install it with:
> ```
> curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
> ```
> Then re-run this request.

### 3b. Write the project files

Write these files **exactly as shown**.

**`~/.local/share/yt-transcript/Cargo.toml`**

```toml
[package]
name = "yt-transcript"
version = "0.5.1"
edition = "2021"

[[bin]]
name = "yt-transcript"
path = "src/main.rs"

[dependencies]
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync", "fs"] }
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls", "cookies", "json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
anyhow = "1"
url = "2"

[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
strip = true
```

**`~/.local/share/yt-transcript/src/main.rs`**

```rust
use anyhow::{bail, Result};
use reqwest::Client;
use serde_json::json;
use std::env;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;

const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
                   (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 || args[1] == "--help" {
        eprintln!("Usage: yt-transcript <video-id-or-url> [lang-code]");
        eprintln!("       yt-transcript --list <video-id-or-url>");
        eprintln!("       yt-transcript --channel <video-or-@handle-or-channel-url>");
        eprintln!("       yt-transcript --channel-id <video-id-or-url>");
        eprintln!("       yt-transcript --video-meta <video-id-or-url>");
        eprintln!("       yt-transcript --archive <tsv-file> [--workers N] [--limit N]");
        eprintln!("       yt-transcript --version");
        eprintln!("Example: yt-transcript dQw4w9WgXcQ en");
        std::process::exit(1);
    }

    if args[1] == "--version" {
        println!("yt-transcript 0.5.1");
        return Ok(());
    }

    let client = Client::builder().user_agent(UA).build()?;

    if args[1] == "--channel-id" {
        let raw = args.get(2).map(|s| s.as_str()).unwrap_or("");
        if raw.is_empty() {
            bail!("--channel-id requires a video ID, URL, or @handle");
        }
        let (channel_id, channel_name) = resolve_channel(&client, raw).await?;
        println!("{}\t{}", channel_id, channel_name);
        return Ok(());
    }

    if args[1] == "--video-meta" {
        let raw = args.get(2).map(|s| s.as_str()).unwrap_or("");
        if raw.is_empty() {
            bail!("--video-meta requires a video ID or URL");
        }
        let video_id = extract_video_id(raw)?;
        let meta = fetch_video_meta(&client, &video_id).await?;
        println!("{}", serde_json::to_string_pretty(&meta)?);
        return Ok(());
    }

    if args[1] == "--archive" {
        let tsv_path = match args.get(2) {
            Some(p) if !p.starts_with("--") => p.as_str(),
            _ => bail!("--archive requires a TSV file path"),
        };
        let mut workers = 2usize;
        let mut limit: Option<usize> = None;
        let mut i = 3;
        while i < args.len() {
            match args[i].as_str() {
                "--workers" => {
                    i += 1;
                    workers = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(2);
                }
                "--limit" => {
                    i += 1;
                    limit = args.get(i).and_then(|s| s.parse().ok());
                }
                _ => {}
            }
            i += 1;
        }
        let arc_client = Arc::new(client);
        run_archive(arc_client, tsv_path, workers, limit).await?;
        return Ok(());
    }

    if args[1] == "--channel" {
        let raw = args.get(2).map(|s| s.as_str()).unwrap_or("");
        if raw.is_empty() {
            bail!("--channel requires a video ID, URL, or @handle");
        }
        let (channel_id, channel_name) = resolve_channel(&client, raw).await?;
        eprintln!("Channel: {} ({})", channel_name, channel_id);
        let videos = fetch_channel_videos(&client, &channel_id).await?;
        eprintln!("Total videos: {}", videos.len());
        for v in &videos {
            println!(
                "{}\thttps://www.youtube.com/watch?v={}\t{}\t{}\t{}\t{}",
                v.video_id, v.video_id, v.title, v.duration, v.views, v.published
            );
        }
        return Ok(());
    }

    let is_list = args[1] == "--list";
    let raw = if is_list {
        args.get(2).map(|s| s.as_str()).unwrap_or("")
    } else {
        args[1].as_str()
    };

    let video_id = extract_video_id(raw)?;
    let tracks = fetch_caption_tracks(&client, &video_id).await?;

    if is_list {
        println!("Available transcripts for {}:", video_id);
        for t in &tracks {
            println!(
                "  {} ({}) - auto-generated: {}",
                t.lang_code, t.lang_name, t.is_auto
            );
        }
        return Ok(());
    }

    let lang = args.get(2).map(|s| s.as_str()).unwrap_or("en");
    let track = tracks
        .iter()
        .find(|t| t.lang_code == lang && !t.is_auto)
        .or_else(|| tracks.iter().find(|t| t.lang_code == lang))
        .or_else(|| tracks.iter().find(|t| t.lang_code.starts_with(lang)))
        .ok_or_else(|| {
            let available: Vec<&str> = tracks.iter().map(|t| t.lang_code.as_str()).collect();
            anyhow::anyhow!("No transcript for '{}'. Available: {:?}", lang, available)
        })?;

    eprintln!(
        "# {} ({}) | auto-generated: {}",
        track.lang_name, track.lang_code, track.is_auto
    );

    // Strip fmt=srv3 if present — default (no fmt) returns plain XML
    let caption_url = track.base_url.replace("&fmt=srv3", "");
    let xml = client
        .get(&caption_url)
        .header("Accept-Language", "en-US")
        .send()
        .await?
        .text()
        .await?;

    if xml.is_empty() {
        bail!("YouTube returned empty caption data for {} (lang={})", video_id, lang);
    }

    println!("{}", extract_text(&xml));
    Ok(())
}

// =============================================================================
// Archive command
// =============================================================================

struct TsvRow {
    video_id: String,
    title: String,
    duration_str: String,
    views_str: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum VideoType {
    WorshipService,
    SundaySchool,
    Conference,
    Qa,
    Memorial,
    Baptism,
    SpecialMusic,
    Other,
}

impl VideoType {
    fn as_str(self) -> &'static str {
        match self {
            Self::WorshipService => "worship_service",
            Self::SundaySchool => "sunday_school",
            Self::Conference => "conference",
            Self::Qa => "qa",
            Self::Memorial => "memorial",
            Self::Baptism => "baptism",
            Self::SpecialMusic => "special_music",
            Self::Other => "other",
        }
    }
}

async fn run_archive(
    client: Arc<Client>,
    tsv_path: &str,
    workers: usize,
    limit: Option<usize>,
) -> Result<()> {
    let rows = parse_tsv(tsv_path, limit)?;
    let out_dir = PathBuf::from(tsv_path)
        .parent()
        .unwrap_or(std::path::Path::new("."))
        .to_path_buf();

    let total = rows.len();
    eprintln!("Archive: {} videos | {} workers | output: {}", total, workers, out_dir.display());

    // Pre-filter already-downloaded (only skip if transcript was successfully fetched)
    let (pending, skipped_count) = {
        let mut pending = Vec::new();
        let mut skipped = 0usize;
        for row in rows {
            let path = out_dir.join(sanitize_filename(&row.title));
            let already_done = std::fs::read_to_string(&path)
                .map(|contents| contents.contains("transcript_available: true"))
                .unwrap_or(false);
            if already_done {
                skipped += 1;
            } else {
                pending.push(row);
            }
        }
        (pending, skipped)
    };
    if skipped_count > 0 {
        eprintln!("  Skipping {} already downloaded.", skipped_count);
    }

    let fail_path = out_dir.join("no_transcript.txt");
    let mut fail_file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&fail_path)?;

    let sem = Arc::new(tokio::sync::Semaphore::new(workers));
    let mut set = tokio::task::JoinSet::new();

    for row in pending {
        let client = Arc::clone(&client);
        let sem = Arc::clone(&sem);
        let out_dir = out_dir.clone();
        set.spawn(async move {
            let _permit = sem.acquire().await.unwrap();
            let video_id = row.video_id.clone();
            let title = row.title.clone();
            let result = process_video_archive(&client, &row, &out_dir).await;
            (video_id, title, result)
        });
    }

    let mut done = skipped_count;
    let mut failures = 0usize;

    while let Some(join_result) = set.join_next().await {
        done += 1;
        let pct = done as f64 / total as f64 * 100.0;
        match join_result {
            Ok((_video_id, title, Ok(_path))) => {
                let short: String = title.chars().take(72).collect();
                eprintln!("[{}/{} {:.1}%] OK  {}", done, total, pct, short);
            }
            Ok((video_id, title, Err(e))) => {
                failures += 1;
                let _ = writeln!(fail_file, "{}\t{}\t{}", video_id, title, e);
                eprintln!("[{}/{} {:.1}%] FAIL {} — {}", done, total, pct, video_id, e);
            }
            Err(e) => {
                failures += 1;
                eprintln!("[{}/{} {:.1}%] PANIC — {}", done, total, pct, e);
            }
        }
    }

    let succeeded = done - failures - skipped_count;
    eprintln!("\nDone. {} succeeded, {} failed, {} skipped.", succeeded, failures, skipped_count);
    if failures > 0 {
        eprintln!("Failures logged to: {}", fail_path.display());
    }
    Ok(())
}

async fn process_video_archive(
    client: &Client,
    row: &TsvRow,
    out_dir: &std::path::Path,
) -> Result<PathBuf> {
    // Fetch rich metadata (best-effort — fall back to TSV values on failure)
    let meta = fetch_video_meta(client, &row.video_id).await.ok();
    let meta = meta.as_ref();

    let title = meta
        .and_then(|m| m.get("title"))
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or(&row.title)
        .to_string();

    let tags: Vec<String> = meta
        .and_then(|m| m.get("tags"))
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(str::to_string)).collect())
        .unwrap_or_default();

    let description = meta
        .and_then(|m| m.get("description"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let published = meta
        .and_then(|m| m.get("publish_date"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let duration_seconds = meta
        .and_then(|m| m.get("duration_seconds"))
        .and_then(|v| v.as_u64())
        .unwrap_or(0);

    let view_count_meta = meta
        .and_then(|m| m.get("view_count"))
        .and_then(|v| v.as_u64())
        .unwrap_or(0);

    let duration = if duration_seconds > 0 {
        seconds_to_duration(duration_seconds)
    } else {
        row.duration_str.clone()
    };

    let views_tsv = parse_view_count(&row.views_str);
    let views = if views_tsv > 0 { views_tsv } else { view_count_meta };

    // Classify and extract metadata
    let video_type = classify_video_type(&title, &tags);
    let passage = if video_type == VideoType::WorshipService {
        extract_passage(&title)
    } else {
        String::new()
    };
    let book = extract_book(&passage);
    let series = extract_series(&title, video_type);
    let speaker = extract_speaker(&title, &description);

    // Fetch transcript text (best-effort)
    let transcript_text = fetch_transcript_text(client, &row.video_id).await;
    let transcript_available = transcript_text.is_some();
    let body = transcript_text.as_deref().unwrap_or("[No transcript available]");

    // Assemble and write file
    let frontmatter = build_frontmatter(
        &row.video_id, &title, video_type, &series, &book, &passage,
        &speaker, &duration, &published, views, transcript_available, &tags, &description,
    );
    let content = format!("{}\n\n{}\n", frontmatter, body);

    let out_path = out_dir.join(sanitize_filename(&title));
    std::fs::write(&out_path, content.as_bytes())?;
    Ok(out_path)
}

/// Fetch transcript as plain text; returns None if unavailable.
async fn fetch_transcript_text(client: &Client, video_id: &str) -> Option<String> {
    let tracks = fetch_caption_tracks(client, video_id).await.ok()?;
    let track = tracks
        .iter()
        .find(|t| t.lang_code == "en" && !t.is_auto)
        .or_else(|| tracks.iter().find(|t| t.lang_code == "en"))
        .or_else(|| tracks.iter().find(|t| t.lang_code.starts_with("en")))?;

    let caption_url = track.base_url.replace("&fmt=srv3", "");
    let xml = client
        .get(&caption_url)
        .header("Accept-Language", "en-US")
        .send()
        .await
        .ok()?
        .text()
        .await
        .ok()?;

    if xml.is_empty() {
        return None;
    }
    let text = extract_text(&xml);
    if text.is_empty() { None } else { Some(text) }
}

fn parse_tsv(path: &str, limit: Option<usize>) -> Result<Vec<TsvRow>> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| anyhow::anyhow!("Cannot read TSV '{}': {}", path, e))?;
    let mut rows = Vec::new();
    for line in content.lines() {
        let parts: Vec<&str> = line.splitn(6, '\t').collect();
        if parts.len() < 3 {
            continue;
        }
        rows.push(TsvRow {
            video_id: parts[0].to_string(),
            title: parts[2].to_string(),
            duration_str: parts.get(3).copied().unwrap_or("").to_string(),
            views_str: parts.get(4).copied().unwrap_or("").to_string(),
        });
        if limit.map(|n| rows.len() >= n).unwrap_or(false) {
            break;
        }
    }
    Ok(rows)
}

// --- Classification ---

fn classify_video_type(title: &str, tags: &[String]) -> VideoType {
    let t = title.to_lowercase();
    let tag_str = tags.join(" ").to_lowercase();

    if title.starts_with("Special:") || t.contains("christmas special") {
        return VideoType::SpecialMusic;
    }
    if t.contains("memorial") {
        return VideoType::Memorial;
    }
    if t.contains("baptism service") {
        return VideoType::Baptism;
    }
    if t.contains("q&a") || t.contains("question and answer") {
        return VideoType::Qa;
    }
    if t.contains("conference") || has_session_number(title) || tag_str.contains("conference") {
        return VideoType::Conference;
    }
    if t.contains("sunday school") || has_lesson_number(title) {
        return VideoType::SundaySchool;
    }
    if !extract_passage(title).is_empty() {
        return VideoType::WorshipService;
    }
    VideoType::Other
}

fn has_lesson_number(title: &str) -> bool {
    let lower = title.to_lowercase();
    if let Some(pos) = lower.find("lesson ") {
        return lower[pos + 7..]
            .trim_start_matches('#')
            .trim_start()
            .starts_with(|c: char| c.is_ascii_digit());
    }
    false
}

fn has_session_number(title: &str) -> bool {
    let lower = title.to_lowercase();
    if let Some(pos) = lower.find("session ") {
        return lower[pos + 8..].starts_with(|c: char| c.is_ascii_digit());
    }
    false
}

// --- Passage extraction ---

/// Find a scripture passage like "2 Peter 2:19-20" inside parentheses.
fn extract_passage(title: &str) -> String {
    let mut s = title;
    while let Some(open) = s.find('(') {
        let inner_start = open + 1;
        if let Some(close_rel) = s[inner_start..].find(')') {
            let inner = s[inner_start..inner_start + close_rel].trim();
            if is_scripture_passage(inner) {
                return inner.to_string();
            }
        }
        s = &s[inner_start..];
    }
    String::new()
}

fn is_scripture_passage(s: &str) -> bool {
    // Must contain ':' for chapter:verse separation
    let Some(colon_pos) = s.find(':') else { return false };
    let before = s[..colon_pos].trim();
    let after = s[colon_pos + 1..].trim();
    // before: must have letters (book name) and end with a digit (chapter)
    // after: must start with a digit (verse)
    before.chars().any(|c| c.is_alphabetic())
        && before.ends_with(|c: char| c.is_ascii_digit())
        && after.starts_with(|c: char| c.is_ascii_digit())
}

/// "2 Peter 2:19-20" → "2 Peter"
fn extract_book(passage: &str) -> String {
    if passage.is_empty() { return String::new(); }
    let Some(colon_pos) = passage.find(':') else { return String::new() };
    let before = passage[..colon_pos].trim();
    // Strip the chapter number at the end (last word that is all digits)
    if let Some(last_space) = before.rfind(' ') {
        before[..last_space].trim().to_string()
    } else {
        String::new()
    }
}

/// Extract series name based on video type.
fn extract_series(title: &str, video_type: VideoType) -> String {
    match video_type {
        VideoType::WorshipService => extract_book(&extract_passage(title)),

        VideoType::SundaySchool => {
            // "Christian Ethics, Lesson 20: ..." → "Christian Ethics"
            let lower = title.to_lowercase();
            if let Some(lesson_pos) = lower.find("lesson") {
                let prefix = &title[..lesson_pos];
                if let Some(sep_pos) = prefix.rfind(',').or_else(|| prefix.rfind(':')) {
                    return title[..sep_pos].trim().to_string();
                }
                return prefix.trim().to_string();
            }
            String::new()
        }

        VideoType::Conference => {
            // Strip "Session N" suffix if present
            let lower = title.to_lowercase();
            if let Some(pos) = lower.find("session") {
                return title[..pos]
                    .trim_end_matches(|c: char| c == '-' || c == '–' || c.is_whitespace())
                    .to_string();
            }
            // Otherwise strip known trailing separators
            title
                .trim_end_matches(|c: char| c == ',' || c == ':' || c.is_whitespace())
                .to_string()
        }

        _ => String::new(),
    }
}

/// Infer the speaker from title and description. Defaults to "Jim Osman".
fn extract_speaker(title: &str, description: &str) -> String {
    // "... with Dr./Rev./Pastor Firstname Lastname"
    if let Some(s) = find_speaker_with(title) {
        return s;
    }
    // "Firstname Lastname preaches/teaches" in description
    if let Some(s) = find_speaker_in_description(description) {
        return s;
    }
    "Jim Osman".to_string()
}

fn find_speaker_with(text: &str) -> Option<String> {
    let lower = text.to_lowercase();
    let pos = lower.find(" with ")?;
    let rest = text[pos + 6..].trim_start();
    // Strip optional honorific
    let rest = if rest.to_lowercase().starts_with("dr.") {
        rest[3..].trim_start()
    } else if rest.to_lowercase().starts_with("rev.") {
        rest[4..].trim_start()
    } else if rest.to_lowercase().starts_with("pastor ") {
        rest[7..].trim_start()
    } else {
        rest
    };
    // Expect two capitalized words
    let words: Vec<&str> = rest
        .split_whitespace()
        .take(2)
        .filter(|w| w.starts_with(|c: char| c.is_uppercase()))
        .collect();
    if words.len() == 2 { Some(words.join(" ")) } else { None }
}

fn find_speaker_in_description(desc: &str) -> Option<String> {
    for keyword in &["preaches", "teaches", "presents", "speaks"] {
        if let Some(pos) = desc.to_lowercase().find(keyword) {
            let before = desc[..pos].trim();
            let words: Vec<&str> = before.split_whitespace().collect();
            let n = words.len();
            if n >= 2 {
                let last = words[n - 1];
                let second = words[n - 2];
                if last.starts_with(|c: char| c.is_uppercase())
                    && second.starts_with(|c: char| c.is_uppercase())
                {
                    return Some(format!("{} {}", second, last));
                }
            }
        }
    }
    None
}

// --- File helpers ---

fn parse_view_count(views_str: &str) -> u64 {
    views_str
        .split_whitespace()
        .next()
        .unwrap_or("")
        .replace(',', "")
        .parse()
        .unwrap_or(0)
}

fn seconds_to_duration(seconds: u64) -> String {
    if seconds == 0 { return String::new(); }
    let h = seconds / 3600;
    let m = (seconds % 3600) / 60;
    let s = seconds % 60;
    if h > 0 {
        format!("{}:{:02}:{:02}", h, m, s)
    } else {
        format!("{}:{:02}", m, s)
    }
}

fn sanitize_filename(title: &str) -> String {
    let mut result = String::new();
    let mut last_was_space = false;
    for ch in title.chars() {
        let out = match ch {
            '/' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\\' => '-',
            c => c,
        };
        if out == ' ' || out == '-' {
            if !last_was_space {
                result.push(out);
            }
            last_was_space = out == ' ';
        } else {
            last_was_space = false;
            result.push(out);
        }
    }
    let trimmed = result.trim();
    let truncated: String = trimmed.chars().take(120).collect();
    format!("{}.txt", truncated.trim_end())
}

fn yaml_str(s: &str) -> String {
    if s.is_empty() {
        return "\"\"".to_string();
    }
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

#[allow(clippy::too_many_arguments)]
fn build_frontmatter(
    video_id: &str,
    title: &str,
    video_type: VideoType,
    series: &str,
    book: &str,
    passage: &str,
    speaker: &str,
    duration: &str,
    published: &str,
    views: u64,
    transcript_available: bool,
    tags: &[String],
    description: &str,
) -> String {
    let mut lines = vec!["---".to_string()];
    lines.push(format!("video_id: {}", video_id));
    lines.push(format!("url: https://www.youtube.com/watch?v={}", video_id));
    lines.push(format!("title: {}", yaml_str(title)));
    lines.push(format!("type: {}", video_type.as_str()));
    if !series.is_empty() {
        lines.push(format!("series: {}", yaml_str(series)));
    }
    if !book.is_empty() {
        lines.push(format!("book: {}", yaml_str(book)));
    }
    if !passage.is_empty() {
        lines.push(format!("passage: {}", yaml_str(passage)));
    }
    lines.push(format!("speaker: {}", yaml_str(speaker)));
    lines.push(format!("duration: {}", yaml_str(duration)));
    lines.push(format!("published: {}", yaml_str(published)));
    lines.push(format!("views: {}", views));
    lines.push(format!("transcript_available: {}", transcript_available));
    if tags.is_empty() {
        lines.push("tags: []".to_string());
    } else {
        lines.push("tags:".to_string());
        for tag in tags {
            lines.push(format!("  - {}", yaml_str(tag)));
        }
    }
    if description.is_empty() {
        lines.push("description: \"\"".to_string());
    } else {
        lines.push("description: |".to_string());
        for line in description.lines() {
            lines.push(format!("  {}", line));
        }
    }
    lines.push("---".to_string());
    lines.join("\n")
}

// =============================================================================
// Video metadata functions
// =============================================================================

/// Fetch rich metadata for a single video from its watch page HTML.
async fn fetch_video_meta(client: &Client, video_id: &str) -> Result<serde_json::Value> {
    let watch_url = format!("https://www.youtube.com/watch?v={}", video_id);
    let html = client
        .get(&watch_url)
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await?
        .text()
        .await?;

    let title = extract_meta_title(&html).unwrap_or_default();
    let description = extract_meta_content(&html, "name", "description").unwrap_or_default();
    let keywords_str = extract_meta_content(&html, "name", "keywords").unwrap_or_default();
    let tags: Vec<String> = keywords_str
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    let publish_date = extract_itemprop_content(&html, "uploadDate")
        .map(|s| s[..s.len().min(10)].to_string())
        .unwrap_or_default();

    let duration_iso = extract_itemprop_content(&html, "duration").unwrap_or_default();
    let duration_seconds = parse_iso_duration(&duration_iso);

    let view_count: u64 = extract_itemprop_content(&html, "interactionCount")
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    Ok(json!({
        "video_id": video_id,
        "title": title,
        "description": description,
        "tags": tags,
        "publish_date": publish_date,
        "duration_seconds": duration_seconds,
        "view_count": view_count,
    }))
}

/// Extract content="..." from a meta tag matching attr="value" in the same tag.
fn extract_meta_content(html: &str, attr: &str, value: &str) -> Option<String> {
    let pattern = format!("{}=\"{}\"", attr, value);
    let mut search_from = 0;
    while let Some(rel_pos) = html[search_from..].find(&pattern) {
        let pos = search_from + rel_pos;
        if let Some(tag_start) = html[..pos].rfind('<') {
            if let Some(tag_end_rel) = html[pos..].find('>') {
                let tag_end = pos + tag_end_rel;
                let tag = &html[tag_start..=tag_end];
                let content_marker = "content=\"";
                if let Some(c_pos) = tag.find(content_marker) {
                    let c_start = tag_start + c_pos + content_marker.len();
                    if let Some(c_len) = html[c_start..].find('"') {
                        return Some(html_decode(&html[c_start..c_start + c_len]));
                    }
                }
            }
        }
        search_from = pos + 1;
    }
    None
}

/// Extract content="..." from a tag with itemprop="prop".
fn extract_itemprop_content(html: &str, prop: &str) -> Option<String> {
    let pattern = format!("itemprop=\"{}\"", prop);
    let mut search_from = 0;
    while let Some(rel_pos) = html[search_from..].find(&pattern) {
        let pos = search_from + rel_pos;
        if let Some(tag_start) = html[..pos].rfind('<') {
            if let Some(tag_end_rel) = html[pos..].find('>') {
                let tag_end = pos + tag_end_rel;
                let tag = &html[tag_start..=tag_end];
                let content_marker = "content=\"";
                if let Some(c_pos) = tag.find(content_marker) {
                    let c_start = tag_start + c_pos + content_marker.len();
                    if let Some(c_len) = html[c_start..].find('"') {
                        return Some(html[c_start..c_start + c_len].to_string());
                    }
                }
            }
        }
        search_from = pos + 1;
    }
    None
}

/// Extract and clean the page title (strips " - YouTube" suffix).
fn extract_meta_title(html: &str) -> Option<String> {
    let start = html.find("<title>")? + "<title>".len();
    let end = start + html[start..].find("</title>")?;
    Some(html_decode(&html[start..end]).replace(" - YouTube", "").trim().to_string())
}

/// Parse ISO 8601 duration (PT[nH][nM][nS]) to total seconds.
fn parse_iso_duration(iso: &str) -> u64 {
    if !iso.starts_with("PT") { return 0; }
    let s = &iso[2..];
    let mut total: u64 = 0;
    let mut current = String::new();
    for ch in s.chars() {
        match ch {
            '0'..='9' => current.push(ch),
            'H' => { total += current.parse::<u64>().unwrap_or(0) * 3600; current.clear(); }
            'M' => { total += current.parse::<u64>().unwrap_or(0) * 60; current.clear(); }
            'S' => { total += current.parse::<u64>().unwrap_or(0); current.clear(); }
            _ => {}
        }
    }
    total
}

// =============================================================================
// Channel functions
// =============================================================================

struct ChannelVideo {
    video_id: String,
    title: String,
    duration: String,
    views: String,
    published: String,
}

/// Resolve any input (video ID/URL, @handle, channel URL) to (channel_id, channel_name).
async fn resolve_channel(client: &Client, input: &str) -> Result<(String, String)> {
    // @handle
    if input.starts_with('@') {
        return resolve_channel_from_page(
            client,
            &format!("https://www.youtube.com/{}", input),
        )
        .await;
    }

    // URL
    if let Ok(url) = url::Url::parse(input) {
        let path = url.path();

        // /channel/UCxxx
        if path.starts_with("/channel/") {
            let channel_id = path
                .strip_prefix("/channel/")
                .unwrap()
                .split('/')
                .next()
                .unwrap();
            return resolve_channel_from_page(
                client,
                &format!("https://www.youtube.com/channel/{}", channel_id),
            )
            .await;
        }

        // /@handle
        if path.starts_with("/@") {
            let handle = path.split('/').nth(1).unwrap_or(path.trim_start_matches('/'));
            return resolve_channel_from_page(
                client,
                &format!("https://www.youtube.com/{}", handle),
            )
            .await;
        }

        // Video URL (has ?v= or is youtu.be)
        if url.query_pairs().any(|(k, _)| k == "v")
            || url.host_str() == Some("youtu.be")
        {
            if let Ok(video_id) = extract_video_id(input) {
                return resolve_channel_from_video(client, &video_id).await;
            }
        }

        // Any other YouTube URL — custom URL (/name, /c/name, /user/name)
        let host = url.host_str().unwrap_or("");
        if host.contains("youtube.com") {
            return resolve_channel_from_page(client, input).await;
        }
    }

    // Bare video ID
    if input.len() == 11 && input.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        return resolve_channel_from_video(client, input).await;
    }

    bail!("Could not determine channel from: {}", input)
}

/// Resolve channel info from a channel/handle page URL.
async fn resolve_channel_from_page(client: &Client, page_url: &str) -> Result<(String, String)> {
    let html = client
        .get(page_url)
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await?
        .text()
        .await?;

    let data = extract_yt_initial_data(&html)
        .ok_or_else(|| anyhow::anyhow!("Could not extract ytInitialData from channel page"))?;

    let channel_id = data
        .pointer("/metadata/channelMetadataRenderer/externalId")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("Could not find channel ID in page data"))?
        .to_string();

    let channel_name = data
        .pointer("/metadata/channelMetadataRenderer/title")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown")
        .to_string();

    Ok((channel_id, channel_name))
}

/// Resolve channel info from a video's watch page.
async fn resolve_channel_from_video(
    client: &Client,
    video_id: &str,
) -> Result<(String, String)> {
    let watch_url = format!("https://www.youtube.com/watch?v={}", video_id);
    let html = client
        .get(&watch_url)
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await?
        .text()
        .await?;

    let channel_id = extract_channel_id_from_html(&html)
        .ok_or_else(|| anyhow::anyhow!("Could not find channel ID in watch page for {}", video_id))?;
    let channel_name =
        extract_channel_name_from_html(&html).unwrap_or_else(|| "Unknown".to_string());

    Ok((channel_id, channel_name))
}

fn extract_channel_id_from_html(html: &str) -> Option<String> {
    // Try <meta itemprop="channelId" content="UCxxx">
    let marker = "itemprop=\"channelId\" content=\"";
    if let Some(pos) = html.find(marker) {
        let start = pos + marker.len();
        if let Some(end) = html[start..].find('"') {
            return Some(html[start..start + end].to_string());
        }
    }
    // Fallback: "channelId":"UCxxx" in embedded JSON
    let marker = "\"channelId\":\"";
    let start = html.find(marker)? + marker.len();
    let end = html[start..].find('"')? + start;
    Some(html[start..end].to_string())
}

fn extract_channel_name_from_html(html: &str) -> Option<String> {
    // Try "ownerChannelName":"..."
    let marker = "\"ownerChannelName\":\"";
    if let Some(pos) = html.find(marker) {
        let start = pos + marker.len();
        if let Some(end) = html[start..].find('"') {
            return Some(html_decode(&html[start..start + end]));
        }
    }
    // Fallback: "author":"..."
    let marker = "\"author\":\"";
    let start = html.find(marker)? + marker.len();
    let end = html[start..].find('"')? + start;
    Some(html_decode(&html[start..end]))
}

/// Fetch all videos from a channel, paginating through continuation tokens.
async fn fetch_channel_videos(
    client: &Client,
    channel_id: &str,
) -> Result<Vec<ChannelVideo>> {
    let mut videos = Vec::new();

    // First page
    let url = format!("https://www.youtube.com/channel/{}/videos", channel_id);
    let html = client
        .get(&url)
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .await?
        .text()
        .await?;

    let data = extract_yt_initial_data(&html)
        .ok_or_else(|| anyhow::anyhow!("Could not extract ytInitialData from channel page"))?;
    let api_key = extract_innertube_key(&html)
        .ok_or_else(|| anyhow::anyhow!("Could not extract INNERTUBE_API_KEY from channel page"))?;

    let grid_contents = find_video_grid(&data)
        .ok_or_else(|| anyhow::anyhow!("Could not find video grid in channel data"))?;

    let mut continuation_token = None;
    parse_video_items(grid_contents, &mut videos, &mut continuation_token);
    eprintln!("  ... fetched {} videos", videos.len());

    let mut page = 1;
    while let Some(token) = continuation_token.take() {
        page += 1;
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;

        let browse_url = format!(
            "https://www.youtube.com/youtubei/v1/browse?key={}",
            api_key
        );
        let payload = json!({
            "continuation": token,
            "context": {
                "client": {
                    "clientName": "WEB",
                    "clientVersion": "2.20240101.00.00"
                }
            }
        });

        let resp = client
            .post(&browse_url)
            .header("Content-Type", "application/json")
            .json(&payload)
            .send()
            .await?;

        if !resp.status().is_success() {
            eprintln!(
                "Warning: page {} returned HTTP {}, stopping pagination",
                page,
                resp.status()
            );
            break;
        }

        let browse_data: serde_json::Value = resp.json().await?;

        let items = browse_data
            .pointer(
                "/onResponseReceivedActions/0/appendContinuationItemsAction/continuationItems",
            )
            .and_then(|v| v.as_array());

        if let Some(items) = items {
            let before = videos.len();
            parse_video_items(items, &mut videos, &mut continuation_token);
            if videos.len() == before {
                break;
            }
            eprintln!("  ... fetched {} videos (page {})", videos.len(), page);
        } else {
            break;
        }
    }

    Ok(videos)
}

fn find_video_grid(data: &serde_json::Value) -> Option<&Vec<serde_json::Value>> {
    let tabs = data
        .pointer("/contents/twoColumnBrowseResultsRenderer/tabs")?
        .as_array()?;

    for tab in tabs {
        if let Some(tr) = tab.get("tabRenderer") {
            if tr.get("selected").and_then(|v| v.as_bool()) == Some(true) {
                if let Some(contents) = tr
                    .pointer("/content/richGridRenderer/contents")
                    .and_then(|v| v.as_array())
                {
                    return Some(contents);
                }
            }
        }
    }

    for tab in tabs {
        if let Some(tr) = tab.get("tabRenderer") {
            if tr.pointer("/title").and_then(|v| v.as_str()) == Some("Videos") {
                if let Some(contents) = tr
                    .pointer("/content/richGridRenderer/contents")
                    .and_then(|v| v.as_array())
                {
                    return Some(contents);
                }
            }
        }
    }

    None
}

fn parse_video_items(
    items: &[serde_json::Value],
    videos: &mut Vec<ChannelVideo>,
    continuation_token: &mut Option<String>,
) {
    for item in items {
        if let Some(vr) = item.pointer("/richItemRenderer/content/videoRenderer") {
            let video_id = vr
                .get("videoId")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let title = vr
                .pointer("/title/runs/0/text")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .replace('\t', " ");
            let duration = vr
                .pointer("/lengthText/simpleText")
                .and_then(|v| v.as_str())
                .unwrap_or("LIVE")
                .to_string();
            let views = vr
                .pointer("/viewCountText/simpleText")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let published = vr
                .pointer("/publishedTimeText/simpleText")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            if !video_id.is_empty() {
                videos.push(ChannelVideo { video_id, title, duration, views, published });
            }
        }

        if let Some(token) = item
            .pointer("/continuationItemRenderer/continuationEndpoint/continuationCommand/token")
            .and_then(|v| v.as_str())
        {
            *continuation_token = Some(token.to_string());
        }
    }
}

// =============================================================================
// Shared HTML / JSON utilities
// =============================================================================

fn extract_yt_initial_data(html: &str) -> Option<serde_json::Value> {
    let marker = "var ytInitialData = ";
    let start = html.find(marker)? + marker.len();
    let json_str = &html[start..];
    let end = find_json_end(json_str)?;
    serde_json::from_str(&json_str[..end]).ok()
}

fn find_json_end(s: &str) -> Option<usize> {
    let bytes = s.as_bytes();
    if bytes.first() != Some(&b'{') { return None; }
    let mut depth: i32 = 0;
    let mut in_string = false;
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' if in_string => i += 1,
            b'"' => in_string = !in_string,
            b'{' if !in_string => depth += 1,
            b'}' if !in_string => {
                depth -= 1;
                if depth == 0 { return Some(i + 1); }
            }
            _ => {}
        }
        i += 1;
    }
    None
}

// =============================================================================
// Transcript / caption functions
// =============================================================================

struct CaptionTrack {
    base_url: String,
    lang_code: String,
    lang_name: String,
    is_auto: bool,
}

/// Fetch caption tracks via InnerTube /player API with ANDROID client.
async fn fetch_caption_tracks(client: &Client, video_id: &str) -> Result<Vec<CaptionTrack>> {
    let watch_url = format!("https://www.youtube.com/watch?v={}", video_id);
    let html = client.get(&watch_url).send().await?.text().await?;

    let api_key = extract_innertube_key(&html)
        .ok_or_else(|| anyhow::anyhow!("Could not extract INNERTUBE_API_KEY from watch page"))?;

    let player_url = format!(
        "https://www.youtube.com/youtubei/v1/player?key={}",
        api_key
    );

    let payload = json!({
        "context": {
            "client": {
                "clientName": "ANDROID",
                "clientVersion": "20.10.38"
            }
        },
        "videoId": video_id
    });

    let resp = client
        .post(&player_url)
        .header("Content-Type", "application/json")
        .json(&payload)
        .send()
        .await?;

    let player: serde_json::Value = resp.json().await?;

    let caption_tracks = player
        .pointer("/captions/playerCaptionsTracklistRenderer/captionTracks")
        .and_then(|v| v.as_array())
        .ok_or_else(|| anyhow::anyhow!("No caption tracks found for video {}", video_id))?;

    let mut tracks = Vec::new();
    for track in caption_tracks {
        let base_url = track
            .get("baseUrl")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        let lang_code = track
            .get("languageCode")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        let lang_name = track
            .pointer("/name/simpleText")
            .or_else(|| track.pointer("/name/runs/0/text"))
            .and_then(|v| v.as_str())
            .unwrap_or(&lang_code)
            .to_string();
        let is_auto = track
            .get("kind")
            .and_then(|v| v.as_str())
            .map(|k| k == "asr")
            .unwrap_or(false);

        if !base_url.is_empty() {
            tracks.push(CaptionTrack { base_url, lang_code, lang_name, is_auto });
        }
    }

    if tracks.is_empty() {
        bail!("No usable caption tracks for video {}", video_id);
    }

    Ok(tracks)
}

fn extract_innertube_key(html: &str) -> Option<String> {
    let marker = "\"INNERTUBE_API_KEY\":\"";
    let start = html.find(marker)? + marker.len();
    let end = html[start..].find('"')? + start;
    Some(html[start..end].to_string())
}

fn extract_text(xml: &str) -> String {
    let mut parts = Vec::new();
    for segment in xml.split("<text ") {
        if let Some(tag_end) = segment.find('>') {
            if let Some(text_end) = segment[tag_end + 1..].find("</text>") {
                let raw = &segment[tag_end + 1..tag_end + 1 + text_end];
                let decoded = html_decode(raw).replace('\n', " ");
                let trimmed = decoded.trim();
                if !trimmed.is_empty() {
                    parts.push(trimmed.to_string());
                }
            }
        }
    }
    parts.join(" ")
}

fn html_decode(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
}

fn extract_video_id(input: &str) -> Result<String> {
    if input.len() == 11 && input.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        return Ok(input.to_string());
    }

    if let Ok(url) = url::Url::parse(input) {
        if url.host_str() == Some("youtu.be") {
            if let Some(seg) = url.path_segments().and_then(|mut s| s.next()) {
                if !seg.is_empty() {
                    return Ok(seg.to_string());
                }
            }
        }
        if let Some(v) = url.query_pairs().find(|(k, _)| k == "v") {
            return Ok(v.1.to_string());
        }
        if let Some(seg) = url.path_segments().and_then(|mut s| {
            s.next();
            s.next()
        }) {
            if !seg.is_empty() {
                return Ok(seg.to_string());
            }
        }
    }

    bail!("Could not extract a YouTube video ID from: {}", input)
}
```

### 3c. Compile and install

```bash
mkdir -p ~/.local/bin
cd ~/.local/share/yt-transcript
cargo build --release 2>&1
cp target/release/yt-transcript ~/.local/bin/yt-transcript
chmod +x ~/.local/bin/yt-transcript
```

If `cargo build` fails, show the error to the user and investigate. We own this
code — fix bugs directly in the source.

---

## Step 4 — Execute the command

### Fetch transcript (default)

```bash
~/.local/bin/yt-transcript <video-id> [lang]
```

Default language is `en`. Transcript text → stdout. Metadata → stderr.

### List available languages

```bash
~/.local/bin/yt-transcript --list <video-id>
```

### List all channel videos

```bash
~/.local/bin/yt-transcript --channel <video-id-or-@handle-or-url>
```

Output format (tab-separated to stdout, pipeable):
```
VIDEO_ID\tURL\tTITLE\tDURATION\tVIEWS\tPUBLISHED
```

Channel name and total count → stderr.

Pagination is automatic with 1-second delay between pages to avoid throttling.
Channels with many videos will take proportionally longer.

### Get channel ID from a video

```bash
~/.local/bin/yt-transcript --channel-id <video-id-or-url>
```

Outputs: `CHANNEL_ID\tCHANNEL_NAME`

### Get rich video metadata as JSON

```bash
~/.local/bin/yt-transcript --video-meta <video-id-or-url>
```

Outputs JSON to stdout with: `video_id`, `title`, `description`, `tags` (array),
`publish_date` (YYYY-MM-DD), `duration_seconds` (integer), `view_count` (integer).

**Examples:**

```bash
~/.local/bin/yt-transcript dQw4w9WgXcQ
~/.local/bin/yt-transcript dQw4w9WgXcQ es
~/.local/bin/yt-transcript "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
~/.local/bin/yt-transcript --list dQw4w9WgXcQ
~/.local/bin/yt-transcript --channel-id vzCy44o3JwA
~/.local/bin/yt-transcript --channel vzCy44o3JwA
~/.local/bin/yt-transcript --channel @somecreator
~/.local/bin/yt-transcript --channel vzCy44o3JwA | head -10
```

### Batch archive from TSV

Downloads all videos listed in a TSV file, writing one `.txt` file per video with
YAML frontmatter + plain-text transcript. Output files go in the **same directory
as the TSV file**. Files with `transcript_available: true` are skipped. Files where
the transcript failed (`transcript_available: false`) are automatically retried — just
re-run the same command, no manual cleanup needed.

```bash
# Full run — live progress to stderr
~/.local/bin/yt-transcript --archive ~/Videos/kcc/transcripts/kcc_videos.tsv

# Test on first 10 rows before committing to the full run
~/.local/bin/yt-transcript --archive ~/Videos/kcc/transcripts/kcc_videos.tsv --limit 10

# More workers for faster throughput (default 2; max ~4 before YouTube rate-limits)
~/.local/bin/yt-transcript --archive ~/Videos/kcc/transcripts/kcc_videos.tsv --workers 4

# Capture live progress + save log
~/.local/bin/yt-transcript --archive ~/Videos/kcc/transcripts/kcc_videos.tsv 2>&1 | tee archive.log
```

**TSV format** (tab-separated, no header):
```
VIDEO_ID  URL  TITLE  DURATION  VIEWS  RELATIVE_DATE
```
This is exactly the format produced by `--channel`.

**Output file format** — YAML frontmatter + plain text body:
```
---
video_id: 6nbwNKG7jAw
url: https://www.youtube.com/watch?v=6nbwNKG7jAw
title: "Enslaved By Error (2 Peter 2:19-20)"
type: worship_service
series: "2 Peter"
book: "2 Peter"
passage: "2 Peter 2:19-20"
speaker: "Jim Osman"
duration: "40:57"
published: "2026-03-02"
views: 684
transcript_available: true
tags:
  - "Kootenai Church"
  - "2 Peter"
description: |
  Jim Osman preaches on 2 Peter 2:19-20...
---

[transcript text]
```

**Classification types** (applied in priority order):

| Type | Trigger |
|---|---|
| `special_music` | Title starts with `Special:` or contains `Christmas Special` |
| `memorial` | Title contains `Memorial` |
| `baptism` | Title contains `Baptism Service` |
| `qa` | Title contains `Q&A` or `Question and Answer` |
| `conference` | Title contains `Conference` or `Session N` or tags include `conference` |
| `sunday_school` | Title contains `Sunday School` or `Lesson N` / `Lesson #N` |
| `worship_service` | Title contains a scripture passage `(Book Chapter:Verse)` |
| `other` | Default |

**Failure logging:** Videos that fail (no captions, HTTP error, write error) are
appended to `no_transcript.txt` in the output directory with format:
```
VIDEO_ID\tTITLE\tERROR_MESSAGE
```

**Progress output** (stderr, live as each task completes):
```
Archive: 2147 videos | 5 workers | output: /home/peter/Videos/kcc/transcripts
  Skipping 142 already downloaded.
[143/2147 6.7%] OK  Enslaved By Error (2 Peter 2:19-20)
[144/2147 6.7%] FAIL abc123def45 — No caption tracks found for video abc123def45
...
Done. 1998 succeeded, 7 failed, 142 skipped.
```

---

## Step 5 — Handle errors

| Error message contains | Cause | Response to user |
|---|---|---|
| `No caption tracks found` | No captions | "This video has no captions available." |
| `Could not extract INNERTUBE_API_KEY` | Page blocked / private | "This video is unavailable or private." |
| `No transcript for` | Lang not found | Run `--list`, show available languages |
| `empty caption data` | PO token / region issue | Check if ANDROID client approach still works |
| `Could not extract` | Bad URL/ID | Ask user for the URL or ID directly |
| `Could not find channel ID` | Private/unavailable channel | "This channel is unavailable." |
| `Could not find video grid` | Channel layout changed | YouTube may have changed page structure |
| `HTTP 429` in pagination | Rate limited | Partial results returned, inform user |
| `Cannot read TSV` | TSV path wrong | Verify path; TSV must be tab-separated with at least 3 columns |
| Archive produces no files | Wrong output dir | Output goes to TSV's parent directory |
| Many FAIL lines in archive | Rate limited | Reduce `--workers` to 1; just re-run — failed videos are auto-retried |

---

## Step 6 — Save and deliver results

### Saving transcripts to files (ALWAYS do this)

When fetching one or more transcripts, **always save to files** — never only print
to the conversation. The user plans to accumulate transcripts across sessions and
analyze them together.

**Folder naming convention:**

| Situation | Folder |
|---|---|
| Batch fetch from a channel by topic | `~/transcripts/<ChannelName> - <Topic>/` |
| Single channel, no specific topic | `~/transcripts/<ChannelName>/` |
| Mixed sources / user-named collection | `~/transcripts/<CollectionName>/` |

Use the channel name exactly as returned by `--channel` (e.g. `StoryBrand With Donald Miller`),
shortened to the recognizable brand name (e.g. `StoryBrand`). Keep folder names short and
human-readable. Ask the user if the collection name is unclear.

**File naming:** Use the video title as the filename. Sanitize by replacing
`/ : * ? " < > | \` with `-` and collapsing extra spaces. Extension: `.txt`.

**Bash pattern for a single transcript:**
```bash
FOLDER="$HOME/transcripts/StoryBrand - Storytelling"
mkdir -p "$FOLDER"
~/.local/bin/yt-transcript <video-id> > "$FOLDER/Sanitized Video Title.txt" 2>/dev/null
echo "Saved: $FOLDER/Sanitized Video Title.txt"
```

**Batch fetch pattern — run saves in parallel when fetching multiple videos:**
```bash
FOLDER="$HOME/transcripts/StoryBrand - Storytelling"
mkdir -p "$FOLDER"
# Run each fetch; failures produce empty files (check and report)
~/.local/bin/yt-transcript r6xP5DA7D7k > "$FOLDER/3 Tips for Telling a Better Story.txt" 2>/dev/null &
~/.local/bin/yt-transcript 2VidhUB66R4 > "$FOLDER/Why Telling Your Story Will Not Grow Your Business.txt" 2>/dev/null &
wait
# Report results
for f in "$FOLDER"/*.txt; do
  size=$(wc -c < "$f")
  if [ "$size" -lt 100 ]; then
    echo "FAILED (empty): $f"
  else
    echo "OK ($size bytes): $f"
  fi
done
```

After saving, tell the user:
- The folder path
- Which files saved successfully (title → filename)
- Any failures, so they can be retried

### For channel video lists

Present the filtered list as a table in the conversation. Do not save the raw channel
listing to a file unless the user asks.

### Workflow for topic-based transcript collection

1. User provides channel URL/handle and a topic of interest
2. Use `--channel` to list all videos from the channel
3. Filter the TSV list by topic — match titles against the user's stated interest
4. Present the filtered list to the user (titles, durations, dates)
5. Proceed to fetch unless the user says otherwise
6. Create folder: `~/transcripts/<ChannelName> - <Topic>/`
7. Fetch all matching transcripts in parallel, saving each to `<sanitized-title>.txt`
8. Report the saved files and folder path to the user

---

## Architecture Notes

**Why ANDROID client for transcripts?** YouTube now requires PO (Proof of Origin)
tokens for WEB client timedtext (caption) requests. The ANDROID InnerTube client
context is exempt from PO token requirements for subtitle access.

**Why WEB client for channel browsing?** The channel pages and browse API use
standard WEB client context. No PO tokens needed for listing videos.

**How channel listing works:**
1. GET channel page `/channel/{id}/videos` → extract `ytInitialData` from HTML
2. Parse video grid from selected tab's `richGridRenderer.contents[]`
3. Each `richItemRenderer.content.videoRenderer` contains video metadata
4. Extract continuation token from `continuationItemRenderer` for next page
5. POST `/youtubei/v1/browse` with continuation token for subsequent pages
6. 1-second delay between pages to avoid rate limiting
7. Stop when no continuation token or no new videos returned

**How transcript fetching works:**
1. GET watch page → extract `INNERTUBE_API_KEY`
2. POST `/youtubei/v1/player` with `clientName: "ANDROID"` → get caption track URLs
3. GET the `baseUrl` (with `&fmt=srv3` stripped) → caption XML
4. Parse XML `<text>` elements → plain text output

---

## Maintenance

- **Binary:** `~/.local/bin/yt-transcript`
- **Source:** `~/.local/share/yt-transcript/` (we own this — fix bugs directly)
- **Version:** `0.5.1` — default workers 2, smart skip (retries `transcript_available: false`)
- **Rebuild:** `cd ~/.local/share/yt-transcript && cargo build --release && cp target/release/yt-transcript ~/.local/bin/`
- **If broken by YouTube change:** Check if client contexts still work, update `clientVersion`, or investigate page structure changes
