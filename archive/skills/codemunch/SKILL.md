---
name: codemunch
description: Symbol-level code indexing and retrieval using tree-sitter AST parsing. Indexes codebases and enables O(1) symbol lookup by name, saving up to 99% of tokens vs full-file reads. Use when asked to index code, search symbols, find functions/types/methods, get symbol source, show code outline, or explore an indexed codebase. Triggers on "index this project", "find function X", "search for symbol", "show outline", "what functions are in", or any request to efficiently browse a codebase's symbols.
---

# CodeMunch — Symbol-Level Code Retrieval

Indexes codebases using tree-sitter AST parsing and lightweight text extractors
for O(1) symbol retrieval. Instead of reading entire files, retrieve just the
function, struct, heading, or config section you need — saving up to 99% of tokens.

Source is fully local at `~/.local/share/codemunch/` — we own and maintain it.

**Tree-sitter parsed:** Rust, Python, JavaScript, TypeScript, TSX, Go
**Structured text:** Markdown (headings), JSON (keys), TOML (sections), YAML (keys), HTML (elements/ids), CSS (selectors)
**File-level indexed:** SQL, shell scripts, plain text, XML, config files, Dockerfiles, Makefiles, GraphQL, protobuf

---

## When to Use CodeMunch vs Direct File Reads

| Scenario | Use CodeMunch | Use Direct Read |
|---|---|---|
| Need one function from a large file | Yes | No |
| Exploring unfamiliar codebase | Yes (outline/search) | No |
| Need to understand project structure | Yes (tree/outline) | No |
| Editing a file you already have open | No | Yes |
| Small files (<50 lines) | No | Yes |
| Need the full file for context | No | Yes |
| Searching across many files by symbol name | Yes (search) | No |

**Rule of thumb:** If a file has >100 lines and you need <20% of it, use codemunch.

---

## Step 1 — Resolve the intent

| User intent | Command |
|---|---|
| Index a project/directory | `codemunch index <path>` |
| Get a specific symbol's source | `codemunch get <repo> <symbol-id>` |
| Search symbols by name | `codemunch search <repo> <query> [--kind K] [--lang L] [--max N]` |
| List all indexed repos | `codemunch list` |
| Show file tree of a repo | `codemunch tree <repo> [prefix]` |
| Show symbol outline | `codemunch outline <repo> [file]` |
| Clear a stale index | `codemunch invalidate <repo>` |

**Symbol ID format:**
```
{file_path}::{qualified_name}#{kind}[~N]

Examples:
  src/main.rs::Config.load#method
  src/lib.rs::parse_input#function
  src/models.rs::User#type
```

**`<repo>`** is the directory name (last component of the indexed path).

---

## Step 2 — Check for the binary

```bash
~/.local/bin/codemunch --version 2>/dev/null
```

- **Exit 0 with `codemunch 0.1.0`** → binary exists, skip to Step 4
- **Any other result** → binary missing or outdated, proceed to Step 3

---

## Step 3 — Bootstrap the binary (first run only)

Inform the user: *"Building the codemunch tool for the first time — this takes
about 2-3 minutes (tree-sitter grammars need compiling)."*

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

**`~/.local/share/codemunch/Cargo.toml`**

```toml
[package]
name = "codemunch"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "codemunch"
path = "src/main.rs"

[dependencies]
tree-sitter = "0.25"
tree-sitter-rust = "0.24"
tree-sitter-python = "0.23"
tree-sitter-javascript = "0.23"
tree-sitter-typescript = "0.23"
tree-sitter-go = "0.23"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
anyhow = "1"
sha2 = "0.10"
ignore = "0.4"
globset = "0.4"

[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
strip = true
```

**`~/.local/share/codemunch/src/main.rs`**

