<!-- Copyright 2026. All rights reserved. -->

---
name: adversarial-code-auditor
description: "Pre-emptive adversarial audit of existing code against four correctness risk pillars: memory safety, resource lifecycle, concurrency correctness, and test integrity. Use when you have a cluster of high-risk defects (UAF, double-free, GPU leaks, async races, brittle tests) and need systematic static-analysis-style review before symptoms manifest. NOT for runtime bugs (use debug-protocol) and NOT for spec-to-code gaps (use spec-implementation-auditor)."
compatibility: "Requires gh CLI and git. Works with any agent runtime that supports subagent dispatch."
metadata:
  title: "Adversarial Code Auditor (Correctness Risk Pillars)"
  category: auditing
  risk: low
  source: custom
  version: "2.0"
---

# Adversarial Code Auditor

## Architecture: Autonomous Subagent Filing

Each auditor subagent independently reads, audits, and files its own findings. The coordinator scopes and dispatches only. No coordinator extraction corrupts objectivity.

```
Coordinator (you)
  |
  +-> Auditor Subagent 1  ->  audits file → writes temp body → gh issue create → returns URLs
  +-> Auditor Subagent 2  ->  audits file → writes temp body → gh issue create → returns URLs
  +-> Auditor Subagent N  ->  audits file → writes temp body → gh issue create → returns URLs
  |
  +-> Collect URLs, validate, produce aggregate report
```

| Role | Scope |
|------|-------|
| **Auditor Subagent** | Read file. Audit through pillar lens. Apply severity rubric. Produce 7-section body. Write body to temp file verbatim. Run `gh issue create --body-file`. Return issue URL. |
| **Coordinator** | Scope clusters. Dispatch auditors. Collect issue URLs. Validate (spot-check 1-2 bodies). Cross-reference dedup. Produce aggregate report. Coordinator NEVER touches issue body text. |

---

Use this skill to perform pre-emptive adversarial review of source files identified as belonging to high-risk correctness clusters: **memory safety, resource lifecycle, concurrency correctness, and test integrity**. This is a static-review skill — it reasons about code as written, not about runtime behavior. For dynamic debugging of reproducible defects, use `debug-protocol`.

## When to Invoke

- A cluster of related high-risk defects exists (e.g., 5+ open FFI memory bugs in related source files).
- The defects are static/fundamental in nature (UAF, double-free, missing dispose, racy state mutation, non-isolated tests) — not transient runtime symptoms.
- You want to get ahead of the backlog by auditing the correctness of code before symptoms escalate.
- **The user provides explicit file paths to audit** — no prior issues required. Dispatch auditors directly against the specified files. All findings are "Discovered in audit."

## When NOT to Invoke

- The issue is a single, reproducible runtime bug → use `debug-protocol`.
- The issue is a spec-to-code gap (behavior specified but not implemented) → use `spec-implementation-auditor`.
- The issue is a new feature implementation → use `feature-driven-implementation`.

---

## The Four Risk Pillars

Every audit subagent operates through one of these four lenses, weighted by the target cluster:

### 1. Memory Safety (FFI / Native Bridge)
- Double-free, use-after-free, dangling pointers
- Buffer overflows, signed/unsigned wrap
- C++ exception propagation across FFI boundaries
- Native resource finalizer correctness (NativeFinalizer, reference counting)
- Mutex/pointer lifetime in async callbacks

### 2. Resource Lifecycle (GPU / Image / Memory)
- Missing `dispose()` on GPU resources (`ui.Image`, textures, framebuffers)
- Tile/cache eviction correctness under capacity pressure
- Synchronous I/O on UI thread (file reads, heavy parsing)
- GC allocation churn in render/update hot paths

### 3. Concurrency Correctness (Async Races / ViewModel State)
- `ChangeNotifier` disposal-after-notify races
- Unchecked async type-loading races (multiple futures for same key)
- State mutation from `build()` or other synchronous contexts
- Watch/subscription lifecycle against widget disposal

### 4. Test Integrity (Isolation / Reliability)
- FFI/DB-dependent unit tests (should use mocks/stubs)
- `sleep`/`Future.delayed` loops causing flakiness
- Bare `assert()` instead of `expect()` in test functions
- Missing test suite wrappers (`testWidgets` vs raw `test`)
- Duplicated test fakes/stubs across suites

---

## Severity Calibration (MANDATORY)

Every finding MUST be classified against this objective rubric. Inflated severity invalidates the audit.

| Severity | Criteria | Example |
|----------|----------|---------|
| **Critical** | Crashes the process, corrupts memory, or leaks resources on every invocation with **current code paths**. Must be reachable from existing callers. | `checkStatus` throws before `calloc.free` — memory leak on every error path |
| **Important** | Produces wrong behavior, degrades under load, or creates a correctness risk reachable in edge cases. | LRU cache evicts entries on duplicate writes; cache contract violation |
| **Suggestion** | Code improvement, missing guard for a forward-looking risk, missing test coverage, documentation gap, dead code. **Not a bug in current code paths.** | Missing input validation for future callers; no test for edge case; misleading docstring |
| **Nitpick** | Style, naming, formatting. No correctness impact. | Commented-out block; inconsistent naming |

