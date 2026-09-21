# Rust Patterns & Anti-Patterns

Extensible reference for code review. Add new patterns as discovered.

---

## Clone Anti-Patterns

### Unnecessary Clone in Loop

**Anti-pattern:**
```rust
for item in items {
    let name = item.name.clone();
    process(&name);
}
```

**Pattern:**
```rust
for item in &items {
    process(&item.name);
}
```

### Clone to Satisfy Borrow Checker

**Anti-pattern:**
```rust
let data = self.data.clone();
self.process(&data);
```

**Pattern:** The conflict exists because `process(&mut self)` claims the whole struct while `self.data` is borrowed. Fix the signature first — see *Signature Contracts* below and SKILL.md §14:
```rust
// Best: process only claims what it touches, so the field borrow is disjoint
fn process(cfg: &Config, data: &Data) { ... }
Self::process(&self.config, &self.data);

// Or: destructure once — disjoint field borrows are legal within one body
let Self { data, config, .. } = self;
Self::process(config, data);

// Last resort: take the field out and put it back. Cheap, but the struct is
// transiently in a default state — a panic mid-`process` leaves it that way.
let data = std::mem::take(&mut self.data);
self.process(&data);
self.data = data;
```

**Why:** `.clone()` here buys a compile pass with a heap allocation on every call. `mem::take` avoids the allocation but leaves a hole in the struct during the call. Both are workarounds for a signature that over-claims.

### Clone in Map/Filter

**Anti-pattern:**
```rust
items.iter().map(|x| x.clone()).collect()
```

**Pattern:**
```rust
items.iter().cloned().collect()
// Or if consuming:
items.into_iter().collect()
```

### to_string() on &str literals

**Anti-pattern:**
```rust
let s = "hello".to_string();
HashMap::from([("key".to_string(), value)])
```

**Pattern:**
```rust
let s = String::from("hello");  // Explicit
// Or use Cow<str> / &'static str where possible
```

---

## Error Handling Patterns

### Unwrap in Library Code

**Anti-pattern:**
```rust
fn parse_config(s: &str) -> Config {
    serde_json::from_str(s).unwrap()
}
```

**Pattern:**
```rust
fn parse_config(s: &str) -> Result<Config, serde_json::Error> {
    serde_json::from_str(s)
}
```

### Nested Result Handling

**Anti-pattern:**
```rust
match outer() {
    Ok(x) => match inner(x) {
        Ok(y) => Ok(y),
        Err(e) => Err(e),
    },
    Err(e) => Err(e),
}
```

**Pattern:**
```rust
let x = outer()?;
inner(x)
```

### Expect Without Context

**Anti-pattern:**
```rust
file.read_to_string(&mut buf).expect("read failed");
```

**Pattern:**
```rust
file.read_to_string(&mut buf)
    .expect("failed to read config file at {path}");
// Or better: propagate with context
```

---

## Option Handling Patterns

### Match on Option for Single Case

**Anti-pattern:**
```rust
match opt {
    Some(x) => do_something(x),
    None => (),
}
```

**Pattern:**
```rust
if let Some(x) = opt {
    do_something(x);
}
```

### Unwrap or Default

**Anti-pattern:**
```rust
match opt {
    Some(x) => x,
    None => Default::default(),
}
```

**Pattern:**
```rust
opt.unwrap_or_default()
```

### Map + Unwrap

**Anti-pattern:**
```rust
opt.map(|x| x.value).unwrap_or(0)
```

**Pattern:**
```rust
opt.map_or(0, |x| x.value)
```

### Verbose Boolean Env Var Check

**Anti-pattern:**
```rust
let enabled = env
    .var("FEATURE_ENABLED")
    .map(|v| v.to_string().to_lowercase() == "true")
    .unwrap_or(false);
```

**Pattern:**
```rust
let enabled = env.var("FEATURE_ENABLED")
    .map_or(false, |v| v.to_string().eq_ignore_ascii_case("true"));
```

**Why:** `map_or` combines map and unwrap_or into a single, more idiomatic call. Also use `eq_ignore_ascii_case` for clearer intent than `to_lowercase() == "true"`.

---

## Iterator Patterns

### Manual Loop with Push

**Anti-pattern:**
```rust
let mut result = Vec::new();
for item in items {
    if item.valid {
        result.push(item.transform());
    }
}
```

**Pattern:**
```rust
let result: Vec<_> = items
    .into_iter()
    .filter(|item| item.valid)
    .map(|item| item.transform())
    .collect();
```