```rust
use anyhow::{bail, Context, Result};
use ignore::WalkBuilder;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use tree_sitter::{Language, Parser};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VERSION: &str = "codemunch 0.1.0";
const MAX_FILE_SIZE: u64 = 500_000; // 500KB
const BINARY_CHECK_SIZE: usize = 8192;

/// Extensions that are always skipped (binary/media/etc.)
const BINARY_EXTENSIONS: &[&str] = &[
    "png", "jpg", "jpeg", "gif", "bmp", "ico", "svg", "webp", "mp3", "mp4",
    "avi", "mov", "mkv", "flac", "wav", "ogg", "pdf", "zip", "tar", "gz",
    "bz2", "xz", "7z", "rar", "exe", "dll", "so", "dylib", "o", "a", "lib",
    "class", "jar", "pyc", "pyo", "wasm", "ttf", "otf", "woff", "woff2",
    "eot", "db", "sqlite", "sqlite3", "bin", "dat",
];

/// Files that may contain secrets
const SECRET_PATTERNS: &[&str] = &[
    ".env", ".env.local", ".env.production", ".env.development",
    "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa",
];

const SECRET_EXTENSIONS: &[&str] = &[
    "pem", "key", "p12", "pfx", "jks", "keystore",
];

// ---------------------------------------------------------------------------
// Data structures
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SymbolLocation {
    byte_offset: usize,
    byte_length: usize,
    line: usize,
    end_line: usize,
    content_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Symbol {
    id: String,
    name: String,
    qualified_name: String,
    kind: String,
    file_path: String,
    location: SymbolLocation,
    signature: Option<String>,
    docstring: Option<String>,
    children: Vec<String>, // child symbol IDs
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct IndexedFile {
    path: String,
    language: String,
    content_hash: String,
    size: u64,
    symbols: Vec<String>, // top-level symbol IDs
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CodeIndex {
    name: String,
    root_path: String,
    created_at: String,
    file_count: usize,
    symbol_count: usize,
    files: Vec<IndexedFile>,
    symbols: HashMap<String, Symbol>,
}

// ---------------------------------------------------------------------------
// Language support
// ---------------------------------------------------------------------------

struct LanguageSpec {
    name: &'static str,
    #[allow(dead_code)]
    extensions: &'static [&'static str],
    language_fn: fn() -> Language,
    symbol_node_types: &'static [(&'static str, &'static str)], // (node_type, kind_label)
    docstring_node: Option<&'static str>,
}

fn rust_language() -> Language {
    tree_sitter_rust::LANGUAGE.into()
}

fn python_language() -> Language {
    tree_sitter_python::LANGUAGE.into()
}

fn javascript_language() -> Language {
    tree_sitter_javascript::LANGUAGE.into()
}

fn typescript_language() -> Language {
    tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into()
}

fn tsx_language() -> Language {
    tree_sitter_typescript::LANGUAGE_TSX.into()
}

fn go_language() -> Language {
    tree_sitter_go::LANGUAGE.into()
}

fn language_specs() -> Vec<LanguageSpec> {
    vec![
        LanguageSpec {
            name: "rust",
            extensions: &["rs"],
            language_fn: rust_language,
            symbol_node_types: &[
                ("function_item", "function"),
                ("struct_item", "type"),
                ("enum_item", "type"),
                ("trait_item", "type"),
                ("impl_item", "impl"),
                ("const_item", "constant"),
                ("static_item", "constant"),
                ("type_item", "type"),
                ("mod_item", "module"),
                ("macro_definition", "macro"),
            ],
            docstring_node: Some("line_comment"),
        },
        LanguageSpec {
            name: "python",
            extensions: &["py"],
            language_fn: python_language,
            symbol_node_types: &[
                ("function_definition", "function"),
                ("class_definition", "type"),
                ("decorated_definition", "decorated"),
            ],
            docstring_node: Some("expression_statement"),
        },
        LanguageSpec {
            name: "javascript",
            extensions: &["js", "mjs", "cjs"],
            language_fn: javascript_language,
            symbol_node_types: &[
                ("function_declaration", "function"),
                ("class_declaration", "type"),
                ("method_definition", "method"),
                ("lexical_declaration", "constant"),
                ("variable_declaration", "constant"),
                ("export_statement", "export"),
            ],
            docstring_node: Some("comment"),
        },
        LanguageSpec {
            name: "typescript",
            extensions: &["ts"],
            language_fn: typescript_language,
            symbol_node_types: &[
                ("function_declaration", "function"),
                ("class_declaration", "type"),
                ("method_definition", "method"),
                ("interface_declaration", "type"),
                ("type_alias_declaration", "type"),
                ("enum_declaration", "type"),
                ("lexical_declaration", "constant"),
                ("variable_declaration", "constant"),
                ("export_statement", "export"),
            ],
            docstring_node: Some("comment"),
        },
        LanguageSpec {
            name: "tsx",
            extensions: &["tsx"],
            language_fn: tsx_language,
            symbol_node_types: &[
                ("function_declaration", "function"),
                ("class_declaration", "type"),
                ("method_definition", "method"),
                ("interface_declaration", "type"),
                ("type_alias_declaration", "type"),
                ("enum_declaration", "type"),
                ("lexical_declaration", "constant"),
                ("variable_declaration", "constant"),
                ("export_statement", "export"),
            ],
            docstring_node: Some("comment"),
        },
        LanguageSpec {
            name: "go",
            extensions: &["go"],
            language_fn: go_language,
            symbol_node_types: &[
                ("function_declaration", "function"),
                ("method_declaration", "method"),
                ("type_declaration", "type"),
                ("const_declaration", "constant"),
                ("var_declaration", "constant"),
            ],
            docstring_node: Some("comment"),
        },
    ]
}

fn detect_language(path: &Path) -> Option<&'static str> {
    let ext = path.extension().and_then(|e| e.to_str());
    let file_name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");

    // Check by extension first
    if let Some(ext) = ext {
        match ext {
            // Tree-sitter parsed languages
            "rs" => return Some("rust"),
            "py" => return Some("python"),
            "js" | "mjs" | "cjs" => return Some("javascript"),
            "ts" => return Some("typescript"),
            "tsx" => return Some("tsx"),
            "go" => return Some("go"),
            // Structured text formats (lightweight extractors)
            "md" | "mdx" => return Some("markdown"),
            "json" | "jsonc" | "json5" => return Some("json"),
            "toml" => return Some("toml"),
            "yaml" | "yml" => return Some("yaml"),
            "html" | "htm" => return Some("html"),
            "css" | "scss" | "less" => return Some("css"),
            // Plain text files (file-level indexing)
            "txt" | "text" => return Some("text"),
            "sh" | "bash" | "zsh" | "fish" => return Some("shell"),
            "sql" => return Some("sql"),
            "xml" | "xsl" | "xslt" => return Some("xml"),
            "svg" => return Some("svg"),
            "cfg" | "ini" | "conf" => return Some("config"),
            "dockerfile" => return Some("dockerfile"),
            "graphql" | "gql" => return Some("graphql"),
            "proto" => return Some("proto"),
            "lock" => return None, // skip generated lock files
            _ => {}
        }
    }

    // Check by filename (no extension or special names)
    match file_name {
        "Dockerfile" | "Containerfile" => Some("dockerfile"),
        "Makefile" | "makefile" | "GNUmakefile" => Some("makefile"),
        "Justfile" | "justfile" => Some("makefile"),
        ".gitignore" | ".dockerignore" | ".prettierignore" | ".eslintignore" => Some("config"),
        ".editorconfig" => Some("config"),
        "LICENSE" | "LICENCE" | "COPYING" => Some("text"),
        _ => None,
    }
}

fn get_spec(lang: &str) -> Option<LanguageSpec> {
    language_specs().into_iter().find(|s| s.name == lang)
}

// ---------------------------------------------------------------------------
// Security filtering
// ---------------------------------------------------------------------------

fn is_path_traversal(path: &Path, root: &Path) -> bool {
    match (path.canonicalize(), root.canonicalize()) {
        (Ok(p), Ok(r)) => !p.starts_with(&r),
        _ => true, // if we can't resolve, reject
    }
}

fn is_symlink_escape(path: &Path, root: &Path) -> bool {
    if let Ok(meta) = fs::symlink_metadata(path) {
        if meta.file_type().is_symlink() {
            if let Ok(target) = fs::read_link(path) {
                let resolved = if target.is_absolute() {
                    target
                } else {
                    path.parent().unwrap_or(path).join(&target)
                };
                if let (Ok(res), Ok(r)) = (resolved.canonicalize(), root.canonicalize()) {
                    return !res.starts_with(&r);
                }
                return true;
            }
        }
    }
    false
}

fn is_secret_file(path: &Path) -> bool {
    let file_name = path.file_name().and_then(|f| f.to_str()).unwrap_or("");
    if SECRET_PATTERNS.iter().any(|p| file_name == *p) {
        return true;
    }
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        if SECRET_EXTENSIONS.iter().any(|e| ext == *e) {
            return true;
        }
    }
    false
}

fn is_binary_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|ext| BINARY_EXTENSIONS.iter().any(|b| ext.eq_ignore_ascii_case(b)))
        .unwrap_or(false)
}

fn is_binary_content(path: &Path) -> bool {
    let Ok(mut file) = fs::File::open(path) else {
        return true;
    };
    let mut buf = vec![0u8; BINARY_CHECK_SIZE];
    let Ok(n) = file.read(&mut buf) else {
        return true;
    };
    buf[..n].contains(&0)
}

fn exceeds_size_limit(path: &Path) -> bool {
    fs::metadata(path)
        .map(|m| m.len() > MAX_FILE_SIZE)
        .unwrap_or(true)
}

fn is_valid_utf8_file(path: &Path) -> bool {
    fs::read_to_string(path).is_ok()
}

/// Returns true if file passes all 7 security checks.
fn passes_security_filter(path: &Path, root: &Path) -> bool {
    !is_path_traversal(path, root)
        && !is_symlink_escape(path, root)
        && !is_secret_file(path)
        && !is_binary_extension(path)
        && !exceeds_size_limit(path)
        && !is_binary_content(path)
        && is_valid_utf8_file(path)
}

// ---------------------------------------------------------------------------
// File discovery
// ---------------------------------------------------------------------------

/// Directories that are always skipped regardless of .gitignore
const SKIP_DIRS: &[&str] = &[
    "target", "node_modules", ".git", "__pycache__", ".venv", "venv",
    "dist", "build", ".next", ".nuxt", "vendor", ".cache",
];

fn should_skip_dir(name: &str) -> bool {
    SKIP_DIRS.iter().any(|d| name == *d)
}

fn discover_files(root: &Path) -> Result<Vec<(PathBuf, String)>> {
    let mut files = Vec::new();
    let walker = WalkBuilder::new(root)
        .hidden(true) // respect hidden files
        .git_ignore(true)
        .git_global(true)
        .git_exclude(true)
        .filter_entry(|entry| {
            if entry.file_type().map_or(false, |ft| ft.is_dir()) {
                if let Some(name) = entry.file_name().to_str() {
                    return !should_skip_dir(name);
                }
            }
            true
        })
        .build();

    for entry in walker {
        let entry = entry?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if let Some(lang) = detect_language(path) {
            if passes_security_filter(path, root) {
                files.push((path.to_path_buf(), lang.to_string()));
            }
        }
    }
    Ok(files)
}

// ---------------------------------------------------------------------------
// Tree-sitter parsing
// ---------------------------------------------------------------------------

struct ExtractedSymbol {
    name: String,
    qualified_name: String,
    kind: String,
    byte_offset: usize,
    byte_length: usize,
    line: usize,
    end_line: usize,
    signature: Option<String>,
    docstring: Option<String>,
    children: Vec<ExtractedSymbol>,
}

fn extract_symbols(source: &[u8], spec: &LanguageSpec) -> Result<Vec<ExtractedSymbol>> {
    let mut parser = Parser::new();
    let language = (spec.language_fn)();
    parser
        .set_language(&language)
        .context("Failed to set tree-sitter language")?;

    let tree = parser
        .parse(source, None)
        .context("Failed to parse source")?;

    let root = tree.root_node();
    let source_str = std::str::from_utf8(source).unwrap_or("");
    let mut symbols = Vec::new();

    extract_from_node(root, source, source_str, spec, "", &mut symbols);
    Ok(symbols)
}

fn extract_from_node(
    node: tree_sitter::Node,
    source: &[u8],
    source_str: &str,
    spec: &LanguageSpec,
    parent_name: &str,
    symbols: &mut Vec<ExtractedSymbol>,
) {
    let node_type = node.kind();

    // Check if this node is a symbol we want to extract
    if let Some(kind_label) = spec
        .symbol_node_types
        .iter()
        .find(|(nt, _)| *nt == node_type)
        .map(|(_, k)| *k)
    {
        // Handle special cases
        let (effective_kind, inner_node): (&str, tree_sitter::Node) = match node_type {
            // For decorated definitions (Python), unwrap to the inner definition
            "decorated_definition" => {
                if let Some(inner) = find_child_by_types(
                    node,
                    &["function_definition", "class_definition"],
                ) {
                    let inner_kind = match inner.kind() {
                        "function_definition" => "function",
                        "class_definition" => "type",
                        _ => kind_label,
                    };
                    (inner_kind, inner)
                } else {
                    return; // skip if no inner definition
                }
            }
            // For export statements (JS/TS), unwrap to inner declaration
            "export_statement" => {
                if let Some(inner) = find_child_by_types(
                    node,
                    &[
                        "function_declaration",
                        "class_declaration",
                        "lexical_declaration",
                        "variable_declaration",
                        "interface_declaration",
                        "type_alias_declaration",
                        "enum_declaration",
                    ],
                ) {
                    let inner_kind = match inner.kind() {
                        "function_declaration" => "function",
                        "class_declaration" => "type",
                        "interface_declaration" => "type",
                        "type_alias_declaration" => "type",
                        "enum_declaration" => "type",
                        _ => "constant",
                    };
                    (inner_kind, inner)
                } else {
                    // export default or re-export — skip
                    return;
                }
            }
            _ => (kind_label, node),
        };

        let name = extract_name(inner_node, source_str, spec.name);

        if !name.is_empty() && name != "_" {
            let qualified = if parent_name.is_empty() {
                name.clone()
            } else {
                format!("{}.{}", parent_name, name)
            };

            // Use the outer node's full range for byte offset/length
            let byte_offset = node.start_byte();
            let byte_length = node.end_byte() - node.start_byte();
            let line = node.start_position().row + 1;
            let end_line = node.end_position().row + 1;

            let signature = extract_signature(inner_node, source_str, spec.name);
            let docstring = extract_docstring(node, source_str, spec);

            // Extract children from body nodes (methods within class/impl/struct/etc.)
            let mut children = Vec::new();
            let child_parent = &qualified;
            let body_types = &["block", "class_body", "declaration_list", "field_declaration_list"];
            if let Some(body) = find_child_by_types(inner_node, body_types) {
                for i in 0..body.child_count() {
                    if let Some(child) = body.child(i) {
                        extract_from_node(child, source, source_str, spec, child_parent, &mut children);
                    }
                }
            }

            symbols.push(ExtractedSymbol {
                name,
                qualified_name: qualified,
                kind: effective_kind.to_string(),
                byte_offset,
                byte_length,
                line,
                end_line,
                signature,
                docstring,
                children,
            });
            return; // don't recurse further from here (children already handled)
        }
    }

    // For impl blocks in Rust, we want to capture the type name as parent
    if node_type == "impl_item" && spec.name == "rust" {
        let impl_name = extract_impl_type_name(node, source_str);
        if !impl_name.is_empty() {
            let byte_offset = node.start_byte();
            let byte_length = node.end_byte() - node.start_byte();
            let line = node.start_position().row + 1;
            let end_line = node.end_position().row + 1;

            let signature = extract_impl_signature(node, source_str);

            let mut children = Vec::new();
            if let Some(body) = find_child_by_types(node, &["declaration_list"]) {
                for i in 0..body.child_count() {
                    if let Some(child) = body.child(i) {
                        extract_from_node(child, source, source_str, spec, &impl_name, &mut children);
                    }
                }
            }

            symbols.push(ExtractedSymbol {
                name: impl_name.clone(),
                qualified_name: impl_name,
                kind: "impl".to_string(),
                byte_offset,
                byte_length,
                line,
                end_line,
                signature,
                docstring: None,
                children,
            });
            return;
        }
    }

    // Recurse into children for non-symbol nodes
    for i in 0..node.child_count() {
        if let Some(child) = node.child(i) {
            extract_from_node(child, source, source_str, spec, parent_name, symbols);
        }
    }
}

fn find_child_by_types<'a>(node: tree_sitter::Node<'a>, types: &[&str]) -> Option<tree_sitter::Node<'a>> {
    for i in 0..node.child_count() {
        if let Some(child) = node.child(i) {
            if types.contains(&child.kind()) {
                return Some(child);
            }
        }
    }
    None
}

fn extract_name(node: tree_sitter::Node, source: &str, lang: &str) -> String {
    // Try common name field types
    let name_fields = ["name", "identifier"];
    for field in &name_fields {
        if let Some(name_node) = node.child_by_field_name(field) {
            return node_text(name_node, source).to_string();
        }
    }

    // Language-specific fallbacks
    match lang {
        "go" => {
            // Go type_spec within type_declaration
            if node.kind() == "type_declaration" {
                for i in 0..node.child_count() {
                    if let Some(child) = node.child(i) {
                        if child.kind() == "type_spec" {
                            if let Some(name_node) = child.child_by_field_name("name") {
                                return node_text(name_node, source).to_string();
                            }
                        }
                    }
                }
            }
        }
        "javascript" | "typescript" | "tsx" => {
            // const/let declarations: extract the variable name
            if node.kind() == "lexical_declaration" || node.kind() == "variable_declaration" {
                for i in 0..node.child_count() {
                    if let Some(child) = node.child(i) {
                        if child.kind() == "variable_declarator" {
                            if let Some(name_node) = child.child_by_field_name("name") {
                                return node_text(name_node, source).to_string();
                            }
                        }
                    }
                }
            }
        }
        _ => {}
    }

    // Last resort: find first identifier child
    for i in 0..node.child_count() {
        if let Some(child) = node.child(i) {
            if child.kind() == "identifier" || child.kind() == "type_identifier" {
                return node_text(child, source).to_string();
            }
        }
    }

    String::new()
}

fn extract_impl_type_name(node: tree_sitter::Node, source: &str) -> String {
    // impl [Trait for] Type { ... }
    if let Some(type_node) = node.child_by_field_name("type") {
        return node_text(type_node, source).to_string();
    }
    // Fallback: look for type_identifier child
    for i in 0..node.child_count() {
        if let Some(child) = node.child(i) {
            if child.kind() == "type_identifier" || child.kind() == "generic_type" {
                return node_text(child, source).to_string();
            }
        }
    }
    String::new()
}

fn extract_impl_signature(node: tree_sitter::Node, source: &str) -> Option<String> {
    // Get everything before the declaration_list (the { ... })
    let start = node.start_byte();
    if let Some(body) = find_child_by_types(node, &["declaration_list"]) {
        let end = body.start_byte();
        let sig = &source[start..end];
        Some(sig.trim().to_string())
    } else {
        Some(node_text(node, source).lines().next()?.to_string())
    }
}

fn extract_signature(node: tree_sitter::Node, source: &str, lang: &str) -> Option<String> {
    match lang {
        "rust" => {
            // For functions: everything before the block
            if let Some(body) = find_child_by_types(node, &["block"]) {
                let sig = &source[node.start_byte()..body.start_byte()];
                return Some(sig.trim().to_string());
            }
            // For structs/enums: first line
            let text = node_text(node, source);
            Some(text.lines().next()?.to_string())
        }
        "python" => {
            // def name(params) -> type:
            if let Some(params) = node.child_by_field_name("parameters") {
                let name = extract_name(node, source, lang);
                let params_text = node_text(params, source);
                let ret = node
                    .child_by_field_name("return_type")
                    .map(|n| format!(" -> {}", node_text(n, source)))
                    .unwrap_or_default();
                return Some(format!("def {}{}{}", name, params_text, ret));
            }
            let text = node_text(node, source);
            Some(text.lines().next()?.to_string())
        }
        "go" => {
            if let Some(body) = find_child_by_types(node, &["block"]) {
                let sig = &source[node.start_byte()..body.start_byte()];
                return Some(sig.trim().to_string());
            }
            let text = node_text(node, source);
            Some(text.lines().next()?.to_string())
        }
        _ => {
            // JS/TS: first line or up to body
            if let Some(body) = find_child_by_types(node, &["statement_block", "class_body"]) {
                let sig = &source[node.start_byte()..body.start_byte()];
                return Some(sig.trim().to_string());
            }
            let text = node_text(node, source);
            Some(text.lines().next()?.to_string())
        }
    }
}

fn extract_docstring(node: tree_sitter::Node, source: &str, spec: &LanguageSpec) -> Option<String> {
    let _doc_node_type = spec.docstring_node?;

    match spec.name {
        "rust" => {
            // Collect /// comments immediately before the node
            let mut comments = Vec::new();
            let mut sibling = node.prev_sibling();
            while let Some(s) = sibling {
                let text = node_text(s, source).trim().to_string();
                if s.kind() == "line_comment" && (text.starts_with("///") || text.starts_with("//!")) {
                    comments.push(
                        text.trim_start_matches("///")
                            .trim_start_matches("//!")
                            .trim()
                            .to_string(),
                    );
                    sibling = s.prev_sibling();
                } else if s.kind() == "attribute_item" || s.kind() == "attribute" {
                    // Skip attributes like #[derive(...)]
                    sibling = s.prev_sibling();
                } else {
                    break;
                }
            }
            if comments.is_empty() {
                return None;
            }
            comments.reverse();
            Some(comments.join("\n"))
        }
        "python" => {
            // First expression_statement in body that's a string
            if let Some(body) = find_child_by_types(node, &["block"]) {
                if let Some(first) = body.child(0) {
                    if first.kind() == "expression_statement" {
                        if let Some(string_node) = first.child(0) {
                            if string_node.kind() == "string" || string_node.kind() == "concatenated_string" {
                                let text = node_text(string_node, source);
                                return Some(
                                    text.trim_matches('"')
                                        .trim_matches('\'')
                                        .trim()
                                        .to_string(),
                                );
                            }
                        }
                    }
                }
            }
            None
        }
        _ => {
            // JS/TS/Go: preceding block comment
            let mut sibling = node.prev_sibling();
            while let Some(s) = sibling {
                if s.kind() == "comment" {
                    let text = node_text(s, source).trim().to_string();
                    if text.starts_with("/*") || text.starts_with("//") {
                        return Some(
                            text.trim_start_matches("/**")
                                .trim_start_matches("/*")
                                .trim_start_matches("//")
                                .trim_end_matches("*/")
                                .trim()
                                .to_string(),
                        );
                    }
                } else {
                    break;
                }
                sibling = s.prev_sibling();
            }
            None
        }
    }
}

fn node_text<'a>(node: tree_sitter::Node, source: &'a str) -> &'a str {
    &source[node.start_byte()..node.end_byte()]
}

// ---------------------------------------------------------------------------
// Lightweight text-based extractors (no tree-sitter)
// ---------------------------------------------------------------------------

fn extract_text_symbols(source: &str, lang: &str) -> Vec<ExtractedSymbol> {
    match lang {
        "markdown" => extract_markdown_symbols(source),
        "json" => extract_json_symbols(source),
        "toml" => extract_toml_symbols(source),
        "yaml" => extract_yaml_symbols(source),
        "html" => extract_html_symbols(source),
        "css" => extract_css_symbols(source),
        _ => extract_whole_file_symbol(source, lang),
    }
}

/// Extract headings from markdown as a flat symbol list
fn extract_markdown_symbols(source: &str) -> Vec<ExtractedSymbol> {
    let mut symbols = Vec::new();
    let mut byte_pos = 0;

    for (line_num, line) in source.lines().enumerate() {
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') {
            let level = trimmed.chars().take_while(|c| *c == '#').count();
            let heading = trimmed[level..].trim().trim_start_matches(' ');
            if !heading.is_empty() && level <= 6 {
                let kind = format!("h{}", level);
                let byte_end = byte_pos + line.len();
                symbols.push(ExtractedSymbol {
                    name: heading.to_string(),
                    qualified_name: heading.to_string(),
                    kind,
                    byte_offset: byte_pos,
                    byte_length: line.len(),
                    line: line_num + 1,
                    end_line: line_num + 1,
                    signature: Some(line.trim().to_string()),
                    docstring: None,
                    children: Vec::new(),
                });
                // Find the content block under this heading (until next heading of same or higher level)
                let heading_byte_start = byte_pos;
                let mut content_end_byte = source.len();
                let mut content_end_line = source.lines().count();
                let mut scan_byte = byte_end;
                if scan_byte < source.len() {
                    scan_byte += 1; // skip newline
                }
                for (scan_line_num, scan_line) in source.lines().enumerate().skip(line_num + 1) {
                    let scan_trimmed = scan_line.trim_start();
                    if scan_trimmed.starts_with('#') {
                        let scan_level = scan_trimmed.chars().take_while(|c| *c == '#').count();
                        if scan_level <= level {
                            content_end_byte = scan_byte;
                            content_end_line = scan_line_num;
                            break;
                        }
                    }
                    scan_byte += scan_line.len() + 1; // +1 for newline
                }
                // Update the symbol to span the full section
                if let Some(sym) = symbols.last_mut() {
                    sym.byte_length = content_end_byte.saturating_sub(heading_byte_start);
                    sym.end_line = content_end_line;
                }
            }
        }
        byte_pos += line.len() + 1; // +1 for newline
    }

    if symbols.is_empty() {
        return extract_whole_file_symbol(source, "markdown");
    }
    symbols
}

/// Extract top-level keys from JSON
fn extract_json_symbols(source: &str) -> Vec<ExtractedSymbol> {
    let parsed: Result<serde_json::Value, _> = serde_json::from_str(source);
    let Ok(value) = parsed else {
        return extract_whole_file_symbol(source, "json");
    };

    let mut symbols = Vec::new();
    if let Some(obj) = value.as_object() {
        for key in obj.keys() {
            // Find the key's position in the source text
            let search = format!("\"{}\"", key);
            if let Some(pos) = source.find(&search) {
                let line = source[..pos].chars().filter(|c| *c == '\n').count() + 1;
                let val = &obj[key];
                let kind = match val {
                    serde_json::Value::Object(_) => "object",
                    serde_json::Value::Array(_) => "array",
                    serde_json::Value::String(_) => "string",
                    serde_json::Value::Number(_) => "number",
                    serde_json::Value::Bool(_) => "boolean",
                    serde_json::Value::Null => "null",
                };
                let preview = match val {
                    serde_json::Value::Object(o) => format!("{{...}} ({} keys)", o.len()),
                    serde_json::Value::Array(a) => format!("[...] ({} items)", a.len()),
                    serde_json::Value::String(s) => {
                        if s.len() > 60 { format!("\"{}...\"", &s[..57]) } else { format!("\"{}\"", s) }
                    }
                    other => other.to_string(),
                };
                symbols.push(ExtractedSymbol {
                    name: key.clone(),
                    qualified_name: key.clone(),
                    kind: kind.to_string(),
                    byte_offset: pos,
                    byte_length: search.len(),
                    line,
                    end_line: line,
                    signature: Some(format!("{}: {}", key, preview)),
                    docstring: None,
                    children: Vec::new(),
                });
            }
        }
    }

    if symbols.is_empty() {
        return extract_whole_file_symbol(source, "json");
    }
    symbols
}

/// Extract [table] sections and key = value pairs from TOML
fn extract_toml_symbols(source: &str) -> Vec<ExtractedSymbol> {
    let mut symbols = Vec::new();
    let mut byte_pos = 0;

    for (line_num, line) in source.lines().enumerate() {
        let trimmed = line.trim();
        // [table] or [[array_table]]
        if trimmed.starts_with('[') {
            let name = trimmed.trim_matches(|c| c == '[' || c == ']').trim();
            if !name.is_empty() {
                let kind = if trimmed.starts_with("[[") { "array_table" } else { "table" };
                symbols.push(ExtractedSymbol {
                    name: name.to_string(),
                    qualified_name: name.to_string(),
                    kind: kind.to_string(),
                    byte_offset: byte_pos,
                    byte_length: line.len(),
                    line: line_num + 1,
                    end_line: line_num + 1,
                    signature: Some(trimmed.to_string()),
                    docstring: None,
                    children: Vec::new(),
                });
            }
        }
        // Top-level key = value (not indented, not comment)
        else if !trimmed.is_empty() && !trimmed.starts_with('#') {
            if let Some(eq_pos) = trimmed.find('=') {
                let key = trimmed[..eq_pos].trim();
                let val = trimmed[eq_pos + 1..].trim();
                if !key.is_empty() && symbols.is_empty() {
                    // Only capture top-level keys (before any [table])
                    symbols.push(ExtractedSymbol {
                        name: key.to_string(),
                        qualified_name: key.to_string(),
                        kind: "key".to_string(),
                        byte_offset: byte_pos,
                        byte_length: line.len(),
                        line: line_num + 1,
                        end_line: line_num + 1,
                        signature: Some(format!("{} = {}", key,
                            if val.len() > 60 { format!("{}...", &val[..57]) } else { val.to_string() }
                        )),
                        docstring: None,
                        children: Vec::new(),
                    });
                }
            }
        }
        byte_pos += line.len() + 1;
    }

    if symbols.is_empty() {
        return extract_whole_file_symbol(source, "toml");
    }
    symbols
}

/// Extract top-level keys from YAML
fn extract_yaml_symbols(source: &str) -> Vec<ExtractedSymbol> {
    let mut symbols = Vec::new();
    let mut byte_pos = 0;

    for (line_num, line) in source.lines().enumerate() {
        // Top-level key: not indented, not comment, not ---/...
        if !line.starts_with(' ') && !line.starts_with('\t')
            && !line.starts_with('#') && !line.starts_with("---") && !line.starts_with("...")
        {
            if let Some(colon_pos) = line.find(':') {
                let key = line[..colon_pos].trim();
                if !key.is_empty() && !key.starts_with('-') {
                    let val = line[colon_pos + 1..].trim();
                    let kind = if val.is_empty() { "mapping" } else { "scalar" };
                    symbols.push(ExtractedSymbol {
                        name: key.to_string(),
                        qualified_name: key.to_string(),
                        kind: kind.to_string(),
                        byte_offset: byte_pos,
                        byte_length: line.len(),
                        line: line_num + 1,
                        end_line: line_num + 1,
                        signature: Some(if val.is_empty() {
                            format!("{}:", key)
                        } else {
                            format!("{}: {}", key,
                                if val.len() > 60 { format!("{}...", &val[..57]) } else { val.to_string() }
                            )
                        }),
                        docstring: None,
                        children: Vec::new(),
                    });
                }
            }
        }
        byte_pos += line.len() + 1;
    }

    if symbols.is_empty() {
        return extract_whole_file_symbol(source, "yaml");
    }
    symbols
}

/// Extract elements with id attributes and major structural tags from HTML
fn extract_html_symbols(source: &str) -> Vec<ExtractedSymbol> {
    let mut symbols = Vec::new();
    let mut byte_pos = 0;

    for (line_num, line) in source.lines().enumerate() {
        let trimmed = line.trim();
        // Look for id="..." attributes
        if let Some(id_pos) = trimmed.find("id=\"") {
            let after = &trimmed[id_pos + 4..];
            if let Some(end) = after.find('"') {
                let id_val = &after[..end];
                if !id_val.is_empty() {
                    // Find the tag name
                    let tag = trimmed.trim_start_matches('<')
                        .split(|c: char| c.is_whitespace() || c == '>')
                        .next()
                        .unwrap_or("element");
                    symbols.push(ExtractedSymbol {
                        name: id_val.to_string(),
                        qualified_name: format!("{}#{}", tag, id_val),
                        kind: "element".to_string(),
                        byte_offset: byte_pos,
                        byte_length: line.len(),
                        line: line_num + 1,
                        end_line: line_num + 1,
                        signature: Some(format!("<{} id=\"{}\">", tag, id_val)),
                        docstring: None,
                        children: Vec::new(),
                    });
                }
            }
        }
        // Also capture <script>, <style>, <template> blocks
        for tag in &["script", "style", "template", "head", "body", "main", "nav", "footer", "header"] {
            let open = format!("<{}", tag);
            if trimmed.starts_with(&open) && (trimmed.len() == open.len() || !trimmed.as_bytes()[open.len()].is_ascii_alphanumeric()) {
                symbols.push(ExtractedSymbol {
                    name: tag.to_string(),
                    qualified_name: tag.to_string(),
                    kind: "element".to_string(),
                    byte_offset: byte_pos,
                    byte_length: line.len(),
                    line: line_num + 1,
                    end_line: line_num + 1,
                    signature: Some(trimmed.chars().take(80).collect()),
                    docstring: None,
                    children: Vec::new(),
                });
                break; // one match per line
            }
        }
        byte_pos += line.len() + 1;
    }

    if symbols.is_empty() {
        return extract_whole_file_symbol(source, "html");
    }
    symbols
}

/// Extract selectors from CSS
fn extract_css_symbols(source: &str) -> Vec<ExtractedSymbol> {
    let mut symbols = Vec::new();
    let mut byte_pos = 0;
    let mut in_block = 0i32;

    for (line_num, line) in source.lines().enumerate() {
        let trimmed = line.trim();
        // Track brace depth
        for ch in trimmed.chars() {
            match ch {
                '{' => in_block += 1,
                '}' => in_block -= 1,
                _ => {}
            }
        }
        // A selector is a non-empty line at depth 0 that doesn't start with } or @ or /
        if in_block <= 1 && !trimmed.is_empty()
            && !trimmed.starts_with('}') && !trimmed.starts_with('/')
            && !trimmed.starts_with('*')
        {
            if trimmed.contains('{') || trimmed.ends_with(',') {
                let selector = trimmed.trim_end_matches('{').trim_end_matches(',').trim();
                if !selector.is_empty() {
                    let kind = if trimmed.starts_with('@') { "at-rule" } else { "selector" };
                    symbols.push(ExtractedSymbol {
                        name: selector.to_string(),
                        qualified_name: selector.to_string(),
                        kind: kind.to_string(),
                        byte_offset: byte_pos,
                        byte_length: line.len(),
                        line: line_num + 1,
                        end_line: line_num + 1,
                        signature: Some(selector.to_string()),
                        docstring: None,
                        children: Vec::new(),
                    });
                }
            }
        }
        byte_pos += line.len() + 1;
    }

    if symbols.is_empty() {
        return extract_whole_file_symbol(source, "css");
    }
    symbols
}

/// Index an entire file as a single symbol (for plain text, shell, sql, etc.)
fn extract_whole_file_symbol(source: &str, lang: &str) -> Vec<ExtractedSymbol> {
    let line_count = source.lines().count().max(1);
    vec![ExtractedSymbol {
        name: "(file)".to_string(),
        qualified_name: "(file)".to_string(),
        kind: lang.to_string(),
        byte_offset: 0,
        byte_length: source.len(),
        line: 1,
        end_line: line_count,
        signature: Some(format!("{} ({} lines)", lang, line_count)),
        docstring: None,
        children: Vec::new(),
    }]
}

// ---------------------------------------------------------------------------
// Index building
// ---------------------------------------------------------------------------

fn build_index(root: &Path) -> Result<CodeIndex> {
    let root = root
        .canonicalize()
        .context("Failed to resolve root path")?;
    let name = root
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unnamed")
        .to_string();

    eprintln!("Indexing: {}", root.display());

    let files = discover_files(&root)?;
    eprintln!("Found {} source files", files.len());

    let content_dir = index_content_dir(&name);
    fs::create_dir_all(&content_dir)?;

    let mut index = CodeIndex {
        name: name.clone(),
        root_path: root.display().to_string(),
        created_at: chrono_now(),
        file_count: 0,
        symbol_count: 0,
        files: Vec::new(),
        symbols: HashMap::new(),
    };

    for (path, lang) in &files {
        let rel_path = path
            .strip_prefix(&root)
            .unwrap_or(path)
            .to_string_lossy()
            .to_string();

        let source = match fs::read(path) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("  SKIP {}: {}", rel_path, e);
                continue;
            }
        };

        let file_hash = sha256_hex(&source);

        // Cache the source file
        let cache_path = content_dir.join(&rel_path);
        if let Some(parent) = cache_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&cache_path, &source)?;

        let extracted = if let Some(spec) = get_spec(lang) {
            // Tree-sitter parsed languages
            match extract_symbols(&source, &spec) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("  PARSE ERROR {}: {}", rel_path, e);
                    continue;
                }
            }
        } else {
            // Lightweight text-based extractors
            let source_str = match std::str::from_utf8(&source) {
                Ok(s) => s,
                Err(_) => continue,
            };
            extract_text_symbols(source_str, lang)
        };

        let mut file_symbol_ids = Vec::new();
        let mut name_counts: HashMap<String, usize> = HashMap::new();

        fn flatten_symbols(
            extracted: &[ExtractedSymbol],
            file_path: &str,
            source: &[u8],
            symbols: &mut HashMap<String, Symbol>,
            parent_ids: &mut Vec<String>,
            name_counts: &mut HashMap<String, usize>,
        ) {
            for sym in extracted {
                let base_id = format!("{}::{}#{}", file_path, sym.qualified_name, sym.kind);
                let count = name_counts.entry(base_id.clone()).or_insert(0);
                let id = if *count == 0 {
                    base_id.clone()
                } else {
                    format!("{}~{}", base_id, count)
                };
                *count += 1;

                let content = &source[sym.byte_offset..sym.byte_offset + sym.byte_length];
                let content_hash = sha256_hex(content);

                let mut child_ids = Vec::new();
                flatten_symbols(
                    &sym.children,
                    file_path,
                    source,
                    symbols,
                    &mut child_ids,
                    name_counts,
                );

                symbols.insert(
                    id.clone(),
                    Symbol {
                        id: id.clone(),
                        name: sym.name.clone(),
                        qualified_name: sym.qualified_name.clone(),
                        kind: sym.kind.clone(),
                        file_path: file_path.to_string(),
                        location: SymbolLocation {
                            byte_offset: sym.byte_offset,
                            byte_length: sym.byte_length,
                            line: sym.line,
                            end_line: sym.end_line,
                            content_hash,
                        },
                        signature: sym.signature.clone(),
                        docstring: sym.docstring.clone(),
                        children: child_ids,
                    },
                );
                parent_ids.push(id);
            }
        }

        flatten_symbols(
            &extracted,
            &rel_path,
            &source,
            &mut index.symbols,
            &mut file_symbol_ids,
            &mut name_counts,
        );

        let symbol_count = file_symbol_ids.len();
        eprintln!(
            "  {} — {} symbols ({})",
            rel_path, symbol_count, lang
        );

        index.files.push(IndexedFile {
            path: rel_path,
            language: lang.clone(),
            content_hash: file_hash,
            size: source.len() as u64,
            symbols: file_symbol_ids,
        });
    }

    index.file_count = index.files.len();
    index.symbol_count = index.symbols.len();

    eprintln!(
        "Indexed {} files, {} symbols",
        index.file_count, index.symbol_count
    );

    Ok(index)
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

fn index_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".code-index")
}

fn index_path(name: &str) -> PathBuf {
    index_dir().join(format!("{}.json", name))
}

fn index_content_dir(name: &str) -> PathBuf {
    index_dir().join(name)
}

fn save_index(index: &CodeIndex) -> Result<()> {
    let dir = index_dir();
    fs::create_dir_all(&dir)?;

    let path = index_path(&index.name);
    let tmp_path = path.with_extension("json.tmp");

    let json = serde_json::to_string_pretty(index)?;
    fs::write(&tmp_path, json)?;
    fs::rename(&tmp_path, &path)?;

    eprintln!("Saved index to {}", path.display());
    Ok(())
}

fn load_index(name: &str) -> Result<CodeIndex> {
    let path = index_path(name);
    let json = fs::read_to_string(&path)
        .with_context(|| format!("Index '{}' not found at {}", name, path.display()))?;
    let index: CodeIndex = serde_json::from_str(&json)?;
    Ok(index)
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

fn cmd_index(path: &str) -> Result<()> {
    let root = PathBuf::from(path);
    if !root.exists() {
        bail!("Path does not exist: {}", path);
    }
    if !root.is_dir() {
        bail!("Path is not a directory: {}", path);
    }
    let index = build_index(&root)?;
    save_index(&index)?;
    // Print summary to stdout
    println!(
        "{{\"name\":\"{}\",\"files\":{},\"symbols\":{}}}",
        index.name, index.file_count, index.symbol_count
    );
    Ok(())
}

fn cmd_get(repo: &str, symbol_id: &str) -> Result<()> {
    let index = load_index(repo)?;
    let symbol = index
        .symbols
        .get(symbol_id)
        .with_context(|| format!("Symbol not found: {}", symbol_id))?;

    let content_dir = index_content_dir(repo);
    let file_path = content_dir.join(&symbol.file_path);

    let mut file = fs::File::open(&file_path)
        .with_context(|| format!("Cached file not found: {}", file_path.display()))?;

    file.seek(SeekFrom::Start(symbol.location.byte_offset as u64))?;
    let mut buf = vec![0u8; symbol.location.byte_length];
    file.read_exact(&mut buf)?;

    let content = String::from_utf8(buf)?;

    // Verify hash
    let actual_hash = sha256_hex(content.as_bytes());
    if actual_hash != symbol.location.content_hash {
        eprintln!(
            "WARNING: Content hash mismatch for {} (index may be stale)",
            symbol_id
        );
    }

    // Print metadata to stderr
    eprintln!(
        "# {} ({}) — {}:{}-{}",
        symbol.qualified_name, symbol.kind, symbol.file_path, symbol.location.line, symbol.location.end_line
    );
    if let Some(sig) = &symbol.signature {
        eprintln!("# Signature: {}", sig);
    }

    // Print source to stdout
    println!("{}", content);
    Ok(())
}

fn cmd_search(repo: &str, query: &str, kind_filter: Option<&str>, lang_filter: Option<&str>, max_results: usize) -> Result<()> {
    let index = load_index(repo)?;
    let query_lower = query.to_lowercase();
    let query_parts: Vec<&str> = query_lower.split_whitespace().collect();

    let mut scored: Vec<(&Symbol, f64)> = index
        .symbols
        .values()
        .filter(|s| {
            if let Some(k) = kind_filter {
                if s.kind != k {
                    return false;
                }
            }
            if let Some(l) = lang_filter {
                let file_lang = index
                    .files
                    .iter()
                    .find(|f| f.path == s.file_path)
                    .map(|f| f.language.as_str())
                    .unwrap_or("");
                if file_lang != l {
                    return false;
                }
            }
            true
        })
        .filter_map(|s| {
            let score = score_symbol(s, &query_parts, &query_lower);
            if score > 0.0 {
                Some((s, score))
            } else {
                None
            }
        })
        .collect();

    scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(max_results);

    if scored.is_empty() {
        eprintln!("No symbols matching '{}' in {}", query, repo);
        return Ok(());
    }

    eprintln!("Found {} matches for '{}' in {}", scored.len(), query, repo);

    for (sym, score) in &scored {
        println!(
            "{}\t{}\t{}\t{}:{}-{}\t{:.2}",
            sym.id,
            sym.kind,
            sym.signature.as_deref().unwrap_or(&sym.name),
            sym.file_path,
            sym.location.line,
            sym.location.end_line,
            score
        );
    }
    Ok(())
}

fn score_symbol(symbol: &Symbol, query_parts: &[&str], query_lower: &str) -> f64 {
    let name_lower = symbol.name.to_lowercase();
    let qualified_lower = symbol.qualified_name.to_lowercase();
    let mut score = 0.0;

    // Exact name match
    if name_lower == *query_lower {
        score += 100.0;
    }
    // Name starts with query
    else if name_lower.starts_with(query_lower) {
        score += 50.0;
    }
    // Name contains query
    else if name_lower.contains(query_lower) {
        score += 30.0;
    }
    // Qualified name contains query
    else if qualified_lower.contains(query_lower) {
        score += 20.0;
    }

    // Check individual query parts (for multi-word queries)
    if query_parts.len() > 1 {
        let mut parts_matched = 0;
        for part in query_parts {
            if name_lower.contains(part) || qualified_lower.contains(part) {
                parts_matched += 1;
            }
        }
        score += (parts_matched as f64 / query_parts.len() as f64) * 15.0;
    }

    // Signature match
    if let Some(sig) = &symbol.signature {
        let sig_lower = sig.to_lowercase();
        if sig_lower.contains(query_lower) {
            score += 10.0;
        }
    }

    // Docstring match
    if let Some(doc) = &symbol.docstring {
        let doc_lower = doc.to_lowercase();
        if doc_lower.contains(query_lower) {
            score += 5.0;
        }
    }

    // Boost for "important" kinds
    match symbol.kind.as_str() {
        "function" | "method" => score *= 1.1,
        "type" => score *= 1.05,
        _ => {}
    }

    score
}

fn cmd_list() -> Result<()> {
    let dir = index_dir();
    if !dir.exists() {
        eprintln!("No indexes found (directory {} does not exist)", dir.display());
        return Ok(());
    }

    let mut entries: Vec<(String, CodeIndex)> = Vec::new();

    for entry in fs::read_dir(&dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("json") {
            if let Ok(json) = fs::read_to_string(&path) {
                if let Ok(index) = serde_json::from_str::<CodeIndex>(&json) {
                    entries.push((index.name.clone(), index));
                }
            }
        }
    }

    if entries.is_empty() {
        eprintln!("No indexes found");
        return Ok(());
    }

    entries.sort_by(|a, b| a.0.cmp(&b.0));
    for (name, index) in &entries {
        println!(
            "{}\t{}\t{} files\t{} symbols\t{}",
            name, index.root_path, index.file_count, index.symbol_count, index.created_at
        );
    }
    Ok(())
}

fn cmd_tree(repo: &str, prefix: Option<&str>) -> Result<()> {
    let index = load_index(repo)?;

    let mut paths: Vec<&str> = index.files.iter().map(|f| f.path.as_str()).collect();
    paths.sort();

    if let Some(pfx) = prefix {
        paths.retain(|p| p.starts_with(pfx));
    }

    // Build a simple tree
    let mut prev_parts: Vec<&str> = Vec::new();
    for path in &paths {
        let parts: Vec<&str> = path.split('/').collect();
        let common = prev_parts
            .iter()
            .zip(parts.iter())
            .take_while(|(a, b)| a == b)
            .count();

        for (i, part) in parts.iter().enumerate() {
            if i < common {
                continue;
            }
            let indent = "  ".repeat(i);
            let is_file = i == parts.len() - 1;
            if is_file {
                // Find symbol count for this file
                let sym_count = index
                    .files
                    .iter()
                    .find(|f| f.path == *path)
                    .map(|f| f.symbols.len())
                    .unwrap_or(0);
                println!("{}{} ({} symbols)", indent, part, sym_count);
            } else {
                println!("{}{}/", indent, part);
            }
        }
        prev_parts = parts;
    }
    Ok(())
}

fn cmd_outline(repo: &str, file_filter: Option<&str>) -> Result<()> {
    let index = load_index(repo)?;

    let mut files: Vec<&IndexedFile> = index.files.iter().collect();
    if let Some(filter) = file_filter {
        files.retain(|f| f.path.contains(filter));
    }
    files.sort_by_key(|f| &f.path);

    for file in &files {
        println!("{}:", file.path);
        print_outline_symbols(&index, &file.symbols, 1);
    }
    Ok(())
}

fn print_outline_symbols(index: &CodeIndex, symbol_ids: &[String], depth: usize) {
    for id in symbol_ids {
        if let Some(sym) = index.symbols.get(id) {
            let indent = "  ".repeat(depth);
            let sig = sym.signature.as_deref().unwrap_or(&sym.name);
            println!(
                "{}{} ({}) L{}-{}",
                indent, sig, sym.kind, sym.location.line, sym.location.end_line
            );
            if !sym.children.is_empty() {
                print_outline_symbols(index, &sym.children, depth + 1);
            }
        }
    }
}

fn cmd_invalidate(repo: &str) -> Result<()> {
    let path = index_path(repo);
    let content_dir = index_content_dir(repo);

    let mut removed = false;
    if path.exists() {
        fs::remove_file(&path)?;
        eprintln!("Removed index: {}", path.display());
        removed = true;
    }
    if content_dir.exists() {
        fs::remove_dir_all(&content_dir)?;
        eprintln!("Removed content cache: {}", content_dir.display());
        removed = true;
    }
    if !removed {
        eprintln!("No index found for '{}'", repo);
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    format!("{:x}", hasher.finalize())
}

fn chrono_now() -> String {
    // Simple ISO 8601 without chrono dependency
    let output = std::process::Command::new("date")
        .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
        .output();
    match output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        Err(_) => "unknown".to_string(),
    }
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

fn print_usage() {
    eprintln!("Usage: codemunch <command> [args...]");
    eprintln!();
    eprintln!("Commands:");
    eprintln!("  index <path>                          Index a local directory");
    eprintln!("  get <repo> <symbol-id>                Retrieve symbol source (O(1) seek)");
    eprintln!("  search <repo> <query> [--kind K] [--lang L] [--max N]");
    eprintln!("                                        Search symbols by name");
    eprintln!("  list                                  List all indexed repos");
    eprintln!("  tree <repo> [prefix]                  Show file tree");
    eprintln!("  outline <repo> [file]                 Symbol hierarchy (no source)");
    eprintln!("  invalidate <repo>                     Clear cached index");
    eprintln!("  --version                             Version check");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 || args[1] == "--help" || args[1] == "-h" {
        print_usage();
        std::process::exit(if args.len() < 2 { 1 } else { 0 });
    }

    if args[1] == "--version" || args[1] == "-V" {
        println!("{}", VERSION);
        return;
    }

    let result = match args[1].as_str() {
        "index" => {
            if args.len() < 3 {
                eprintln!("Usage: codemunch index <path>");
                std::process::exit(1);
            }
            cmd_index(&args[2])
        }
        "get" => {
            if args.len() < 4 {
                eprintln!("Usage: codemunch get <repo> <symbol-id>");
                std::process::exit(1);
            }
            cmd_get(&args[2], &args[3])
        }
        "search" => {
            if args.len() < 4 {
                eprintln!("Usage: codemunch search <repo> <query> [--kind K] [--lang L] [--max N]");
                std::process::exit(1);
            }
            let repo = &args[2];
            let query = &args[3];
            let mut kind_filter = None;
            let mut lang_filter = None;
            let mut max_results = 20;
            let mut i = 4;
            while i < args.len() {
                match args[i].as_str() {
                    "--kind" => {
                        i += 1;
                        kind_filter = args.get(i).map(|s| s.as_str());
                    }
                    "--lang" => {
                        i += 1;
                        lang_filter = args.get(i).map(|s| s.as_str());
                    }
                    "--max" => {
                        i += 1;
                        if let Some(n) = args.get(i).and_then(|s| s.parse().ok()) {
                            max_results = n;
                        }
                    }
                    _ => {}
                }
                i += 1;
            }
            cmd_search(repo, query, kind_filter, lang_filter, max_results)
        }
        "list" => cmd_list(),
        "tree" => {
            if args.len() < 3 {
                eprintln!("Usage: codemunch tree <repo> [prefix]");
                std::process::exit(1);
            }
            cmd_tree(&args[2], args.get(3).map(|s| s.as_str()))
        }
        "outline" => {
            if args.len() < 3 {
                eprintln!("Usage: codemunch outline <repo> [file]");
                std::process::exit(1);
            }
            cmd_outline(&args[2], args.get(3).map(|s| s.as_str()))
        }
        "invalidate" => {
            if args.len() < 3 {
                eprintln!("Usage: codemunch invalidate <repo>");
                std::process::exit(1);
            }
            cmd_invalidate(&args[2])
        }
        other => {
            eprintln!("Unknown command: {}", other);
            print_usage();
            std::process::exit(1);
        }
    };

    if let Err(e) = result {
        eprintln!("Error: {:?}", e);
        std::process::exit(1);
    }
}
```