**Hard rules:**
- If the code contains an explicit guard that already handles the scenario (try/catch, NaN check, null check), you MUST acknowledge it. "No validation" is false if any validation exists. **Read the code before claiming absence.**
- A stub function that cannot throw does NOT have an "exception propagation" risk. Do not flag impossible scenarios.
- If a finding describes behavior that would only occur after future code changes, it is **Suggestion**, not Critical.
- Every finding MUST cite at least one exact file:line pair. If you cannot cite a specific line, do not report it.

---

## UML Diagram Requirements (MANDATORY for Critical & Important)

Every Critical and Important finding MUST include a Mermaid UML diagram in section 4. The diagram type is determined by the defect category:

| Pillar | Defect Pattern | Required UML Diagram |
|--------|---------------|---------------------|
| Memory Safety | UAF / double-free / dangling pointer | `sequenceDiagram` — show threads/lifelines, the point of free, and the point of use-after-free |
| Memory Safety | Exception crossing FFI / missing guard | `sequenceDiagram` — show the throw path from C++ through the FFI boundary to the Dart VM abort |
| Memory Safety | Buffer overflow / signed wrap | `classDiagram` — show the type contract violation (signed to unsigned cast) |
| Resource Lifecycle | Missing dispose / leak on error path | `sequenceDiagram` — show allocation, the exception branch, and the skipped free |
| Resource Lifecycle | Cache eviction / LRU violation | `stateDiagram-v2` — show the cache state machine with the invariant violation |
| Concurrency | ChangeNotifier post-disposal | `sequenceDiagram` — show the async continuation after dispose has been called |
| Concurrency | TOCTOU / async race | `sequenceDiagram` — show two concurrent callers racing on shared state |
| Test Integrity | FFI-dependent test / missing mock | `classDiagram` — show the test dependency on real FFI instead of mock interface |

**UML conformance rules:**
- Sequence diagrams MUST use named lifelines (not generic `Actor`), MUST include `alt`/`loop` combined fragments for branches.
- Class diagrams MUST show composition (`*--`) or association (`-->`) for relationships, MUST NOT contain isolated classes.
- State diagrams MUST use `stateDiagram-v2` syntax, MUST include transition labels.
- Use Case interaction defects MUST use `flowchart` with `([oval])` shapes, a `subgraph` boundary, and stereotype annotations (`«include»`, `«extend»`).
- Every diagram MUST trace to specific `file:line` references from the Correctness Analysis (Section 3). No placeholder diagrams.

---

## Step-by-Step Workflow

### Step 0 — Pre-flight: Cluster Scoping (Coordinator)

This skill runs end-to-end once authorized. No internal gates after start.

**Path A — Bug-based scoping (cluster enrichment):** Use when open bugs exist.

1. **Query the tracker** for all open issues labeled `bug`:
   ```bash
   gh issue list --limit 1000 --state open --label bug --json number,title,labels,body
   ```
2. **Classify each issue** into one or more of the four risk pillars based on title/body keywords.
3. **Extract file:line references** from each issue body. If an issue body lacks file paths, skip it for the audit — static review needs target files.
4. **Build a per-file hit list**: deduplicate and group by source file. Rank by issue count (most-referenced files first).
5. **Select the target pillar** — if the user specified one, use it. Otherwise, audit the highest-density pillar.
6. **Produce scoping summary** with target pillar, file hit list, and issue count. Then proceed directly to Step 1 — no intermediate gate.

**Path B — Direct file scoping (clean-slate audit):** Use when the user provides explicit file paths and a pillar. No prior bugs required.

1. Accept the file paths and pillar from the user. If no pillar specified, default to Memory Safety.
2. Skip the issue query — there are no known issues to read.
3. The file hit list IS the user-provided file paths.
4. **Produce scoping summary** with pillar and file list. Note: "Clean-slate audit — zero known issues. All findings are new discoveries."
5. Proceed directly to Step 1.

### Step 1 — Per-File Adversarial Audit (Auditor Subagents)

For each source file in the hit list:

**A. Dispatch a fresh isolated Auditor Subagent** with ONLY:
- The file path (subagent reads the file itself)
- The target risk pillar lens (one of the four above)
- The full 8-dimension review framework (below)
- Project conventions (from `.pipeline/constitution.md`, language-specific rules from the active implementation profile)
- A strict instruction: **Read the file. Audit it. Do NOT modify anything. Do NOT create issues. Do NOT run `gh`.** The subagent's ONLY output is the set of complete, ready-to-file issue bodies.
- **Existing review docs** for context (e.g., `docs/reviews/review_cpp_bridge.md`) — if they exist.

**B. Auditor Subagent executes the 8-dimension adversarial review:**

#### 1) Context Understanding
- What is the purpose of this code? (From file path, class names, imports)
- What problem does it solve?
- What are its callers and callees?

#### 2) Correctness Analysis (weighted by risk pillar)
- **Memory Safety pillar weight: HIGH.** Check every raw pointer dereference, every `Pointer.fromFunction`, every `malloc`/`calloc`/`free` pair, every `NativeFinalizer` registration, every FFI string conversion for UAF risk.
- **Resource Lifecycle pillar weight: HIGH.** Check every class for `dispose()`, every `ui.Image` creation for matching disposal, every cache map for eviction-on-write, every `File.readAsStringSync` call.
- **Concurrency pillar weight: HIGH.** Check every `notifyListeners()` for post-disposal risk, every async factory for idempotency, every `build()` override for state mutation.
- **Test Integrity pillar weight: HIGH.** Check every test file for `import 'package:flutter_test/flutter_test.dart'`, absence of `sleep`/`Future.delayed`, presence of `expect()` over `assert()`, correct test wrapper functions.