### Index-Based Iteration

**Anti-pattern:**
```rust
for i in 0..items.len() {
    process(&items[i]);
}
```

**Pattern:**
```rust
for item in &items {
    process(item);
}
```

### Enumerate When Index Unused

**Anti-pattern:**
```rust
for (_, item) in items.iter().enumerate() {
    process(item);
}
```

**Pattern:**
```rust
for item in &items {
    process(item);
}
```

---

## Type Conversion Patterns

### Manual From Implementation

**Anti-pattern:**
```rust
impl MyType {
    fn from_other(other: Other) -> Self { ... }
}
```

**Pattern:**
```rust
impl From<Other> for MyType {
    fn from(other: Other) -> Self { ... }
}
// Enables: let my: MyType = other.into();
```

### String Conversion Inconsistency

**Anti-pattern:**
```rust
fn greet(name: String) { ... }
greet(user.name.to_string());
```

**Pattern:**
```rust
fn greet(name: impl AsRef<str>) { ... }
greet(&user.name);
```

---

## Lifetime Patterns

### Unnecessary Lifetime Annotations

**Anti-pattern:**
```rust
fn first<'a>(items: &'a [i32]) -> &'a i32 {
    &items[0]
}
```

**Pattern:**
```rust
fn first(items: &[i32]) -> &i32 {
    &items[0]
}
// Elision handles this case
```

### Owned When Borrowed Suffices

**Anti-pattern:**
```rust
struct Config {
    name: String,  // Always from static str
}
```

**Pattern:**
```rust
struct Config {
    name: &'static str,
}
// Or Cow<'static, str> if sometimes dynamic
```

---

## Boolean Expression Patterns

### If-Else Returning Bool

**Anti-pattern:**
```rust
if condition {
    true
} else {
    false
}
```

**Pattern:**
```rust
condition
```

### Match for Boolean

**Anti-pattern:**
```rust
match value {
    Pattern::A | Pattern::B => true,
    _ => false,
}
```

**Pattern:**
```rust
matches!(value, Pattern::A | Pattern::B)
```

---

## Struct Patterns

### Builder Without Default

**Anti-pattern:**
```rust
impl Config {
    fn new() -> Self {
        Self {
            timeout: 30,
            retries: 3,
            verbose: false,
        }
    }
}
```

**Pattern:**
```rust
#[derive(Default)]
struct Config {
    #[default = 30]
    timeout: u32,
    #[default = 3]
    retries: u32,
    verbose: bool,
}
// Or impl Default manually
```

### Excessive Pub Fields

**Anti-pattern:**
```rust
pub struct User {
    pub id: u64,
    pub name: String,
    pub password_hash: String,  // Shouldn't be pub!
}
```

**Pattern:**
```rust
pub struct User {
    id: u64,
    name: String,
    password_hash: String,
}

impl User {
    pub fn id(&self) -> u64 { self.id }
    pub fn name(&self) -> &str { &self.name }
    // No getter for password_hash
}
```

---

## Async Patterns

### Blocking in Async

**Anti-pattern:**
```rust
async fn fetch_data() -> Data {
    std::fs::read_to_string("file.txt").unwrap()  // Blocks!
}
```

**Pattern:**
```rust
async fn fetch_data() -> Result<Data> {
    tokio::fs::read_to_string("file.txt").await
}
```

### Unnecessary Async

**Anti-pattern:**
```rust
async fn add(a: i32, b: i32) -> i32 {
    a + b
}
```

**Pattern:**
```rust
fn add(a: i32, b: i32) -> i32 {
    a + b
}
```

---

## Type System Patterns

### Boolean Return for State Transitions

**Anti-pattern:**
```rust
fn connect(&self, user_id: &str) -> Result<(UserState, bool)> {
    let user = self.get_user(user_id)?;
    let was_offline = user.connections == 0;
    // ... increment connections ...
    Ok((updated_user, was_offline))
}

// Caller must remember what `true` means
let (user, came_online) = users.connect(id)?;
if came_online { broadcast(); }
```

**Pattern:**
```rust
pub enum ConnectResult {
    CameOnline(UserState),
    Reconnected(UserState),
}

fn connect(&self, user_id: &str) -> Result<ConnectResult> {
    // ... logic ...
    Ok(ConnectResult::from_transition(prior, updated))
}

// Intent is self-documenting
match users.connect(id)? {
    ConnectResult::CameOnline(user) => broadcast(),
    ConnectResult::Reconnected(user) => { /* no broadcast */ }
}
```