### 3c. Compile and install

```bash
mkdir -p ~/.local/bin
cd ~/.local/share/codemunch
cargo build --release 2>&1
cp target/release/codemunch ~/.local/bin/codemunch
chmod +x ~/.local/bin/codemunch
```

If `cargo build` fails, show the error to the user and investigate. We own this
code — fix bugs directly in the source.

---

## Step 4 — Execute the command

### Index a project

```bash
~/.local/bin/codemunch index /path/to/project
```

stdout: JSON summary `{"name":"...","files":N,"symbols":N}`. stderr: progress.

The repo name is the directory basename. Index is stored at `~/.code-index/{name}.json`.

### Get a symbol

```bash
~/.local/bin/codemunch get <repo-name> '<symbol-id>'
```

**Always quote the symbol ID** — it contains `::` and `#` characters.

stdout: symbol source code. stderr: metadata (qualified name, kind, file, lines, signature).

### Search symbols

```bash
~/.local/bin/codemunch search <repo-name> "<query>" [--kind function] [--lang rust] [--max 10]
```

stdout: TSV results (symbol_id, kind, signature, file:lines, score). stderr: count.

### List indexed repos

```bash
~/.local/bin/codemunch list
```

### Show file tree

```bash
~/.local/bin/codemunch tree <repo-name> [path-prefix]
```