#### 3) Security Review
- Input validation: Is data crossing FFI/layer boundaries validated?
- Data exposure: Are secrets, tokens, or keys exposed in logs or error messages?
- Injection: Are query strings or native calls constructed from unsanitized input?

#### 4) Performance Considerations
- **Memory Safety:** Are allocations paired with deallocations on all code paths (including error returns)?
- **Resource Lifecycle:** Are cache eviction policies correct under capacity pressure? Is sync I/O on the right thread?
- **Concurrency:** Are locks/guards scoped to minimize contention?

#### 5) Code Quality & Readability
- Are variable and function names intention-revealing?
- Is the code consistent with the project's naming and formatting conventions?
- Are there dead code blocks, commented-out sections, or placeholder stubs?

#### 6) Architecture & Design
- Does the code follow the Clean Architecture pattern from the implementation profile?
- Are repository/adapter boundaries intact (no persistence SDK imports in UI)?
- Are cross-layer dependencies pointing in the correct direction?

#### 7) Testing
- Is there test coverage for the code in this file?
- Do existing tests cover the risk-pillar scenarios (disposal, error paths, FFI boundary conditions)?
- Are tests isolated from real databases, network, and FFI?

#### 8) Documentation
- Are public APIs documented (JSDoc/TSDoc or DartDoc)?
- Are UML traceability tags present (`@realizes UML::ClassName::operationName`)?
- Are complex algorithms explained?

**C. Auditor Subagent output — for each Critical and Important finding, produce a complete, self-contained issue body:**

```
ISSUE_TITLE: [AUDIT] [File name]: [Brief finding description]

ISSUE_BODY:
## 1. Context and References
- **File**: `path/to/file.ext:line-line`
- **Pillar**: [Memory Safety | Resource Lifecycle | Concurrency | Test Integrity]
- **Symptom**: Observable failure caused by this defect

## 2. Root Cause Analysis (5 Whys)
1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

## 3. Correctness Analysis
[Detailed explanation of WHY the defect is a defect — trace the data flow, identify the invariant being violated, explain the failure mode in concrete terms. Reference the actual source code lines and the 8-dimension review that revealed this finding.]

## 4. UML Diagrams (MANDATORY for Critical & Important)
Select diagram type per the UML Diagram Requirements table. Every diagram MUST trace to specific file:line references from Section 3.

```mermaid
sequenceDiagram
    participant ...
    ...
```

## 5. Affected Callers / Downstream Impact
- [Caller 1] — [how it triggers or is affected by this defect]
- [Caller 2] — ...

## 6. Proposed Correction
[Code snippet showing the fix]

## 7. Relationship to Existing Issues
- **Confirms known issue** [#NNN] — if this finding is already tracked
- **Extends** [#NNN] — if this adds new dimensions to a known issue
- **Discovered in audit** — if this is a new finding

## Audit Source
Adversarial [Pillar] Audit — `docs/audits/adversarial-audit-[pillar]-[YYYY-MM-DD].md`
```

Each issue body MUST include all 7 sections. Section 4 (UML Diagram) is MANDATORY for Critical and Important findings — select the diagram type from the UML Diagram Requirements table. Suggestions may skip section 4.

The Output MUST be clearly delimited with `ISSUE_TITLE:` and `ISSUE_BODY:` markers.
```

**For Suggestions:**
- **Bug-based mode:** produce a comment body delimited with `COMMENT_FOR_ISSUE: #NNN` and `COMMENT_BODY:`.
- **Clean-slate mode:** produce a standard 7-section ISSUE_BODY with severity Suggestion. All findings are new issues since no existing issues exist to comment on.

**D. Auditor Subagent files its own findings:**

For each finding, the auditor subagent MUST:
1. Write the complete 7-section issue body to a temp file verbatim (no summarization):
   ```bash
   cat > /tmp/gh_body.md << 'ENDOFFILE'
   [complete ISSUE_BODY as specified above — all 7 sections, UML if Critical/Important]
   ENDOFFILE
   ```
2. File the issue directly:
   ```bash
   gh issue create --repo gintatkinson/3dgs-002 --title "[exact ISSUE_TITLE]" --label "bug" --body-file /tmp/gh_body.md
   ```
3. For bug-based mode only — comments on existing issues:
   ```bash
   cat > /tmp/gh_comment.md << 'ENDOFFILE'
   [complete COMMENT_BODY]
   ENDOFFILE
   gh issue comment N --repo gintatkinson/3dgs-002 --body-file /tmp/gh_comment.md
   ```
4. Return the issue URL(s) from stdout. The subagent's output to the coordinator is the list of created issue URLs and their severities.

**Quality rules are embedded in the auditor's HARD RULES prompt.** No separate coordinator gate. The auditor applies the Severity Calibration rubric, UML requirements, and fact-verification at audit time — before filing.

### Step 1.E — Coordinator Collects URLs

After ALL auditor subagents return:

1. Collect the issue URLs from each subagent's output.
2. Spot-check 1-2 issue bodies by fetching via `gh issue view N --json body` — verify sections are complete, UML exists for Critical/Important. Do NOT edit bodies. If a body is truncated or malformed, ask that subagent to refile.
3. Compile the URL list for dedup and report.

### Step 2 — Cross-Reference Deduplication (Coordinator)

After filing:

1. **Collect all filed issue URLs** from `gh issue create` output.
2. **Check for duplicates** — same root cause in multiple files. For duplicates, close extras and link to canonical issue.
3. **Cross-reference across pillars** — add comments linking related findings across files.

### Step 3 — Aggregate Risk Report (Coordinator Subagent)

Dispatch a final fresh subagent to produce the aggregate report:

```markdown
# Adversarial Audit Report — [Pillar(s)] — [Date]

## Scope
- Risk pillar(s) audited: [list]
- Source files audited: N
- Open issues in cluster before audit: M
- New issues filed: P

## Findings by Severity
- Critical: X
- Important: Y
- Suggestion: Z

## Findings by Pillar
- Memory Safety: A
- Resource Lifecycle: B
- Concurrency: C
- Test Integrity: D

## Per-File Summary
| File | Critical | Important | Suggestion | Nitpick | New Issues |
|---|---|---|---|---|---|
| `src/ffi/bridge.dart` | 3 | 2 | 0 | 1 | #142, #143, #144 |
| ... | | | | | |

## Cross-Cutting Patterns
- [Pattern 1: description, files affected, canonical issue]
- [Pattern 2: ...]

## Recommended Remediation Priority
1. [Highest-priority finding — block all other work]
2. [...]
```

Save the report to `docs/audits/adversarial-audit-<pillar>-<YYYY-MM-DD>.md`.

### Step 4 — Back-Propagation Decision

After the audit completes:
- If the findings expose a gap in the pipeline tooling or skills (e.g., a class of defect the existing skills cannot catch), this skill itself should be proposed to the upstream `gintatkinson/digital-pipeline-repo`.
- File an upstream issue:
  ```bash
  gh issue create \
    --repo gintatkinson/digital-pipeline-repo \
    --title "Skill Proposal: adversarial-code-auditor (Correctness Risk Pillars)" \
    --body "[Summary of results from pilot audit, signal quality, and rationale for inclusion]" \
    --label "enhancement"
  ```

---

## Persistence Rules
- Each file audit MUST use a fresh, independent subagent — do not reuse or combine contexts.
- Do NOT skip or combine pillars — audit one pillar at a time for signal clarity.
- **Subagents file their own findings.** Each auditor writes its 7-section body to a temp file and runs `gh issue create --body-file` itself. No coordinator extraction. No body touching.
- The coordinator MUST NOT write, edit, summarize, or extract issue bodies. Coordinator only collects URLs, spot-checks for completeness, cross-references, and produces the aggregate report.
- Quality rules (severity calibration, file:line citations, UML requirements, fact-verification) are embedded in the auditor prompt's HARD RULES. The auditor applies them before filing.

## Audit Checklist
- [ ] Step 0: Cluster scoped, file hit list built, pillar selected, scoping summary produced
- [ ] Step 1: All files audited by isolated subagents — each filed its own issues via `gh --body-file`
- [ ] Step 1.E: Coordinator collected all issue URLs, spot-checked 1-2 bodies for completeness
- [ ] Step 2: Cross-reference deduplication complete
- [ ] Step 3: Aggregate risk report saved to `docs/audits/`
- [ ] Step 4: Back-propagation decision made (upstream proposal)

---

## How to Run This Skill

**Path A — Bug-based scoping:** Use when open bugs exist.

1. **Phase 0:** Query open bugs. Classify into pillars. Build file hit list. Produce scoping summary. Proceed directly to Phase 1.

2. **Phase 1:** For each file, copy the pillar-specific "Bug-based mode" prompt template. Replace `[FILE_PATH]`, `[REVIEW_DOC_PATH]`, `[ISSUE_NUMBERS]` with real values. Dispatch auditors in batches of up to 6 in parallel. Collect outputs.

**Path B — Clean-slate scoping:** Use when zero open bugs exist, or user provides explicit file paths.

1. **Phase 0-B:** Accept file paths and pillar from the user. No issue query needed. File hit list = user-provided paths. Produce scoping summary noting "Clean-slate audit — zero known issues."

2. **Phase 1-B:** For each file, copy the pillar-specific "Clean-slate mode" prompt template. Replace `[FILE_PATH]` with real values. No `[ISSUE_NUMBERS]` to substitute. Dispatch auditors in batches of up to 6 in parallel. All findings use ISSUE_TITLE/ISSUE_BODY — no COMMENT_FOR_ISSUE needed.

**Both paths continue the same from here. Each auditor subagent independently:**
- Reads the file
- Audits through pillar lens applying severity rubric + UML requirements + fact-verification
- Writes the complete 7-section issue body to `/tmp/gh_body.md`
- Runs `gh issue create --repo gintatkinson/3dgs-002 --title "[title]" --label "bug" --body-file /tmp/gh_body.md`
- Returns the issue URL to the coordinator
- For Path A only: comments on existing issues via `gh issue comment`

3. **Phase 1.E (Coordinator):** Collect all issue URLs from subagent output. Spot-check 1-2 bodies via `gh issue view N --json body`. Do not touch bodies.

4. **Phase 2:** Cross-reference for duplicates. Link related findings across files.

5. **Phase 3:** Produce aggregate report. Include all filed issue URLs with severities.

6. **Repeat** for remaining pillars. Stop only when all open bugs have audit coverage or human intervenes.

### Memory Safety Auditor Prompt