**Why:** Booleans lose semantic meaning. Enums make invalid states unrepresentable and force exhaustive handling.

---

### Raw Number Checks vs Semantic Types

**Anti-pattern:**
```rust
let was_offline = user.connections == 0;
// ... later ...
if was_offline { ... }
```

**Pattern:**
```rust
pub enum Presence {
    Offline,
    Online(u32),
}

impl Presence {
    fn from_connections(n: u32) -> Self {
        match n {
            0 => Presence::Offline,
            n => Presence::Online(n),
        }
    }
}

let prior = Presence::from_connections(user.connections);
match prior {
    Presence::Offline => { ... }
    Presence::Online(_) => { ... }
}
```

**Why:** Match on meaning, not magic numbers. Compiler enforces handling all cases.

---

### Constructor Methods on Enums

**Anti-pattern:**
```rust
// Scattered logic deciding which variant to construct
if connections == 0 {
    DisconnectResult::WentOffline
} else {
    DisconnectResult::StillOnline { remaining: connections }
}
```

**Pattern:**
```rust
impl DisconnectResult {
    fn from_connections(n: u32) -> Self {
        match n {
            0 => Self::WentOffline,
            n => Self::StillOnline { remaining: n },
        }
    }
}

// Centralized, consistent construction
DisconnectResult::from_connections(new_count)
```

**Why:** Centralizes variant selection logic. Single source of truth for state-to-variant mapping.

---

### State Transitions as First-Class Types

**Anti-pattern:**
```rust
fn process(&self) -> bool {  // true = "something important happened"
    if condition {
        self.do_work();
        true
    } else {
        false
    }
}
```

**Pattern:**
```rust
pub enum ProcessResult {
    Changed { details: String },
    Unchanged,
}

fn process(&self) -> ProcessResult {
    if condition {
        self.do_work();
        ProcessResult::Changed { details: "..." }
    } else {
        ProcessResult::Unchanged
    }
}
```

**Why:** State transitions carry information. Enums can hold associated data, booleans cannot.

---

## Cloudflare Workers / Durable Object Patterns

### Creating New Request Objects When Forwarding to DOs

**Anti-pattern:**
```rust
// NEVER create new Request objects when forwarding to Durable Objects
let stub = env.durable_object("STATE")?.get_by_name(&site)?;
stub.fetch_with_request(Request::new_with_init(
    "http://internal/tail",
    RequestInit::new()
        .with_method(Method::Post)
        .with_body(Some(body.into())),
)?).await
```

**Pattern:**
```rust
// USE the existing request - it contains all the telemetry, headers, and context
let stub = env.durable_object("STATE")?.get_by_name(&site)?;
stub.fetch_with_request(req).await

// If you need to modify headers, clone first:
let mut forwarded = req.clone_mut()?;
forwarded.headers_mut()?.set("X-Custom", "value")?;
stub.fetch_with_request(forwarded).await
```

**Why:** The incoming request contains valuable telemetry data (CF headers, client info, TLS details, geolocation). Creating a new Request throws all of this away. The request IS the data - use it directly. Only clone if you must modify headers; never reconstruct from scratch.

**Critical:** If you need to read the body AND forward the request:
- Clone BEFORE calling `req.json().await?` (which consumes the body)
- Or restructure so only one handler needs to read the body
- Consider using headers for routing decisions instead of parsing body

**Exception:** For internal DO-to-DO forwarding where the telemetry is IN the JSON body (e.g., tail events), creating a request to forward the parsed event is acceptable since the telemetry is preserved in the payload.

### Multi-Tenant DO Isolation

**Anti-pattern:**
```rust
// Single DO with filtering - mixes data, complex filtering logic
let stub = env.durable_object("STATE")?.get_by_name("main")?;
// Then filter events by site in handlers...
```

**Pattern:**
```rust
// Per-tenant DOs - clean isolation via DO name
let site = event["event"]["request"]["headers"]["host"]
    .as_str()
    .unwrap()
    .replace('.', "_");
let stub = env.durable_object("STATE")?.get_by_name(&site)?;
```

**Why:** Use DO names for tenant isolation. Each tenant gets their own DO instance with isolated storage. No filtering logic needed - data is separated at the storage level.

### Direct JSON Access

**Anti-pattern:**
```rust
// Overly defensive chained Option handling
let Some(host) = event.get("event")
    .and_then(|e| e.get("request"))
    .and_then(|r| r.get("headers"))
    .and_then(|h| h.get("host"))
    .and_then(|h| h.as_str())
else {
    return Err("impossible case");
};
```