### Show outline

```bash
~/.local/bin/codemunch outline <repo-name> [file-filter]
```

### Clear stale index

```bash
~/.local/bin/codemunch invalidate <repo-name>
```

---

## Step 5 — Handle errors

| Error message contains | Cause | Response |
|---|---|---|
| `Index 'X' not found` | Not indexed yet | Run `codemunch index <path>` first |
| `Symbol not found` | Bad symbol ID | Run `search` to find correct ID |
| `Content hash mismatch` | Source changed since indexing | Run `invalidate` then `index` again |
| `Failed to set tree-sitter language` | Grammar version mismatch | Rebuild: `cd ~/.local/share/codemunch && cargo build --release` |
| `Path does not exist` | Bad path | Verify the path |
| `Cached file not found` | Content cache missing | Run `invalidate` then `index` again |

---

## Step 6 — Deliver results

**For `get` results:** Present the retrieved symbol source directly. If the user
needs context around it, use `outline` to show neighboring symbols or use
direct file reads for the surrounding area.

**For `search` results:** Present the ranked list. Offer to retrieve specific
symbols with `get`. Use the symbol IDs from search output directly.

**For `outline` results:** Use as a table of contents. Help the user navigate
to the symbols they need. Combine with `get` for a read-outline-then-drill-down
workflow.