**Bug-based mode (known issues exist):**
```
Auditor. Read file: [FILE_PATH]. Also read [REVIEW_DOC_PATH] if it exists.
Pillar: Memory Safety. 8-dimension review. Weight Correctness HIGH.

KNOWN ISSUES for this file: [ISSUE_NUMBERS]. Read: gh issue view [N1 N2 N3] --repo gintatkinson/3dgs-002 --json body

Focus: double-free, UAF, dangling pointers, exception safety at extern "C", malloc/free pairing, NativeFinalizer correctness, mutex lifetime in async callbacks, string lifetime across FFI.

HARD RULES:
- Every finding MUST cite exact file:line. No line = no report.
- Before claiming NEW issue: read known issue bodies via gh. If the root cause is already described, output COMMENT_FOR_ISSUE, not a new ISSUE.
- Apply Severity Calibration rubric. Only reachable-from-current-callers is Critical. Forward-looking/future-risk is Suggestion.
- Verify facts against source. "No validation" is only true if zero checks exist. If a NaN guard exists, say so.
- Stub functions that cannot throw have no exception risk. Do not flag.
- Section 4 UML diagram is MANDATORY for every Critical and Important finding. Select diagram type from the UML Diagram Requirements table. Use file:line references from Section 3 as lifeline/transition annotations.

For each finding: write the complete 7-section ISSUE_BODY to /tmp/gh_body.md, then run:
  gh issue create --repo gintatkinson/3dgs-002 --title "[ISSUE_TITLE]" --label "bug" --body-file /tmp/gh_body.md
For comments on existing issues: write COMMENT_BODY to /tmp/gh_comment.md, then run:
  gh issue comment N --repo gintatkinson/3dgs-002 --body-file /tmp/gh_comment.md
Return the list of created issue URLs and comment references. PROCEED
```

**Clean-slate mode (no known issues):**
```
Auditor. Read file: [FILE_PATH]. Also read [REVIEW_DOC_PATH] if it exists.
Pillar: Memory Safety. 8-dimension review. Weight Correctness HIGH.

CLEAN-SLATE AUDIT: No known issues for this file. All findings are new discoveries — use ISSUE_TITLE / ISSUE_BODY for every finding.

Focus: double-free, UAF, dangling pointers, exception safety at extern "C", malloc/free pairing, NativeFinalizer correctness, mutex lifetime in async callbacks, string lifetime across FFI.

HARD RULES:
- Every finding MUST cite exact file:line. No line = no report.
- ALL findings are "Discovered in audit" — no COMMENT_FOR_ISSUE needed.
- Apply Severity Calibration rubric. Only reachable-from-current-callers is Critical. Forward-looking/future-risk is Suggestion.
- Verify facts against source. "No validation" is only true if zero checks exist. If a NaN guard exists, say so.
- Stub functions that cannot throw have no exception risk. Do not flag.
- Section 4 UML diagram is MANDATORY for every Critical and Important finding. Select diagram type from the UML Diagram Requirements table. Use file:line references from Section 3 as lifeline/transition annotations.

For each finding, produce the complete 7-section ISSUE_BODY using this template. ALL 7 sections mandatory. No abbreviations.

```
## 1. Context and References
- **File**: `path/to/file.ext:line-line`
- **Pillar**: [Pillar]
- **Symptom**: [Observable failure]

## 2. Root Cause Analysis (5 Whys)
1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

## 3. Correctness Analysis
[Trace data flow. Identify invariant violated. Reference specific source lines.]

## 4. UML Diagrams (MANDATORY for Critical & Important)
```mermaid
sequenceDiagram
    participant A as [Caller]
    participant B as [Target]
    A->>B: [action]
    B-->>A: [defect triggered]
```
Fill in real participants, messages, and annotations. This MUST be valid mermaid syntax inside the fenced block. ASCII art text diagrams are not mermaid and will not render.
```

## 5. Affected Callers / Downstream Impact
- [Caller] — [how affected]

## 6. Proposed Correction
[Code snippet]

## 7. Relationship to Existing Issues
- **Discovered in audit** — clean-slate audit.

SEVERITY: [Critical | Important | Suggestion | Nitpick]
FILE_LOCATION: [path:line-line]
```

Write each completed body to /tmp/gh_body.md. File via:
  gh issue create --repo gintatkinson/3dgs-002 --title "[ISSUE_TITLE]" --label "bug" --body-file /tmp/gh_body.md
Return the list of created issue URLs with severities. PROCEED
```

### Resource Lifecycle Auditor Prompt

**Bug-based mode:**
```
Auditor. Read file: [FILE_PATH]. Also read [REVIEW_DOC_PATH] if it exists.
Pillar: Resource Lifecycle. 8-dimension review. Weight Correctness HIGH.

KNOWN ISSUES for this file: [ISSUE_NUMBERS]. Read: gh issue view [N1 N2 N3] --repo gintatkinson/3dgs-002 --json body

Focus: missing dispose() on GPU resources, cache eviction correctness, sync I/O on UI thread, GC allocation churn in paint/build, repaint storms, widget tree depth, BackdropFilter overhead.

HARD RULES:
- Every finding MUST cite exact file:line. No line = no report.
- Before claiming NEW issue: read known issue bodies via gh. If the root cause is already described, output COMMENT_FOR_ISSUE, not a new ISSUE.
- Apply Severity Calibration rubric. Only reachable-from-current-callers is Critical. Forward-looking/future-risk is Suggestion.
- Verify facts against source. Read the code before claiming a pattern is missing.
- Section 4 UML diagram is MANDATORY for every Critical and Important finding. Select diagram type from the UML Diagram Requirements table. Use file:line references from Section 3 as lifeline/transition annotations.