**Pattern:**
```rust
// Direct indexing when structure is guaranteed
let host = event["event"]["request"]["headers"]["host"].as_str().unwrap();
```

**Why:** When the data structure is guaranteed (e.g., tail events always have host), use direct indexing. Cleaner, faster, and makes the contract explicit.

---

## Inline vs Function Extraction

### Unnecessary Function Extraction

**Anti-pattern:**
```rust
fn extract_site(event: &serde_json::Value) -> Option<String> {
    let host = event.get("event")?.get("request")?.get("headers")?.get("host")?.as_str()?;
    Some(host.replace('.', "_").replace('-', "_"))
}

// Called once
let site = extract_site(&event)?;
```

**Pattern:**
```rust
// Inline when used once - direct and clear
let site = event["event"]["request"]["headers"]["host"]
    .as_str()
    .unwrap()
    .replace('.', "_")
    .replace('-', "_");
```

**Why:** Don't extract functions for one-liners used in a single place. Keep code direct and readable. Functions add indirection without benefit when the logic is simple and localized.

### Unnecessary Defensive Checks

**Anti-pattern:**
```rust
// Checking for something that's guaranteed by the data flow
let Some(host) = event.get("host") else {
    return Err("no host"); // Can never happen
};
```

**Pattern:**
```rust
// Trust the data contract - use unwrap when invariants are guaranteed
let host = event["host"].as_str().unwrap();
```

**Why:** Don't add error handling for impossible cases. If the code path guarantees a value exists, use `unwrap()`. Defensive programming against impossible states adds noise and obscures actual error cases.

---

## JSON / Serde Patterns

### json! Macro for Structured Data

**Anti-pattern:**
```rust
use serde_json::json;

fn build_response(name: &str, price: u64, enabled: bool) -> serde_json::Value {
    json!({
        "siteName": name,
        "priceUsdc": price,
        "isEnabled": enabled,
        "extra": {
            "version": "2"
        }
    })
}
```

**Pattern:**
```rust
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Response {
    site_name: String,
    price_usdc: u64,
    is_enabled: bool,
    extra: ResponseExtra,
}

#[derive(Debug, Clone, serde::Serialize)]
struct ResponseExtra {
    version: String,
}

fn build_response(name: &str, price: u64, enabled: bool) -> Response {
    Response {
        site_name: name.to_string(),
        price_usdc: price,
        is_enabled: enabled,
        extra: ResponseExtra { version: "2".to_string() },
    }
}
```