**Typical workflow:**
1. `codemunch index /path/to/project` (first time only)
2. `codemunch outline <repo>` or `codemunch search <repo> "query"` to explore
3. `codemunch get <repo> '<symbol-id>'` to retrieve specific symbols
4. If source has changed: `codemunch invalidate <repo>` then `codemunch index` again

---

## Architecture Notes

**How indexing works:**
1. Walk directory tree using `ignore` crate (respects .gitignore, skips target/, node_modules/, etc.)
2. Apply 7-layer security filter (path traversal, symlinks, secrets, binary, size, null bytes, UTF-8)
3. Parse each source file with tree-sitter, extracting symbol AST nodes
4. Record byte offset + length for each symbol (enables O(1) seek on retrieval)
5. Cache raw source files under `~/.code-index/{name}/`
6. Save index with symbol metadata to `~/.code-index/{name}.json`

**How retrieval works:**
1. Load index JSON
2. Look up symbol by ID (HashMap O(1))
3. Open cached source file, seek to byte_offset, read byte_length bytes
4. Verify SHA-256 hash matches (warns if stale)
5. Return symbol source to stdout

**Security:** Files containing secrets (.env, *.pem, *.key), binary files, symlinks
escaping the project root, and files >500KB are all automatically excluded.

---

## Maintenance

- **Binary:** `~/.local/bin/codemunch`
- **Source:** `~/.local/share/codemunch/` (we own this — fix bugs directly)
- **Index data:** `~/.code-index/`
- **Rebuild:** `cd ~/.local/share/codemunch && cargo build --release && cp target/release/codemunch ~/.local/bin/`