For each finding, produce the complete 7-section body using this template. ALL 7 sections mandatory. No abbreviations.

For new issues use ISSUE_TITLE/ISSUE_BODY. For existing issue comments use COMMENT_FOR_ISSUE:#N/COMMENT_BODY.

ISSUE_BODY TEMPLATE:
```
## 1. Context and References
- **File**: `path/to/file.ext:line-line`
- **Pillar**: [Pillar]
- **Symptom**: [Observable failure]

## 2. Root Cause Analysis (5 Whys)
1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

## 3. Correctness Analysis
[Trace data flow. Identify invariant violated. Reference source lines.]

## 4. UML Diagrams (MANDATORY for Critical & Important)
```mermaid
sequenceDiagram
    participant A as [Caller]
    participant B as [Target]
    A->>B: [action]
    B-->>A: [defect triggered]
```
Fill in real participants, messages, and annotations. Valid mermaid syntax required. No ASCII art.

## 5. Affected Callers / Downstream Impact

## 6. Proposed Correction

## 7. Relationship to Existing Issues
- Confirms known issue [#NNN] — if already tracked
- Extends [#NNN] — if adds new dimensions
- **Discovered in audit** — if new finding

SEVERITY: [Critical|Important|Suggestion|Nitpick]
FILE_LOCATION: [path:line-line]
```

Write to /tmp/gh_body.md (or /tmp/gh_comment.md), file via gh issue create --body-file (or gh issue comment). Return URLs with severities. PROCEED
```

**Clean-slate mode:**
```
Auditor. Read file: [FILE_PATH]. Also read [REVIEW_DOC_PATH] if it exists.
Pillar: Resource Lifecycle. 8-dimension review. Weight Correctness HIGH.

CLEAN-SLATE AUDIT: No known issues. All findings are new discoveries — use ISSUE_TITLE / ISSUE_BODY for every finding.

Focus: missing dispose() on GPU resources, cache eviction correctness, sync I/O on UI thread, GC allocation churn in paint/build, repaint storms, widget tree depth, BackdropFilter overhead.

HARD RULES:
- Every finding MUST cite exact file:line. No line = no report.
- ALL findings are "Discovered in audit."
- Apply Severity Calibration rubric. Only reachable-from-current-callers is Critical.
- Verify facts against source. Read the code before claiming a pattern is missing.
- Section 4 UML diagram MANDATORY for Critical/Important.

For each finding, produce the complete 7-section ISSUE_BODY using this template. ALL 7 sections mandatory. No abbreviations.

```
## 1. Context and References
- **File**: `path/to/file.ext:line-line`
- **Pillar**: [Pillar]
- **Symptom**: [Observable failure]

## 2. Root Cause Analysis (5 Whys)
1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

## 3. Correctness Analysis
[Trace data flow. Identify invariant violated. Reference specific source lines.]

## 4. UML Diagrams (MANDATORY for Critical & Important)
```mermaid
sequenceDiagram
    participant A as [Caller]
    participant B as [Target]
    A->>B: [action]
    B-->>A: [defect triggered]
```
Fill in real participants, messages, and annotations. This MUST be valid mermaid syntax inside the fenced block. ASCII art text diagrams are not mermaid and will not render.
```

## 5. Affected Callers / Downstream Impact
- [Caller] — [how affected]

## 6. Proposed Correction
[Code snippet]

## 7. Relationship to Existing Issues
- **Discovered in audit** — clean-slate audit.

SEVERITY: [Critical | Important | Suggestion | Nitpick]
FILE_LOCATION: [path:line-line]
```

Write each completed body to /tmp/gh_body.md. File via:
  gh issue create --repo gintatkinson/3dgs-002 --title "[ISSUE_TITLE]" --label "bug" --body-file /tmp/gh_body.md
Return the list of created issue URLs with severities. PROCEED
```

### Concurrency Auditor Prompt

**Bug-based mode:**
```
Auditor. Read file: [FILE_PATH]. Also read [REVIEW_DOC_PATH] if it exists.
Pillar: Concurrency Correctness. 8-dimension review. Weight Correctness HIGH.

KNOWN ISSUES for this file: [ISSUE_NUMBERS]. Read: gh issue view [N1 N2 N3] --repo gintatkinson/3dgs-002 --json body

Focus: ChangeNotifier disposal-after-notify, async type-loading races, state mutation in build(), watch/subscription lifecycle, TOCTOU on shared state, re-entrant async methods, missing _disposed guards.

HARD RULES:
- Every finding MUST cite exact file:line. No line = no report.
- Before claiming NEW issue: read known issue bodies via gh. If the root cause is already described, output COMMENT_FOR_ISSUE, not a new ISSUE.
- Apply Severity Calibration rubric. Only reachable-from-current-callers is Critical. Forward-looking/future-risk is Suggestion.
- Verify facts against source. Read the code before claiming a guard is missing.
- Section 4 UML diagram is MANDATORY for every Critical and Important finding. Select diagram type from the UML Diagram Requirements table. Use file:line references from Section 3 as lifeline/transition annotations.

For each finding, produce the complete 7-section body using this template. ALL 7 sections mandatory. No abbreviations.

For new issues use ISSUE_TITLE/ISSUE_BODY. For existing issue comments use COMMENT_FOR_ISSUE:#N/COMMENT_BODY.

ISSUE_BODY TEMPLATE:
```
## 1. Context and References
- **File**: `path/to/file.ext:line-line`
- **Pillar**: [Pillar]
- **Symptom**: [Observable failure]