**Why:** The struct IS the schema. Strongly-typed structs provide:
- Compile-time field name checking (no typos like `"sitename"` vs `"siteName"`)
- IDE autocomplete and refactoring support
- Clear documentation of the data contract
- Type safety for values (can't accidentally put string in numeric field)
- `#[serde(rename_all)]` handles JSON naming conventions automatically

### Mixed Enum Payloads with Untagged

**Anti-pattern:**
```rust
// Building different JSON shapes manually
fn build_payment_accept(is_solana: bool, ...) -> serde_json::Value {
    if is_solana {
        json!({ "network": "solana", "payTo": addr })
    } else {
        json!({ "network": "base", "payTo": addr, "asset": usdc })
    }
}
```

**Pattern:**
```rust
#[derive(Debug, Clone, serde::Serialize)]
#[serde(untagged)]
enum PaymentAccept {
    Evm(EvmPaymentAccept),
    Solana(SolanaPaymentAccept),
}

#[derive(Debug, Clone, serde::Serialize)]
struct EvmPaymentAccept {
    network: String,
    pay_to: String,
    asset: String,
}

#[derive(Debug, Clone, serde::Serialize)]
struct SolanaPaymentAccept {
    network: String,
    pay_to: String,
}
```

**Why:** `#[serde(untagged)]` serializes enum variants directly without a discriminator field. Each variant can have different fields, and serde picks the right shape automatically. Type-safe polymorphism.

---

### Missing serde(default) on Wrapper Structs

**Anti-pattern:**
```rust
// Wrapper struct without defaults - breaks when fields missing
#[derive(serde::Serialize, serde::Deserialize)]
pub struct ArticleWithStatus {
    pub article: Article,           // No default - deserialization fails!
    pub has_been_published: bool,   // No default
}
```

**Pattern:**
```rust
// Always add #[serde(default)] when inner type has Default
#[derive(serde::Serialize, serde::Deserialize)]
pub struct ArticleWithStatus {
    #[serde(default)]
    pub article: Article,
    #[serde(default)]
    pub has_been_published: bool,
}
```

**Why:** When wrapping types that already implement Default, the wrapper should inherit that safety. Without `#[serde(default)]`, deserialization fails with "missing field" errors instead of gracefully using defaults. This is especially critical for API evolution - existing clients may send JSON without new fields.

---

### Inconsistent Endpoint Response Types

**Anti-pattern:**
```rust
// GET /article returns wrapper, GET /article/{version} returns raw - INCONSISTENT
("GET", [slug]) => {
    Response::from_json(&ArticleWithStatus { article, has_been_published })
},
("GET", [slug, version]) => {
    Response::from_json(&article)  // Wrong! Returns Article, not ArticleWithStatus
},

// Client code breaks:
let response: ArticleWithStatus = fetch("/article/44").json().await?;
// Error: missing field `has_been_published`
```

**Pattern:**
```rust
// ALL related endpoints return the SAME response type
("GET", [slug]) => {
    Response::from_json(&ArticleWithStatus { article, has_been_published })
},
("GET", [slug, version]) => {
    let has_been_published = /* query publish status */;
    Response::from_json(&ArticleWithStatus { article, has_been_published })
},
```

**Why:** When introducing a wrapper struct, update ALL endpoints that return the wrapped type. Clients deserialize to a single type - if one endpoint returns `T` and another returns `Wrapper<T>`, deserialization fails. Grep for all return sites when adding wrapper types.

---

## Name-Mismatch Adapter Types

### Intermediate Struct for Field Renaming

**Anti-pattern:**
```rust
// UI sends `body`, domain uses `content` — adapter struct bridges the gap
#[derive(Deserialize)]
struct ActionSignals {
    input: String,
    body: String,  // <-- mismatch: domain calls this `content`
}

impl ActionSignals {
    fn into_patch(self) -> SignalPatch {
        SignalPatch {
            input: (!self.input.is_empty()).then_some(self.input),
            content: (!self.body.is_empty()).then_some(self.body),  // rename here
            ..Default::default()
        }
    }
}

// Handler: deserialize → convert → use
let signals: ActionSignals = req.json().await?;
let patch = signals.into_patch();
client.signal(&patch).await?;
```

**Pattern:**
```rust
// Rename the source ($body → $content) so it matches the domain model.
// Deserialize directly — no intermediate type, no conversion method.
let patch: SignalPatch = req.json().await.unwrap_or_default();
client.signal(&patch).await?;

// Move trivial transforms (empty-string → None) to serde:
fn empty_string_is_none<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    let opt = Option::<String>::deserialize(d)?;
    Ok(opt.filter(|s| !s.is_empty()))
}

#[derive(Deserialize)]
struct SignalPatch {
    #[serde(default, deserialize_with = "empty_string_is_none")]
    input: Option<String>,
    #[serde(default, deserialize_with = "empty_string_is_none")]
    content: Option<String>,
}
```

**Why:** The entire adapter type, its `into_patch()` method, and the manual empty-string filtering existed because a UI signal was named `$body` instead of `$content`. Renaming the signal eliminated the struct, the conversion, and the defensive logic — three layers of code that were pure liability born from a single naming mismatch. When you see a 1:1 field-mapping conversion, ask: *"Can I just rename the source?"* The answer is almost always yes, and the payoff is deletion, not refactoring.

---

## Reinventing Crate APIs

### Custom Encoding When Crate Provides It

**Anti-pattern:**
```rust
// Hand-rolled Base62 encoder for ID generation
const BASE62: &[u8; 62] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

pub fn generate_content_id() -> String {
    let uuid = uuid::Uuid::now_v7();
    let mut n = uuid.as_u128();
    let mut chars = [b'0'; 22];
    for c in chars.iter_mut().rev() {
        *c = BASE62[(n % 62) as usize];
        n /= 62;
    }
    String::from_utf8(chars.to_vec()).unwrap()
}
```

**Pattern:**
```rust
pub fn generate_content_id() -> String {
    uuid::Uuid::now_v7().simple().to_string()
}
```

**Why:** The custom Base62 encoder reimplemented what `uuid` already provides via `.simple()` — a 32-char lowercase hex string that's time-ordered, unique, and slug-safe. The custom version was more code, introduced a case-sensitivity bug (uppercase in IDs failed downstream lowercase-only validation), and required a custom constant table. Before writing any encoding, formatting, or conversion logic, read the crate's API — the method you need almost certainly exists.

**The smell:** A `const` alphabet table + manual division/modulo loop. Any time you see manual base conversion, check if the source type already has a `Display`, `LowerHex`, or format method that produces what you need.

---

## Guard Elimination (see SKILL.md §13)

### The Guard Stack

**Anti-pattern:**
```rust
fn send_invoice(conn: &Connection, email: &str, amount: f64) -> Result<Invoice, Error> {
    if !conn.is_open { return Err(Error::NotConnected); }
    if email.is_empty() { return Err(Error::BadEmail); }
    if amount <= 0.0 { return Err(Error::InvalidAmount); }
    // ...only now can we do the real work
}
```

**Pattern:**
```rust
fn send_invoice(conn: &Connection<Open>, email: Email, amount: Money) -> Result<Invoice, Error> {
    // ...just do the real work
}
```

**Why:** Each guard existed because the signature accepted a state that should never exist. Fixing the signature deletes the guard *and* every duplicate of it at every other call site — and, unlike the guard, the compiler never forgets to run it. The three fixes below are the three levels.

---

### Flag + Parallel Options → Enum

**Anti-pattern:**
```rust
struct Invoice {
    paid: bool,
    receipt: Option<Receipt>,
    error: Option<String>,
}

// Constructible by accident, meaningless by definition:
Invoice { paid: true,  receipt: None, error: Some("declined".into()) }
Invoice { paid: false, receipt: Some(r), error: None }
```

**Pattern:**
```rust
enum Invoice {
    Pending,
    Paid(Receipt),
    Failed(String),
}

match invoice {
    Invoice::Pending => wait(),
    Invoice::Paid(receipt) => store(receipt),
    Invoice::Failed(err) => log(err),
}
```

**Why:** `bool` + 2 `Option`s spans 8 field combinations to express 3 real states — the other 5 are bugs you can type. The enum admits exactly the 3, and each variant carries only the data that state actually owns. Add `Refunded` later and every non-exhaustive `match` becomes a compile error instead of a silent fallthrough.

**The smell:** a `bool` field whose meaning is "which of these `Option`s is set."

---

### Primitive Obsession → Newtype with Fallible Constructor

**Anti-pattern:**
```rust
fn send_invoice(email: &str, amount: f64) -> Result<Invoice, Error> {
    if email.is_empty() { return Err(Error::BadEmail); }
    if amount <= 0.0 { return Err(Error::InvalidAmount); }
    // ...
}
```

**Pattern:**
```rust
pub struct Email(String);   // field private — that is the whole point

impl Email {
    pub fn parse(raw: &str) -> Result<Self, Error> {
        raw.split_once('@')
            .filter(|(local, domain)| !local.is_empty() && domain.contains('.'))
            .ok_or(Error::BadEmail)?;
        Ok(Self(raw.to_string()))
    }
    pub fn as_str(&self) -> &str { &self.0 }
}

pub struct Money { minor_units: i64, currency: Currency }

impl Money {
    pub fn from_minor(minor_units: i64, currency: Currency) -> Result<Self, Error> {
        (minor_units > 0).then_some(Self { minor_units, currency }).ok_or(Error::InvalidAmount)
    }
}

fn send_invoice(email: Email, amount: Money) -> Result<Invoice, Error> {
    // no checks — an Email that isn't an email cannot be constructed
}
```

**Why:** Parse, don't validate. Validation that runs on every call is a check you can forget; parsing that runs at construction is a check the type remembers for you. The proof lives in the type, so every downstream function inherits it for free.

Two things make or break it:
- **Private inner field.** `pub struct Email(pub String)` is a `String` in a costume — anyone can build an invalid one.
- **Single door in.** No `From<String>`, no `Default`, no public struct literal that skips `parse`. One constructor, or the guarantee is fiction.

**`f64` for money is always wrong** — it cannot hold 10 cents exactly and carries no currency. Integer minor units + an explicit currency, every time.

**Where to parse:** at the system boundary — request deserialization, config load, DB row → domain. Raw primitives must not travel inward past that line.

---

### Runtime Flag → Typestate

**Anti-pattern:**
```rust
struct Connection { is_open: bool }

impl Connection {
    fn send(&self, msg: &Msg) -> Result<(), Error> {
        if !self.is_open { return Err(Error::NotConnected); }  // runtime guard
        // ...
    }
}

let conn = Connection::new();
conn.send(&msg)?;   // compiles fine, fails at runtime
```

**Pattern:**
```rust
use std::marker::PhantomData;

pub struct Closed;
pub struct Open;

pub struct Connection<State> {
    socket: Socket,
    _state: PhantomData<State>,
}

impl Connection<Closed> {
    pub fn connect(self) -> Result<Connection<Open>, Error> {
        // consumes the closed connection, hands back an open one
        Ok(Connection { socket: self.socket.open()?, _state: PhantomData })
    }
}

impl Connection<Open> {
    pub fn send(&self, msg: &Msg) -> Result<(), Error> {
        // no check — send does not exist on a closed connection
    }
    pub fn close(self) -> Connection<Closed> { /* ... */ }
}

let conn = Connection::new();
conn.send(&msg)?;   // compile error: no method `send` on `Connection<Closed>`
```

**Why:** The flag could only report the mistake after it happened; the type refuses to let it be written. The markers are zero-sized — the guarantee costs nothing at runtime. Transitions consume `self`, so a closed connection's handle is *gone*, not merely stale. Downstream signatures take `&Connection<Open>` and inherit the proof.

**When NOT to reach for it:** if the state never leaves one function; if callers must hold "either state" and would need `Box<dyn>` or a runtime tag to do it; if one saved check would spread a generic parameter through a dozen unrelated signatures. Then a plain enum + `match` is the honest tool.

**Same shape, other names:** `Request<Unauthenticated>` → `Request<Authenticated>`, `Tx<Open>` → `Tx<Committed>`, `Builder<Missing>` → `Builder<Ready>`.

---

## Signature Contracts (see SKILL.md §14)

### Per-Field `_mut()` Accessors

**Anti-pattern:**
```rust
struct Point { x: i32, y: i32 }

impl Point {
    fn x_mut(&mut self) -> &mut i32 { &mut self.x }
    fn y_mut(&mut self) -> &mut i32 { &mut self.y }

    fn scale(&mut self) {
        let x = self.x_mut();
        let y = self.y_mut();   // E0499: cannot borrow `*self` as mutable twice
        *x *= *y;
    }
}
```

**Pattern:**
```rust
impl Point {
    fn scale(&mut self) {
        let Point { x, y } = self;   // one destructure → two disjoint &mut i32
        *x *= *y;
    }

    // If callers outside really need both, hand back both from ONE borrow:
    fn xy_mut(&mut self) -> (&mut i32, &mut i32) { (&mut self.x, &mut self.y) }
}
```

**Why:** Each accessor's `&mut self` claims the entire struct. The names say "x" and "y"; the signatures say "all of me." The compiler believes the signature — it will not open the bodies to discover the fields are disjoint.

**The key fact:** borrow splitting **works inside a single function body** — `&mut self.x` and `&mut self.y` coexist without complaint. The conflict only materialises when the field projection crosses a *call boundary*. So the fix is usually to stop calling the accessor, not to restructure the caller.

**The smell:** a `_mut()` method that returns a borrow of exactly one field.

---

### `&mut self` Where `&self` Suffices

**Anti-pattern:**
```rust
impl Session {
    fn token(&mut self) -> &str { &self.token }        // never mutates
    fn is_expired(&mut self) -> bool { self.exp < now() }  // never mutates
}

// Every caller now needs exclusive access to read a field:
let t = session.token();
let e = session.is_expired();   // E0499
```

**Pattern:**
```rust
impl Session {
    fn token(&self) -> &str { &self.token }
    fn is_expired(&self) -> bool { self.exp < now() }
}

let t = session.token();
let e = session.is_expired();   // fine — shared borrows stack
```

**Why:** `&mut` is a claim of exclusivity, and the compiler enforces it whether or not the body earns it. An unnecessary `&mut self` serializes callers that could have run concurrently and cascades — every function that calls it must also take `&mut self`. Cheapest possible review win: check whether the body mutates at all.

---

### RefCell to Escape a Borrow Conflict

**Anti-pattern:**
```rust
// Single-threaded, but the fields fight, so wrap them
struct Engine {
    cache: RefCell<HashMap<String, u64>>,
    config: Config,
}

fn refresh(&self) {
    let mut cache = self.cache.borrow_mut();   // panics if already borrowed
    cache.insert(self.config.key.clone(), 0);
}
```

**Pattern:**
```rust
struct Engine {
    cache: HashMap<String, u64>,
    config: Config,
}

fn refresh(&mut self) {
    let Engine { cache, config } = self;   // disjoint borrows, checked at compile time
    cache.insert(config.key.clone(), 0);
}
```

**Why:** `RefCell` moves the borrow check from compile time to runtime. The conflict does not go away — it becomes a panic that fires under a call pattern nobody tested. Use `RefCell` when you genuinely need interior mutability behind a shared reference (shared graph nodes, observer registration), never as an escape hatch from a signature you could have narrowed.

---

## Hot-Path Performance (see SKILL.md §15)

### Owned Keys in a Hot-Loop Map

**Anti-pattern:**
```rust
fn top_users(log: &str) -> Vec<String> {
    let mut counts: HashMap<String, u64> = HashMap::new();
    for line in log.lines() {
        let user = line.split(',').nth(1).unwrap().to_string();  // heap alloc per line
        if counts.contains_key(&user) {
            *counts.get_mut(&user).unwrap() += 1;
        } else {
            counts.insert(user.clone(), 1);                      // second alloc per line
        }
    }
    // sort, take 10...
}
```

**Pattern:**
```rust
fn top_users(log: &str) -> Vec<String> {
    let mut counts: HashMap<&str, u64> = HashMap::new();         // keys borrow the log
    for line in log.lines() {
        let user = line.split(',').nth(1).unwrap();
        *counts.entry(user).or_default() += 1;                   // one hash, zero allocs
    }
    let mut ranked: Vec<(&str, u64)> = counts.into_iter().collect();
    ranked.sort_unstable_by_key(|&(_, n)| std::cmp::Reverse(n));
    ranked.iter().take(10).map(|&(u, _)| u.to_string()).collect()  // own only the 10 returned
}
```

**Why:** Two allocations per line × 20M lines vs 10 at the return — a measured 30% runtime cut. The map keys are views into the source string already in memory; ownership is deferred to the output boundary, where it's bounded. The `entry` call also collapses `contains_key` + `get_mut` + `insert` — three hashes of the same key — into one lookup (another measured 12%).

**The smell:** `to_string()` / `clone()` / `String::from` inside a loop whose iteration count scales with input size.

---

### remove() When Order Doesn't Matter

**Anti-pattern:**
```rust
// Sweep idle sessions from a 1M-element vector
while let Some(i) = sessions.iter().position(|s| s.is_idle()) {
    sessions.remove(i);   // shifts every element after i — O(n) per removal
}
```

**Pattern:**
```rust
// Order irrelevant → O(1) per removal: last element swaps into the hole
let mut i = 0;
while i < sessions.len() {
    if sessions[i].is_idle() { sessions.swap_remove(i); } else { i += 1; }
}

// Or, removing many by predicate in one pass (order preserved):
sessions.retain(|s| !s.is_idle());
```

**Why:** `remove` preserves order by sliding every later element over; on a large vector that's the whole vector per call — `swap_remove` was measured 7000x faster on a 1M-session sweep. `retain` is the idiomatic bulk form: one pass, no index bookkeeping. In std since 1.0; most developers never knew it was there.

---

### Sequential Counting Loop → Rayon (native targets only)

**Anti-pattern:**
```rust
// 20M independent iterations on one core while the other 11 idle
let counts = log.lines().fold(HashMap::new(), |mut m, line| {
    *m.entry(user_of(line)).or_default() += 1;
    m
});
```

**Pattern:**
```rust
use rayon::prelude::*;
let counts = log.par_lines()
    .fold(HashMap::new, |mut m, line| { *m.entry(user_of(line)).or_default() += 1; m })
    .reduce(HashMap::new, |mut a, b| {
        for (k, v) in b { *a.entry(k).or_default() += v; }
        a
    });
```

**Why:** Each core builds a private map (`fold`), then `reduce` merges them — no locks, no contention. Measured 7x on 12 cores. Rewriting the `for` loop as an iterator `fold` first makes the parallel switch a one-word change (`lines` → `par_lines`).

**Hard constraint:** wasm32 / Cloudflare Workers are single-threaded — Rayon does not apply there. On Workers the equivalent levers are eliminating allocations (§15 bullet 1) and eliminating round-trips.

---

## Adding New Patterns

When you discover a new pattern during review:

1. Categorize it (clone, error, iterator, etc.)
2. Show the anti-pattern with realistic code
3. Show the corrected pattern
4. Explain why (if not obvious)

Format:
```markdown
### Pattern Name

**Anti-pattern:**
\`\`\`rust
// Bad code
\`\`\`

**Pattern:**
\`\`\`rust
// Good code
\`\`\`

**Why:** Explanation if needed.
```