## 2. Root Cause Analysis (5 Whys)
1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

## 3. Correctness Analysis
[Trace data flow. Identify invariant violated. Reference source lines.]

## 4. UML Diagrams (MANDATORY for Critical & Important)
```mermaid
sequenceDiagram
    participant A as [Caller]
    participant B as [Target]
    A->>B: [action]
    B-->>A: [defect triggered]
```
Fill in real participants, messages, and annotations. Valid mermaid syntax required. No ASCII art.

## 5. Affected Callers / Downstream Impact

## 6. Proposed Correction

## 7. Relationship to Existing Issues
- Confirms known issue [#NNN] — if already tracked
- Extends [#NNN] — if adds new dimensions
- **Discovered in audit** — if new finding

SEVERITY: [Critical|Important|Suggestion|Nitpick]
FILE_LOCATION: [path:line-line]
```

Write to /tmp/gh_body.md (or /tmp/gh_comment.md), file via gh issue create --body-file (or gh issue comment). Return URLs with severities. PROCEED
```

**Clean-slate mode:**
```
Auditor. Read file: [FILE_PATH]. Also read [REVIEW_DOC_PATH] if it exists.
Pillar: Concurrency Correctness. 8-dimension review. Weight Correctness HIGH.

CLEAN-SLATE AUDIT: No known issues. All findings new — use ISSUE_TITLE / ISSUE_BODY.

Focus: ChangeNotifier disposal-after-notify, async type-loading races, state mutation in build(), watch/subscription lifecycle, TOCTOU on shared state, re-entrant async methods, missing _disposed guards.

HARD RULES: cite file:line, apply Severity Calibration, verify against source, UML mandatory for Critical/Important.
7-SECTION BODY TEMPLATE (all sections mandatory for every finding):
```
## 1. Context and References
- **File**: `path/to/file.ext:line-line`
- **Pillar**: [Pillar]
- **Symptom**: [Observable failure]

## 2. Root Cause Analysis (5 Whys)
1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

## 3. Correctness Analysis
[Trace data flow. Identify invariant violated. Reference source lines.]

## 4. UML Diagrams (MANDATORY for Critical & Important)
```mermaid
sequenceDiagram
    participant A as [Caller]
    participant B as [Target]
    A->>B: [action]
    B-->>A: [defect triggered]
```
Fill in real participants, messages, and annotations. Valid mermaid syntax required. No ASCII art.

## 5. Affected Callers / Downstream Impact

## 6. Proposed Correction

## 7. Relationship to Existing Issues
- **Discovered in audit**

SEVERITY: [Critical|Important|Suggestion|Nitpick]
FILE_LOCATION: [path:line-line]
```

Write each body to /tmp/gh_body.md, file via gh issue create --body-file. Return URLs with severities. PROCEED
```

### Test Integrity Auditor Prompt

**Bug-based mode:**
```
Auditor. Read file: [FILE_PATH]. Also read [REVIEW_DOC_PATH] if it exists.
Pillar: Test Integrity. 8-dimension review. Weight Correctness HIGH.

KNOWN ISSUES for this file: [ISSUE_NUMBERS]. Read: gh issue view [N1 N2 N3] --repo gintatkinson/3dgs-002 --json body

Focus: FFI/DB-dependent tests requiring mocks, sleep/Future.delayed loops, bare assert() vs expect(), missing testWidgets wrappers, duplicated fakes/stubs, hardcoded paths, flaky timing assertions, as dynamic casting.

HARD RULES:
- Every finding MUST cite exact file:line. No line = no report.
- Before claiming NEW issue: read known issue bodies via gh. If the root cause is already described, output COMMENT_FOR_ISSUE, not a new ISSUE.
- Apply Severity Calibration rubric. Missing test coverage is a Suggestion, not Critical.
- Verify facts against source. If a test file exists at the expected path, acknowledge it.
- Section 4 UML diagram is MANDATORY for every Critical and Important finding. Select diagram type from the UML Diagram Requirements table. Use file:line references from Section 3 as lifeline/transition annotations.

For each finding, produce the complete 7-section body using this template. ALL 7 sections mandatory. No abbreviations.

For new issues use ISSUE_TITLE/ISSUE_BODY. For existing issue comments use COMMENT_FOR_ISSUE:#N/COMMENT_BODY.

ISSUE_BODY TEMPLATE:
```
## 1. Context and References
- **File**: `path/to/file.ext:line-line`
- **Pillar**: [Pillar]
- **Symptom**: [Observable failure]

## 2. Root Cause Analysis (5 Whys)
1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

## 3. Correctness Analysis
[Trace data flow. Identify invariant violated. Reference source lines.]

## 4. UML Diagrams (MANDATORY for Critical & Important)
```mermaid
sequenceDiagram
    participant A as [Caller]
    participant B as [Target]
    A->>B: [action]
    B-->>A: [defect triggered]
```
Fill in real participants, messages, and annotations. Valid mermaid syntax required. No ASCII art.

## 5. Affected Callers / Downstream Impact

## 6. Proposed Correction

## 7. Relationship to Existing Issues
- Confirms known issue [#NNN] — if already tracked
- Extends [#NNN] — if adds new dimensions
- **Discovered in audit** — if new finding

SEVERITY: [Critical|Important|Suggestion|Nitpick]
FILE_LOCATION: [path:line-line]
```

Write to /tmp/gh_body.md (or /tmp/gh_comment.md), file via gh issue create --body-file (or gh issue comment). Return URLs with severities. PROCEED
```

**Clean-slate mode:**
```
Auditor. Read file: [FILE_PATH]. Also read [REVIEW_DOC_PATH] if it exists.
Pillar: Test Integrity. 8-dimension review. Weight Correctness HIGH.

CLEAN-SLATE AUDIT: No known issues. All findings new — use ISSUE_TITLE / ISSUE_BODY.

Focus: FFI/DB-dependent tests requiring mocks, sleep/Future.delayed loops, bare assert() vs expect(), missing testWidgets wrappers, duplicated fakes/stubs, hardcoded paths, flaky timing assertions, as dynamic casting.

HARD RULES: cite file:line, apply Severity Calibration (missing coverage = Suggestion), verify against source, UML mandatory for Critical/Important.
7-SECTION BODY TEMPLATE (all sections mandatory):
```
## 1. Context and References
- **File**: `path/to/file.ext:line-line`
- **Pillar**: Test Integrity
- **Symptom**: [Observable failure]

## 2. Root Cause Analysis (5 Whys)
1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

## 3. Correctness Analysis
[Trace data flow. Reference source lines.]

## 4. UML Diagrams (MANDATORY for Critical & Important)
```mermaid
sequenceDiagram
    participant A as [Caller]
    participant B as [Target]
    A->>B: [action]
    B-->>A: [defect triggered]
```
Fill in real participants, messages, and annotations. Valid mermaid syntax required. No ASCII art.

## 5. Affected Callers / Downstream Impact

## 6. Proposed Correction

## 7. Relationship to Existing Issues
- **Discovered in audit**

SEVERITY: [Critical|Important|Suggestion|Nitpick]
FILE_LOCATION: [path:line-line]
```

Write each body to /tmp/gh_body.md, file via gh issue create --body-file. Return URLs with severities. PROCEED
```

---

## Worked Example: Complete 7-Section Issue Body

```markdown
## 1. Context and References
- **File**: `cesium_native_bridge/src/bridge.cpp:56-61`
- **Pillar**: Memory Safety
- **Symptom**: Dart FFI caller reads garbage or crashes after calling bridge_get_last_error. Intermittent, correlated with multi-threaded tile loading.

## 2. Root Cause Analysis (5 Whys)
1. Why does Dart crash? It dereferences a pointer whose target was freed.
2. Why was it freed? bridge_get_last_error returns c_str() of internal std::string, then unlocks mutex. Another thread enters bridge_shutdown, erases BridgeState, frees the string.
3. Why return raw pointer to internal state? API designed for zero-copy convenience, assuming caller consumes before next bridge call.
4. Why no lifetime extension? No strdup or caller-allocated buffer pattern.
5. Why was this not designed in? C FFI pattern chose raw C string returns without ownership protocol, relying on caller discipline impossible in multi-threaded FFI.

## 3. Correctness Analysis
Data flow: Thread T1 calls bridge_get_last_error → acquires g_statesMutex → evaluates c_str() on line 60 → returns pointer p → lock_guard destructor releases mutex → Thread T2 enters bridge_shutdown → acquires mutex → erases map entry (line 48) → unique_ptr destructor frees BridgeState → ~std::string() deallocates buffer → T1 dereferences p → use-after-free.

Invariant violated: pointer returned across FFI must remain valid at least until next bridge call by same logical owner.

## 4. UML Diagrams
```mermaid
sequenceDiagram
    participant T1 as Dart Thread T1
    participant Bridge as bridge_get_last_error
    participant T2 as Dart Thread T2 (shutdown)
    T1->>Bridge: get_last_error(handle)
    Bridge-->>T1: return c_str() pointer p
    Note over T1: p is now dangling
    T2->>Bridge: shutdown(handle)
    Bridge->>Bridge: erase BridgeState → ~std::string()
    T1->>T1: read *p → USE-AFTER-FREE
```

## 5. Affected Callers / Downstream Impact
- Dart cesium_bridge.dart:getLastError() — receives dangling pointer after any concurrent shutdown
- Any Dart async code calling getLastError after tile load failure

## 6. Proposed Correction
```cpp
// Replace raw const char* return with caller-allocated buffer:
int32_t bridge_get_last_error(bridge_handle_t handle, char* out_buffer, int32_t buffer_size) {
  if (!out_buffer || buffer_size <= 0) return BRIDGE_ERR_MEMORY;
  std::lock_guard<std::mutex> lock(g_statesMutex);
  auto it = g_states.find(handle);
  if (it == g_states.end()) {
    std::strncpy(out_buffer, "Invalid handle", buffer_size - 1);
    out_buffer[buffer_size - 1] = '\0';
    return BRIDGE_ERR_INIT;
  }
  std::strncpy(out_buffer, it->second->lastError.c_str(), buffer_size - 1);
  out_buffer[buffer_size - 1] = '\0';
  return BRIDGE_OK;
}
```

## 7. Relationship to Existing Issues
Confirms known issue [#74] — this finding matches the existing defect report

SEVERITY: Critical
FILE_LOCATION: cesium_native_bridge/src/bridge.cpp:56-61
```
