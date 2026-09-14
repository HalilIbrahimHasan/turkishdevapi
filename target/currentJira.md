# Jira Implementation Rules

> **How to use:** Attach **`@Jira-Implementation-Rules.md`** plus the exported ticket pack when you want the agent to **implement** automation from a Jira story — not just read or design.  
> Typical intake: `@Jira-Implementation-Rules.md` + `@target/jira-export/tickets/<KEY>/INDEX.md` (+ attachments folder if UI screenshots matter).

**Related docs:** [QA-Intelligence-Rules.md](./QA-Intelligence-Rules.md) · [QA-Review-Rules.md](./QA-Review-Rules.md) · [Jira-Rules.md](./Jira-Rules.md) · [Jira-TestCase-Rules.md](./Jira-TestCase-Rules.md) · [HappyPath-Rules.md](./HappyPath-Rules.md) · [Regression-Rules.md](./Regression-Rules.md) · [Framework-Rules.md](./Framework-Rules.md) · [TEST-CASE-DEVELOPMENT-PLAN.md](../TEST-CASE-DEVELOPMENT-PLAN.md) · [scripts/README-JIRA.md](../../scripts/README-JIRA.md)

---

## Prerequisite

**QA Review must pass** before implementation — see `@QA-Intelligence-Rules.md` → `@QA-Review-Rules.md` (Phase 0 in [TEST-CASE-DEVELOPMENT-PLAN.md](../TEST-CASE-DEVELOPMENT-PLAN.md)). Do not start Gherkin/Java on **FAIL** unless the user explicitly waives with documented risk.

## What makes this file different

| Other rule files | This file |
|------------------|-----------|
| Read Jira, choose feature type, traceability | **Build** features, steps, pages, and helpers from Jira AC |
| Prefer reuse; add glue only when dry-run fails | **Implement missing glue proactively** when AC requires it |
| Conservative on shared code | **Brave on domain code** — new pages, locators, steps, generic helpers |
| Stop at dry-run unless approved | Dry-run **then** implement until AC is covered or user gates a live run |

**Relationship:** `@Jira-Rules.md` = intake and traceability. `@Jira-Implementation-Rules.md` = end-to-end delivery from that intake. Still follow `@HappyPath-Rules.md`, `@Regression-Rules.md`, and `@Framework-Rules.md` for folder layout, tags, and layer structure.

---

## Global guardrails (apply to all work)

1. **Do not break existing suites** — search usages before changing any **existing** step, page method, or shared utility.
2. **Do not change a working workflow** without listing affected tags/features and getting user approval when impact is broad.
3. **Do not leave new code untested** — dry-run is mandatory; live `mvn test` when VPN/env allows or user approves.
4. **Read the full ticket pack first** — description, AC, comments, attachments, linked issues from `INDEX.md`.
5. **Reuse before invent** — but **do not stop** at reuse if AC still has gaps; implement what is missing.
6. **Protect shared utilities** — do not modify `FileManager`, `UserGroups`, `TestingToolOptions`, `Hooks.java`, or `CommonPageElements.java` without explicit user approval. Add domain-specific code instead.
7. **Brave, not reckless** — new code must follow existing package patterns, naming, and POM layering.
8. **User guidance at decision points** — ask when TestType is missing, env/user is unclear, or AC conflicts with existing behavior.
9. **Isolate story code on shared pages** — see `@Framework-Rules.md` § *Story-specific code must not break other workflows*. New AC → new methods/steps/tags; grep shared methods before edit; smoke at least one other domain tag when touching `LabQCPage`, `CommonPageElements`, or shared step glue.

---

## Scope

This file governs **Jira-driven implementation** of:

| Deliverable | Location |
|-------------|----------|
| New or updated `.feature` files | `src/test/resources/Features/` (domain or `Regression/` per story type) |
| New or extended step definitions | `src/test/java/stepDefinitions/` |
| New or extended page objects | `src/test/java/pages/` |
| Domain helpers / validators | `src/test/java/utilities/` or domain page classes |
| Constants (queue names, columns, test types) | `src/main/java/constants/` (with LIMS confirmation for new `TestType`) |
| Traceability | `@EXNGS-XXXX` tags, feature header comments, PR notes |

**Out of scope (unless user explicitly approves):** Jira story edits, changes to `TestRunner.java` default tags, Insight dashboard JS overhauls. **After implementation is verified**, publish Jira Test Cases via `@Jira-TestCase-Rules.md` and `scripts/jira-create-testcase.ps1`.

---

## Standard pipeline — do not reinvent

These stages are **already implemented** across domains with the same step phrases and patterns. For any Jira story whose flow includes them, **reuse existing steps verbatim** — do not duplicate or rewrite unless AC requires behavior that no existing step supports.

| Stage | Reuse (step classes) | Typical Gherkin (copy from sibling features) |
|-------|----------------------|-----------------------------------------------|
| Test data + login | `LoginSteps.java` | `Given Test Data setup for current run` + `Given user navigates to Login Page and logs in` |
| Sample generation | `CommonPageSteps.java` | `When user generates a new sample using "<sis>", "<orderFile>", "<age>" and "<gender>"` |
| Sample receiving | `SampleReceivingSteps.java` | `And user scans generated samples and completes sample receiving` |
| Intake review | `IntakeReviewStep.java` | `And user provides intake values and completes Intake review queue` |
| DNA extraction | `AutomatedDNAExtraction.java`, `ManualDNAExtraction.java` | `And user should navigate and complete DNA extraction` |
| Library prep | `LibraryPrep.java` | Plate/sample steps per domain (`LibraryPrepPlatesPage`, `LibraryPrepSamplesPage`, `LibraryPrepMBPage`) |

**Rule:** Wire new stories through these steps first. Only add new intake/receiving/extraction steps when AC documents a **domain-specific variant** (e.g. MCC-PN prenatal, Couples, Geneseq) — then extend the **existing** step class with a new phrase, mirroring sibling methods in that file.

**Rule:** Do **not** alter signatures or defaults of the standard steps above unless the Jira scope requires it **and** all grep-identified consumers are updated and dry-run.

---

## Jira intake workflow (required)

### 1. Export ticket (if not already present)

```powershell
.\scripts\jira-ticket-detail.ps1 '@EXNGS-XXXX'
```

### 2. Agent attach set (user recommendation)

```text
@Jira-Implementation-Rules.md
@target/jira-export/tickets/EXNGS-XXXX/INDEX.md
@target/jira-export/tickets/EXNGS-XXXX/attachments/   (when UI/mockups/specs exist)
@HappyPath-Rules.md or @Regression-Rules.md             (pick by story type)
@Framework-Rules.md                                     (when new Java is expected)
```

Optional: `@TestTypes.java`, sibling happy path feature, domain step/page files.

### 3. Extract implementation contract from export

From `INDEX.md` and attachments, build an internal checklist:

| Source | Extract |
|--------|---------|
| Summary + description | User story, scope boundaries |
| Acceptance criteria | **Must-have** scenarios (numbered list → scenarios or examples) |
| Comments | Clarifications, env notes, rejected approaches |
| Attachments | Column names, flags, thresholds, UI labels, file formats |
| Linked issues | Dependencies, split stories, out-of-scope work |
| Custom fields | TestType, sprint, component hints |

**Rule:** Every AC bullet must map to a scenario step, assertion, or documented gap — no silent skips.

### 4. Classify story → asset type

| Signal in Jira | Action | Rule file |
|----------------|--------|-----------|
| Full pipeline / new assay flow | Domain happy path or extend existing | `@HappyPath-Rules.md` |
| Queue UI only (buttons/columns/tabs) | Regression feature | `@Regression-Rules.md` |
| Multi TestType same flow | Domain regression outline | `@Regression-Rules.md` |
| LabQC / validation / stats table | Extend domain LabQC steps + page | This file + `@Framework-Rules.md` |
| Reporting / PDF / verbals | Reuse `Reporting.java`, `Verbals.java` | `@Reporting-Rules.md` |

---

## Implementation mindset — brave but structured

When AC is not satisfied by existing features alone, **take action** in this order:

```
1. Search  →  Features/, stepDefinitions/, pages/, constants/, utilities/
2. Reuse   →  Copy Gherkin + wire standard pipeline steps
3. Extend  →  Add method to existing domain page/step (preferred)
4. Create  →  New page object / step class / helper when no sibling fits
5. Generic →  Parameterized helper when 2+ domains share the same new pattern
6. Verify  →  Dry-run all new/changed tags + impacted sibling tags
```

### When to extend existing Java

| Situation | Action |
|-----------|--------|
| Same queue, new button/column/assertion | Add method to domain `*Page.java`; step calls it |
| Same flow, new TestType in Examples | New row in `Scenario Outline` only |
| Slight wording change in one domain | New step phrase in domain step file (duplicate pattern OK) |
| LabQC flag/threshold from Jira | Add validation method on `LabQCPage` or domain LabQC page |

### When to create new Java (allowed and expected)

| Situation | Action |
|-----------|--------|
| New work queue tab with no page class | Create `pages/<Queue><Tab>Page.java` following nearest neighbor |
| New domain with no step file | Create `stepDefinitions/<Domain>.java` extending `BaseStepDefinition` |
| AC needs reusable validation (flags, tables, JSON) | Add `utilities/<Domain>ValidationHelper.java` or page method |
| Repeated locators across scenarios | Private locators in page object; constants in `ColumnNames` / `ButtonNames` |
| Parameterized table checks | Generic method: `(tableName, column, expectedFlag, threshold)` in domain page |

### Page object pattern (mandatory for new UI code)

Follow existing files (e.g. `LabQCPage.java`, `LibraryPrepPlatesPage.java`):

```java
public class SomeDomainPage {
    private WebDriverController wdc;
    private String wqName;

    public SomeDomainPage(WebDriverController wdc, String wqName) {
        this.wdc = wdc;
        this.wqName = wqName;
    }

    public void completeQueueActionForScenario() {
        // WorkQueueManager navigation if needed
        // wdc.find / click / wait — no Gherkin strings here
    }
}
```

Steps stay thin: parse DataTable → call page → assert.

### Step definition pattern (mandatory for new glue)

```java
@Then("user validates {string} column flags per Jira spec")
public void userValidatesColumnFlags(String tableName, DataTable table) {
    // delegate to page or helper; use BaseStepDefinition context
}
```

Copy **exact** phrasing discipline from `@Framework-Rules.md` — spacing and regex matter.

### Generic / dynamic structures (use when justified)

Create parameterized helpers when Jira AC describes **rules** not one-off clicks:

| Pattern | Example |
|---------|---------|
| Flag rule table | DataTable: column, operator, threshold → loop assertions |
| Multi-metric LabQC | Map metric name → locator/validator from constants |
| Attachment-driven expected values | Parse exported xlsx/csv in test resource path for expected rows |
| Scenario Outline for AC matrix | One scenario per AC group; Examples from Jira thresholds |

**Rule:** Prefer DataTables and Examples over copy-pasted scenarios.

---

## User guidance — when to pause and ask

Ask the user before proceeding when:

| Condition | Question |
|-----------|----------|
| `TestType` not in `TestTypes.java` | Confirm code with LIMS or use closest existing type |
| AC ambiguous or conflicting with comments | Which AC version wins? |
| Requires new automation user / env | Which `login.properties` user and `-Denv=`? |
| Changes existing shared step used by 5+ features | Approve impact list and regression dry-run scope |
| Live run hits external systems (Cloverleaf, Oncohub, instruments) | Approve env and `RunUpto` |
| Story is UI-only but AC describes full pipeline | Happy path vs regression? |

**Rule:** Do **not** block on askable questions — implement everything that is clear; list assumptions and gaps in PR/team instructions.

---

## Impact review (still required)

Brave implementation **does not** skip impact search for **edits** to existing code.

| Before merge | Action |
|--------------|--------|
| Changed step phrase or Java method | `grep` all `Features/`, list every tag using it |
| Changed page method | List every step class caller |
| New constant enum value | Confirm no collision with regression column checks |
| Dry-run | New tag + `@SmokeTestSuite*` / domain regression tags sharing glue |

**Safe without approval:** New feature file, new page class, new step phrases that only new scenarios use, new utilities used only from new code.

---

## End-to-end delivery checklist

### Phase A — Understand

- [ ] Ticket exported; `INDEX.md` read
- [ ] Attachments reviewed (screenshots, xlsx, specs)
- [ ] AC mapped to scenarios (table in PR or team instructions)
- [ ] Sibling feature identified (`HappyPath*.feature`, `*Regression.feature`)
- [ ] TestType, user, env, `RunUpto` confirmed or assumed with note

### Phase B — Design

- [ ] Feature path and tags chosen (`@EXNGS-XXXX` + domain tag)
- [ ] Standard pipeline steps reused where applicable
- [ ] Gap list: new pages / steps / constants / helpers
- [ ] User consulted on ambiguities (if any)

### Phase C — Implement

- [ ] Gherkin written; header comment lists Jira key + Java touchpoints
- [ ] Page objects / steps / helpers added per patterns above
- [ ] Constants updated (no hardcoded queue/column names in regression)
- [ ] No unauthorized edits to protected shared classes

### Phase D — Verify

- [ ] Dry-run passes:
  ```powershell
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@EXNGS-XXXX" "-Dcucumber.execution.dry-run=true"
  ```
- [ ] Sibling tags dry-run if shared glue changed
- [ ] Live run status documented (run / blocked / user declined)

### Phase E — Document

- [ ] PR: Jira key, feature path, tags, TestTypes, commands, assumptions
- [ ] Update pending table in `@Jira-Rules.md` or this file's team instructions
- [ ] Gaps or follow-up stories noted

---

## Reference map — where to look first

### By Jira component / keywords

| Jira hints | Start here |
|------------|------------|
| Sample gen / SIS / order file | `CommonPageSteps.java`, `SampleAPI.java` |
| Receiving / scan | `SampleReceivingSteps.java` |
| Intake | `IntakeReviewStep.java`, `IntakeReviewPage.java` |
| Extraction manual/auto | `ManualDNAExtraction.java`, `AutomatedDNAExtraction.java` |
| Library prep | `LibraryPrep.java`, `LibraryPrep*Page.java` |
| LabQC / stats / flags | `LabQc.java`, `LabQCPage.java`, `Microbiome/*` |
| qPCR / dPCR / Sanger / RP | Domain step files (`Qpcr.java`, `Dpcr.java`, …) |
| Reporting / verbals | `Reporting.java`, `Verbals.java` |
| Plasma Complete / Oncohub | `PlasmaComplete/`, `HappyPathPlasmaComplete.feature`, `PlasmaCompleteSteps.java` |
| Plasma Complete TNP | `ManualDNAExtractionPage.tnpReport()`, `@PlasmaCompleteTnpReport` |
| MolOnc Intake Review role | `UserGroups.forIntakeReviewMolOnc()` → `OPS_ASSISTANT` in `IntakeReviewPage.init()` only |

### Standard happy path template (new domain story)

```gherkin
# Jira: EXNGS-XXXX — <summary>
# Touchpoints: <StepClass>.java, <PageClass>.java
@EXNGS-XXXX @DomainSmoke
Feature: <summary>

  Scenario Outline: <AC title>
    Given Test Data setup for current run
      | TestType | Environment | UserName | RunUpto |
      | <TYPE>   | QA          | ...      | ...     |
    Given user navigates to Login Page and logs in
    When user generates a new sample using "<sis>", "<orderFile>", "<age>" and "<gender>"
    And user scans generated samples and completes sample receiving
    And user provides intake values and completes Intake review queue
    And user should navigate and complete DNA extraction
    # --- story-specific steps below (implement bravely if missing) ---
    Then <acceptance step from AC>

    Examples:
      | sis  | orderFile | age | gender |
      | true | false     | 25  | F      |
```

---

## Validation checklist (before merge)

- [ ] All Jira AC items covered or explicitly deferred with user ack
- [ ] `@EXNGS-XXXX` on feature or scenarios
- [ ] Standard pipeline steps reused (not reimplemented) where applicable
- [ ] New Java follows page/step/constants patterns
- [ ] No credentials or tokens committed
- [ ] Dry-run passes for new/changed tags
- [ ] Impact search done for any modified existing glue
- [ ] Protected shared classes untouched unless approved
- [ ] PR lists commands, env, TestTypes, and open assumptions

---

## Team instructions (living section)

> **For automation developers:** Add implementation conventions, domain `@` references, and completed Jira mappings here.  
> **For the agent:** When the user submits instructions via `@Jira-Implementation-Rules.md`, merge requirements below and update reference tables.

### Documented example — EXNGS-3397 (Plasma Complete / Oncohub)

| AC | Automation coverage | Notes |
|----|---------------------|-------|
| Oncohub Cloverleaf receives discrete JSON from Omniseq | **Integration / manual** | No Exemplar UI; see attachments `Discrete Genomic Data Elements*.xlsx`, `Epic Variant Specifications*.xlsx` |
| Oncohub Cloverleaf builds 2.5.1 message | **Integration / manual** | Cloverleaf/Oncohub infrastructure |
| Routes message to LCA Cloverleaf for LCLS | **Integration / manual** | Related: EXNGS-3398, EXNGS-3349 |
| Exemplar full pipeline through report | `@PlasmaCompleteWorkFlow` in `HappyPathPlasmaComplete.feature` | Validates Exemplar handoff point |

| Step | Action |
|------|--------|
| 1 | `.\scripts\jira-ticket-detail.ps1 '@EXNGS-3397'` |
| 2 | Attach `@Jira-Implementation-Rules.md` + `INDEX.md` + `attachments/` xlsx files |
| 3 | Extend `HappyPathPlasmaComplete.feature` with `@EXNGS-3397` full pipeline scenario |
| 4 | Document Cloverleaf AC as integration-out-of-scope in feature header |
| 5 | Dry-run `@PlasmaCompleteWorkFlow` |

### Documented example — EXNGS-2600 (Plasma Complete TNP / failure reports)

| AC | Automation coverage | Notes |
|----|---------------------|-------|
| TNP Report from Quick Search (TestOrderModel) | `@PlasmaCompleteTnpReport` + `PlasmaCompleteSteps.java` | Team agreed: no workflow-screen TNP button (2026-07-28) |
| TSV to GO (Test, Disease, Order ID) | **Integration / manual** | Minimal demographic set per comment 2026-08-05 |
| Sample NOT closed in Exemplar on TNP | Assert toast + sample state in live run | `ManualDNAExtractionPage.tnpReport()` |
| 2x extraction failure / Original Sample Conc <25ng | **SOP / future** | Reprocess via manual extraction; extend when test data stable |
| Failure verbiage in GO | **Manual** | See `Proposed Failure Language_17JUN2026_Shak.xlsx` in ticket attachments |

| Step | Action |
|------|--------|
| 1 | `.\scripts\jira-ticket-detail.ps1 '@EXNGS-2600'` |
| 2 | Review attachments (TNP screenshots, failure language xlsx, QC Failure Report pdf) |
| 3 | Add `@PlasmaCompleteTnpReport` scenario; reuse pipeline through manual extraction |
| 4 | Wire `PlasmaCompleteSteps` → `ManualDNAExtractionPage.tnpReport()` |
| 5 | Dry-run `@PlasmaCompleteTnpReport` |

### Documented example — EXNGS-2557 (Microbiome LabQC stats)

| Step | Action |
|------|--------|
| 1 | Full ticket pack under `target/jira-export/tickets/EXNGS-2557/` |
| 2 | Reuse `HappyPathMB.feature` through LabQC; extend `LabQc.java` / `LabQCPage.java` |
| 3 | Map each AC flag to column + threshold (red dot, numeric bounds from AC) |
| 4 | Prefer regression feature or happy path extension per `@Regression-Rules.md` |
| 5 | Generic table validator if multiple metrics share flag logic |

### Active team instructions

<!-- Append new instructions below -->

#### 2026-08-12 — MolOnc Intake Review user group pattern

- **First domain-specific intake role resolver:** `UserGroups.forIntakeReviewMolOnc(testType, testFamily, labLocation)`.
- **Returns:** `OPS_ASSISTANT` for MolOnc / Plasma Complete intake; `null` otherwise (legacy `init()` branches unchanged).
- **Do not** add site-specific MolOnc enum values — use generic groups per `UserGroups.java` comment block.
- **Extend pattern:** new intake-only roles → add resolver method + single call site in `IntakeReviewPage.init()`; do not scatter intake role logic across page objects.

#### 2026-08-12 — Plasma Complete implementation (EXNGS-2600 + EXNGS-3397)

- **Tickets:** `target/jira-export/tickets/EXNGS-2600/`, `EXNGS-3397/` (attachments included)
- **Feature:** `HappyPathPlasmaComplete.feature` — two scenarios + shared Background
- **Java:** `PlasmaCompleteSteps.java` (TNP quick search step; Plasma Complete Library Prep Qubit/TapeStation step)
- **Integration-only AC:** Cloverleaf JSON/2.5.1 routing (3397); GO TSV drop (2600) — documented in feature header, not UI-automated
- **Dry-run:**
  ```powershell
  mvn test "-Denv=dev" "-Dcucumber.filter.tags=@PlasmaCompleteSmoke" "-Dcucumber.execution.dry-run=true"
  ```

#### 2026-08-12 — Jira Implementation Rules created

- **Purpose:** Jira export → working automation with permission to add pages, steps, helpers when AC requires it.
- **Intake:** `@Jira-Implementation-Rules.md` + `@target/jira-export/tickets/<KEY>/INDEX.md`.
- **Standard pipeline:** sample generation, receiving, intake, DNA extraction, library prep — reuse existing steps; do not break.
- **Brave scope:** new domain pages, locators, step defs, generic validators — follow `@Framework-Rules.md` layering.
- **Gate live runs:** user approval for QA/DEV execution and missing TestType confirmation.

### Pending / requested

| Jira | Request | Status | Notes |
|------|---------|--------|-------|
| EXNGS-2557 | Microbiome LabQC Sample Stats automation | **Done** | `@MBLabQCSampleStats` in HappyPathMB.feature; TC [EXNGS-3994](https://jira.labcorp.com/browse/EXNGS-3994) |
| EXNGS-3397 | Plasma Complete Oncohub Cloverleaf JSON | **Happy path updated** | UI: `@PlasmaCompleteWorkFlow`; Cloverleaf AC integration/manual |
| EXNGS-2600 | Plasma Complete TNP Report generation | **Happy path updated** | UI: `@PlasmaCompleteTnpReport`; GO TSV integration/manual |
| EXNGS-4000 | Plasma Complete LabQC Data Analyst permissions | **Done** | `@EXNGS-4000` in `PlasmaCompleteLabQCRegression.feature`; TC via catalog |

---

## Example agent invocation

```text
@Jira-Implementation-Rules.md
@target/jira-export/tickets/EXNGS-2557/INDEX.md
@Regression-Rules.md
@Framework-Rules.md

Implement test automation for all acceptance criteria in the exported ticket.
Reuse standard sample/receiving/intake/extraction steps.
Extend LabQC pages/steps for new Sample Stats flags; add new glue if dry-run requires it.
Use Mb-prefixed methods + @MBLabQCSampleStats only — do not modify completeSampleStatsStep / happyPath used by BRCA.
grep LabQCPage method usages; dry-run @BRCAWorkFlow after LabQC edits.
Dry-run @EXNGS-2557; do not run QA live until I approve.
Update pending table when done.

# Jira Rules

> **How to use:** In Cursor agent chat, attach `@Jira-Rules.md` plus your specific request (include Jira key, e.g. `@EXNGS-2557`).  
> The agent must follow every rule below, pull story context when possible, create/update test assets, and **append durable updates** to [Team instructions](#team-instructions-living-section).

**Related docs:** [QA-Intelligence-Rules.md](./QA-Intelligence-Rules.md) · [QA-Review-Rules.md](./QA-Review-Rules.md) · [JIRA-READONLY-ACCESS.md](../JIRA-READONLY-ACCESS.md) · [scripts/README-JIRA.md](../../scripts/README-JIRA.md) · [TEST-CASE-DEVELOPMENT-PLAN.md](../TEST-CASE-DEVELOPMENT-PLAN.md) · [HappyPath-Rules.md](./HappyPath-Rules.md) · [Regression-Rules.md](./Regression-Rules.md) · [Jira-Implementation-Rules.md](./Jira-Implementation-Rules.md) · [Jira-TestCase-Rules.md](./Jira-TestCase-Rules.md)

---

## Global guardrails (apply to all work)

1. **Do not break existing rules** — Jira scripts are read-only; never commit tokens or credentials.
2. **Do not change a working workflow** without explicit user approval (especially adding Jira write/update automation).
3. **Do not leave new test assets untested** — after creating features from a story, dry-run at minimum.
4. **Read before write** — always fetch story acceptance criteria before authoring Gherkin.
5. **Traceability** — every story-driven feature gets the Jira key in tag and/or feature header comment.
6. **Trace impact before you edit** — when a Jira story requires changing existing glue, page methods, or features, search the full framework for usages and confirm no unrelated flow breaks.
7. **Protect shared utilities** — do not modify `FileManager`, `UserGroups`, `TestingToolOptions`, or `Hooks.java` to implement a story; prefer domain-specific code or explicit approval.
8. **No duplicate/overload behavior** — do not change shared method signatures or defaults in ways that affect scenarios outside the Jira scope.

---

## Scope

This file governs:

| Area | Current capability |
|------|-------------------|
| **Read Jira** | `scripts/jira-read.ps1`, `scripts/jira-pull-stories.ps1`, **`scripts/jira-ticket-detail.ps1`** (read-only) |
| **Story → test design** | Map acceptance criteria to happy path, regression, or unit feature |
| **Traceability** | `@EXNGS-XXXX` tags, feature headers, PR descriptions |
| **Write Jira** | **Test Case create + link only** — `scripts/jira-create-testcase.ps1 -Create` (see `@Jira-TestCase-Rules.md`); stories remain read-only |

---

## Must-follow rules

### Credentials and security

| Rule | Detail |
|------|--------|
| Credentials file | Copy `scripts/.jira.local.env.example` → `scripts/.jira.local.env` (gitignored) |
| Variables | `JIRA_EMAIL`, `JIRA_API_TOKEN` |
| Never commit | Tokens, passwords, or PATs in features, Java, or docs |
| VPN | Required for `jira.labcorp.com` in most environments |

### Reading stories (agent workflow)

When user provides a Jira key, run from repo root:

```powershell
# Full ticket pack (description, comments, attachments, custom fields) — preferred for agent intake
.\scripts\jira-ticket-detail.ps1 '@EXNGS-2557'

# Single story summary (console + timestamped read/*.md)
.\scripts\jira-read.ps1 '@EXNGS-2557'

# Multiple stories
.\scripts\jira-read.ps1 -TicketKeys EXNGS-2557,EXNGS-2962

# Latest backlog scan
.\scripts\jira-read.ps1 -Latest 10
```

**Output** (gitignored): `target/jira-export/tickets/<KEY>/` (detail script) or `target/jira-export/read/*.md` and `*.json` (read script)

Use **`target/jira-export/tickets/<KEY>/INDEX.md`** for full acceptance criteria, comments, and attachment paths; use `jira-read.ps1` exports for quick scans or multi-ticket lists.

### Bulk export (analysis only)

```powershell
.\scripts\jira-pull-stories.ps1 -Project EXNGS -MaxResults 200
.\scripts\jira-pull-stories.ps1 -Project EXNGS -MbOnly -MaxResults 200
```

Output: `target/jira-export/jira-*.json`

### Story → test asset decision tree

| Story type | Create / update | Rule file |
|------------|-----------------|-----------|
| Full pipeline / workflow change | Happy path or Reporting E2E feature | `@HappyPath-Rules.md` |
| UI-only change in one queue | Regression feature | `@Regression-Rules.md` |
| Multiple TestTypes, same flow | Domain regression (e.g. `FraxRegression`) | `@Regression-Rules.md` |
| Single button/column check | `Features/UnitTest/` | `@Framework-Rules.md` |
| New step glue or page object | Java in `stepDefinitions/` / `pages/` | `@Framework-Rules.md` |
| **Implement full story from export** | Features + steps + pages + helpers from AC | **`@Jira-Implementation-Rules.md`** |
| Reporting / Insight needs | Add `@InsightReport` | `@Reporting-Rules.md` |

### Impact review when implementing from Jira

Stories often request changes to **existing** features or shared glue. Before writing or editing Gherkin/Java:

| Step | Action |
|------|--------|
| 1 | Identify whether the story needs **new** scenarios only, or changes to **existing** steps/page methods. |
| 2 | If existing code changes: grep `Features/`, `stepDefinitions/`, `pages/`, and `utilities/` for every usage. |
| 3 | Confirm parameters (DataTables, `TestType`, queue names) remain valid for all consumers — not only the Jira-scoped feature. |
| 4 | **Do not** edit `FileManager`, `UserGroups`, `TestingToolOptions`, or `Hooks.java` unless the user explicitly approves and impact is documented. |
| 5 | Prefer a new domain-specific page method or step over modifying shared utilities or `CommonPageElements`. |
| 6 | Document affected tags and sibling features in the PR (happy path, regression, unit, smoke suites). |

**Rule:** A Jira story is **not** justification alone to change shared framework code — scope must stay within the story's domain or receive explicit approval.

### QA Intelligence gate (before intake design)

For new stories or material changes, run **`@QA-Intelligence-Rules.md`** then **`@QA-Review-Rules.md`** before this checklist. See [TEST-CASE-DEVELOPMENT-PLAN.md](../TEST-CASE-DEVELOPMENT-PLAN.md) Phase 0.

### Jira intake checklist (per story)

Before writing Gherkin, confirm:

- [ ] Story key, summary, status, assignee read from export
- [ ] Acceptance criteria extracted (description section)
- [ ] **TestType** exists in `constants/TestTypes.java` (or flag for LIMS team)
- [ ] Work queues identified (`constants/WQItems.java`, [PROJECT-MASTER-DIAGRAM.md](../PROJECT-MASTER-DIAGRAM.md))
- [ ] Similar existing feature found (search `Features/` first)
- [ ] Test type chosen: happy path vs regression vs unit
- [ ] Environment and user from `login.properties`
- [ ] Tags planned: domain smoke/workflow + `@EXNGS-XXXX`
- [ ] Dry-run command documented
- [ ] Story scope classified: **new scenarios only** vs **changes to existing** steps/page methods
- [ ] If existing code changes: full-framework grep completed; all call sites listed
- [ ] Parameters and DataTables verified compatible for every consumer
- [ ] No edits to `FileManager`, `UserGroups`, `TestingToolOptions`, or `Hooks.java` unless explicitly approved
- [ ] PR documents affected tags, sibling features, and smoke/regression suites

### Traceability conventions

**Feature header comment:**

```gherkin
# Jira: EXNGS-2557 — Microbiome LabQC Sample Stats validation
# Related: HappyPathMB.feature, LabQc.java, LabQCPage.java
```

**Scenario / feature tag:**

```gherkin
@EXNGS-2557 @MBLabQC
Feature: Microbiome LabQC Sample Stats validation
```

**PR description must include:** Jira key, feature path, tags, TestType(s), env used, dry-run/live run status.

### Writing to Jira (restrictions)

| Action | Allowed? | How |
|--------|----------|-----|
| Read issues | Yes | `jira-read.ps1`, `jira-pull-stories.ps1` |
| Create/update issues | **No (default)** | User performs manually in Jira UI |
| Post test results to Jira | **No (default)** | Not implemented — requires explicit approval to add |
| Add automation scripts that write | **Requires approval** | Security + workflow review before any write API |

**Rule:** If user asks to "update Jira", prepare markdown summary for manual paste unless write automation is explicitly approved and implemented.

---

## Reference map

### Scripts

| Script | Purpose |
|--------|---------|
| **`scripts/jira-ticket-detail.ps1`** | **One ticket, full pack** — INDEX.md, JSON, comments, downloaded attachments |
| `scripts/jira-read.ps1` | Single/multi ticket summary, latest N, `.md` + `.json` under `read/` |
| `scripts/jira-pull-stories.ps1` | Bulk JSON export, `-MbOnly` filter |
| `scripts/jira-common.ps1` | Shared API helpers (dot-sourced) |
| `scripts/.jira.local.env.example` | Credentials template |

### Story → feature exemplars

| Jira context | Start from | Output |
|--------------|------------|--------|
| FRAX multi test type | `HappyPathFrax.feature` | `Regression/FraxRegression.feature` |
| FRAX RP UI only | `RPFraxRegression.feature` | Queue regression scenarios |
| MB LabQC stats | `HappyPathMB.feature` | Regression or happy path extension |
| INH-100 reporting | `INH100HappyPath.feature` | Domain happy path |
| New queue UI matrix | Sibling `*Regression.feature` | `Features/Regression/{Queue}Regression.feature` |

### Test design fields (document in PR or team instructions)

| Field | Example |
|-------|---------|
| Feature path | `Features/Regression/MicrobiomeLabQCRegression.feature` |
| Tags | `@mbLabQcRegression`, `@EXNGS-2557` |
| TestType | `MCB-CORE` |
| NoOfSamples | `1` |
| Environment | `QA` |
| UserName | `automationuser_mb1` |
| RunUpto | `LabQC` or `Verbals` |
| Maven command | `mvn test "-Denv=qa" "-Dcucumber.filter.tags=@mbLabQcRegression"` |

### Default JQL (list mode)

```text
project = "EXNGS" AND issuetype in (Story, Epic, Task, Bug, "Test Case", Requirement)
ORDER BY created DESC
```

---

## Validation checklist (before merge)

- [ ] Jira story read and acceptance criteria addressed in scenarios
- [ ] `@EXNGS-XXXX` tag or header comment on feature
- [ ] Correct rule file patterns followed (happy path vs regression)
- [ ] No credentials in committed files
- [ ] Dry-run passes for new/changed scenarios
- [ ] PR lists Jira key, tags, TestTypes, run commands
- [ ] Pending table in this file or sibling rule file updated if story completes a gap
- [ ] **Impact search done** if existing glue or features were modified
- [ ] **Shared utils and Hooks untouched** unless explicitly approved

---

## Team instructions (living section)

> **For automation developers:** Add new rules, `@` file references, and acceptance criteria here.  
> **For the agent:** When the user submits instructions via `@Jira-Rules.md`, merge requirements into this section and update pending/reference tables.

### Documented example — EXNGS-2557 intake

**Request:** Create test coverage for Microbiome LabQC Sample Stats.

| Step | Action |
|------|--------|
| 1 | `.\scripts\jira-ticket-detail.ps1 '@EXNGS-2557'` (or `jira-read.ps1` for a quick pull) |
| 2 | Read acceptance criteria from `target/jira-export/tickets/EXNGS-2557/INDEX.md` |
| 3 | Reuse `HappyPathMB.feature` LabQC steps, `LabQc.java`, `LabQCPage.java` |
| 4 | Decide: extend happy path **or** new `MicrobiomeLabQCRegression.feature` |
| 5 | Tag `@EXNGS-2557`; dry-run; update pending table |

### Active team instructions

<!-- Append new instructions below -->

#### 2026-08-10 — Single-ticket full export (`jira-ticket-detail.ps1`)

- **Use when:** one Jira key needs full context (AC, comments, screenshots, linked issues, custom fields).
- **Command:** `.\scripts\jira-ticket-detail.ps1 '@EXNGS-XXXX'`
- **Output folder:** `target/jira-export/tickets/<KEY>/` (stable path; re-run refreshes).
- **Agent attach:** `@Jira-Rules.md` + `@target/jira-export/tickets/<KEY>/INDEX.md`
- **Full implementation:** add `@Jira-Implementation-Rules.md` when the user wants features/steps/pages built from the export
- **Options:** `-SkipAttachments`, `-IncludeSubtasks`, `-JsonOnly`

#### 2026-07-29 — Jira-driven changes must not break shared framework

- Classify every story as new scenarios vs edits to existing glue before coding.
- Full-framework usage search required when changing existing steps, page methods, or parameters.
- Do not modify `FileManager`, `UserGroups`, `TestingToolOptions`, or `Hooks.java` without explicit approval.

### Pending / requested

| Jira | Request | Status | Target rule file |
|------|---------|--------|------------------|
| EXNGS-2557 | Microbiome LabQC Sample Stats test coverage | **Done** | `@MBLabQCSampleStats`; Jira TC EXNGS-3994 |
| EXNGS-3397 | Plasma Complete Oncohub Cloverleaf JSON | Automation + Jira Test [EXNGS-3919](https://jira.labcorp.com/browse/EXNGS-3919) | `@PlasmaCompleteWorkFlow` |
| EXNGS-2600 | Plasma Complete TNP Report | Automation + Jira Test [EXNGS-3920](https://jira.labcorp.com/browse/EXNGS-3920) | `@PlasmaCompleteTnpReport` |

---

## Example agent invocation

```
@Jira-Rules.md

Read EXNGS-2557 with full ticket pack:
  .\scripts\jira-ticket-detail.ps1 '@EXNGS-2557'
Then use @target/jira-export/tickets/EXNGS-2557/INDEX.md for acceptance criteria.
Create Microbiome LabQC regression scenarios. Reference @TestTypes.java MCB-CORE.
Dry-run only unless I approve QA run. Update pending table when done.
```
# Happy Path Rules

> **How to use:** In Cursor agent chat, attach `@HappyPath-Rules.md` plus your specific request.  
> The agent must follow every rule below, validate changes, run tests, and **append durable updates** to [Team instructions](#team-instructions-living-section) when you add new conventions or file references.

**Related docs:** [README.md](./README.md) · [TEST-CASE-DEVELOPMENT-PLAN.md](../TEST-CASE-DEVELOPMENT-PLAN.md) · [Regression-Rules.md](./Regression-Rules.md) · [Reporting-Rules.md](./Reporting-Rules.md) · [Jira-Rules.md](./Jira-Rules.md) · [Framework-Rules.md](./Framework-Rules.md)

---

## Global guardrails (apply to all work)

1. **Do not break existing rules** — preserve smoke suite tags, domain folders, default `TestRunner` behavior, and pipeline step order.
2. **Do not change a working workflow** without explicit user approval, cross-suite impact review, and consistent updates to all related files.
3. **Do not leave updated code untested** — dry-run for step binding; targeted smoke run when approved and env available.
4. **Reuse existing steps** — happy paths compose domain step classes; avoid new glue unless no step matches.
5. **Best practices** — `Scenario Outline` + `Examples`, realistic test data, stop at `RunUpto` when partial coverage is enough.
6. **Trace impact before you edit** — when a feature change requires updating shared glue or page methods, search all usages across `Features/` and confirm no other happy path, smoke suite, or regression flow breaks.
7. **Protect shared utilities** — do not modify `FileManager`, `UserGroups`, `TestingToolOptions`, or other cross-domain utils for one domain; add domain-specific code instead.
8. **Do not touch `Hooks.java`** without explicit approval — happy paths depend on per-scenario driver lifecycle defined there.

---

## Scope

This file governs **happy path / smoke / workflow** scenarios in **domain folders** (not `Features/Regression/`).

```
src/test/resources/Features/
├── INHFeatures/           # FRAX, INH-100/500, SMA, MCC, Couples, Sickle, Gel
├── INHFeatures/ReportingE2E/
├── BRCA/
├── Microbiome/
├── Myeloid/
├── AlphaThal/
├── PlasmaComplete/
├── RepeatExpansion/
├── BulkRun/
└── Database/
```

**Queue UI matrix tests** belong in `Regression/` per [Regression-Rules.md](./Regression-Rules.md).

---

## Must-follow rules

### Folder placement

| Product / assay | Folder | Happy path file pattern |
|---------------|--------|-------------------------|
| FRAX | `INHFeatures/` | `HappyPathFrax.feature` |
| INH-500 | `INHFeatures/` | `HappyPathINH500.feature` |
| INH-100 | `INHFeatures/` | `INH100HappyPath.feature` |
| SMA | `INHFeatures/` | `HappyPathSMA.feature` |
| Couples | `INHFeatures/` | `HappyPathCouples*.feature` |
| MCC | `INHFeatures/` | `HappyPathMCC.feature` |
| Sickle | `INHFeatures/` | `HappyPathSICKEL.feature` |
| Gel | `INHFeatures/` | `GelHappyPath.feature` |
| BRCA | `BRCA/` | `HappyPathBRCA.feature` |
| Microbiome | `Microbiome/` | `HappyPathMB.feature` |
| Myeloid | `Myeloid/` | `HappyPathHemeLymp.feature` |
| Alpha-Thal | `AlphaThal/` | `HappyPathALPHATHAL.feature` |
| Plasma Complete | `PlasmaComplete/` | `HappyPathPlasmaComplete.feature` |

**Plasma Complete Jira traceability (2026-08-12):**

| Jira | Scenario tag | Scope |
|------|--------------|-------|
| EXNGS-3397 | `@PlasmaCompleteWorkFlow` | Full pipeline through report/verbals (Exemplar handoff before Oncohub Cloverleaf JSON) |
| EXNGS-2600 | `@PlasmaCompleteTnpReport` | TNP Report from Test Order quick search after manual extraction |

**Intake Review user group (MolOnc / PLASCOM):** `UserGroups.forIntakeReviewMolOnc()` switches to generic **Ops Assistant** at Intake Review only (`IntakeReviewPage.init()`). Applies to `PCOMP-PC`, `PLASCOM` test family, and `EXETW` (MolOnc) lab location. Other queues keep their existing role rules.

**Intake Review clinical indicator (Plasma Complete):** Use **`Acantholytic Acanthoma`** (`ClinicalIndicator.ACANTHOLYTIC_ACANTHOMA`, PLASCOM only). PLASCOM uses dedicated `selectPlasmaCompleteClinicalIndicator()` — opens dropdown, **waits for options**, types **once**, clicks list item, then `TAB`. FRAX/INH/MCC unchanged.

Ticket exports: `target/jira-export/tickets/EXNGS-3397/`, `EXNGS-2600/` (attachments: Epic Variant xlsx, Discrete Genomic Data xlsx, TNP screenshots, Proposed Failure Language xlsx).
| Repeat Expansion | `RepeatExpansion/` | `HappyPathRepeatExpansion.feature` |
| Reporting E2E | `INHFeatures/ReportingE2E/` | Domain-specific reporting features |

### Tag conventions

| Level | Pattern | Examples |
|-------|---------|----------|
| Feature smoke | `@DomainSmoke` | `@BRCASmoke`, `@MBSmoke`, `@INH500Smoke`, `@happyPathFraxSmokeTest` |
| Scenario workflow | `@DomainWorkFlow` | `@MBWorkFlow`, `@BRCAWorkFlow`, `@INH100WorkFlow` |
| Nightly batch | `@SmokeTestSuite1` … `@SmokeTestSuite7` | Suite groupings for CI batches |
| Insight (optional) | `@InsightReport` | Feature or scenario level — see [Reporting-Rules.md](./Reporting-Rules.md) |
| Jira traceability | `@EXNGS-XXXX` | Adopt on new features |

**Note:** Only FRAX uses the `@happyPath*` prefix (`@happyPathFraxSmokeTest`). Other domains use `@DomainSmoke` pattern.

### Scenario template (required start)

Every happy path begins with:

```gherkin
Given Test Data setup for current run
  | TestType   | Environment | UserName            | ... |
  | <TestType> | QA          | automationuser_...  | ... |
Given user navigates to Login Page and logs in
```

Handled by `LoginSteps.testDataSetupForScenario()` → `BaseStepDefinition.initializeTestData()`.

### Impact review when changing features or shared glue

Happy paths **compose** steps from many domain classes (`FraxSteps`, `LibraryPrep`, `Reporting`, etc.). Editing one feature often tempts changes to shared glue — treat that as high risk.

| Rule | Detail |
|------|--------|
| **Search before edit** | If you change an existing step phrase or Java method, grep `Features/` and `stepDefinitions/` for every consumer — not only the file you are working on. |
| **Parameters stay compatible** | DataTable columns, `TestType`, `RunUpto`, and method arguments must remain valid for **all** scenarios that call the same step. |
| **No silent behavior changes** | Do not overload or override a shared method so it works for your feature but breaks `@SmokeTestSuite*` siblings. |
| **Shared utils off limits** | Do not change `FileManager`, `UserGroups`, `TestingToolOptions`, `WebDriverController`, or `Hooks.java` to satisfy one happy path — ask for a domain-specific helper or explicit approval. |
| **Dry-run sibling tags** | After changes, dry-run the edited tag **and** related smoke suite tags (see smoke suite batch map below). |

**Example:** Changing a `LibraryPrep` step used by BRCA, Myeloid, and INH-500 requires verifying all three happy paths and any regression files that reuse the same glue.

### Test data rules

| Column | Rule |
|--------|------|
| `TestType` | Must exist in `TestTypes.java` |
| `Environment` | `QA`, `DEV`, `uat` — matches `login.properties` |
| `UserName` | Assay-specific automation user from properties |
| `NoOfSamples` | Match TestType expectations (e.g. FRAX-DX = 2) |
| `RunUpto` | Default `Verbals`; shorten for partial tests |
| `ExtractionType` | `Manual` for `-PN` types when applicable |

### Browser session

- Happy paths use a **fresh browser per scenario** (not shared regression mode).
- Features under `Features/Regression/` are excluded — see [Regression-Rules.md](./Regression-Rules.md).

### Execution

Default `TestRunner` tags (do not change without approval):

```java
tags = "@happyPathFraxSmokeTest and @InsightReport"
```

Override at runtime:

```powershell
# FRAX smoke + Insight
mvn test "-Denv=qa" "-Dcucumber.filter.tags=@happyPathFraxSmokeTest and @InsightReport"

# Domain smoke without Insight
mvn test "-Denv=qa" "-Dcucumber.filter.tags=@MBSmoke and not @InsightReport"

# Smoke suite batch
mvn test "-Denv=qa" "-Dcucumber.filter.tags=@SmokeTestSuite1"
```

---

## Reference map

### Happy path feature inventory

| File | Feature tags | Scenario tag(s) | TestType |
|------|--------------|-----------------|----------|
| `INHFeatures/HappyPathFrax.feature` | `@SmokeTestSuite4`, `@InsightReport` | `@happyPathFraxSmokeTest` | `FRAX-CARR` |
| `INHFeatures/HappyPathINH500.feature` | `@INH500Smoke`, `@SmokeTestSuite3` | `@INH500WorkFlow` | `INH-500` |
| `INHFeatures/HappyPathSMA.feature` | `@smaSmoke` | `@smaWorkflow` | `SMA` |
| `INHFeatures/HappyPathMCC.feature` | `@MCCSmoke` | `@MCCWorkflow` | `MCC-PN`, `MCC` |
| `INHFeatures/HappyPathSICKEL.feature` | `@SickleSmoke`, `@SmokeTestSuite7` | `@SickleWorkFlow` | `SICKLE` |
| `INHFeatures/HappyPathCouples.feature` | `@CouplesSmoke` | multiple `@CouplesWorkflow*` | `INH-500,PARTNR-REPRO` |
| `INHFeatures/HappyPathCouplesWithPosNgs.feature` | `@CouplesSmoke` | `@CouplesWorkflow*` | couples variants |
| `INHFeatures/HappyPathCouplesWithNegNgs.feature` | `@CouplesSmoke` | `@CouplesWorkflow*` | couples variants |
| `INHFeatures/GelHappyPath.feature` | — | `@GEL` | `Gel` |
| `INHFeatures/INH100HappyPath.feature` | `@INH100Smoke` | `@INH100WorkFlow` | `INH-100` |
| `INHFeatures/SMAPNwithMCCHappyPath.feature` | `@PrenatalSmoke`, `@SmokeTestSuite4` | — | `SMA-PN` + `MCC` |
| `BRCA/HappyPathBRCA.feature` | `@BRCASmoke`, `@SmokeTestSuite2` | `@BRCAWorkFlow` | `BRCA-COMP` |
| `Microbiome/HappyPathMB.feature` | `@MBSmoke`, `@SmokeTestSuite1` | `@MBWorkFlow` | `MCB-CORE` |
| `Myeloid/HappyPathHemeLymp.feature` | `@MyeloidLympSmoke` | `@PositiveWorkFlow`, `@NegativeWorkFlow`, … | `HEME-LYMP` |
| `AlphaThal/HappyPathALPHATHAL.feature` | `@ALPHATHALSmoke`, `@SmokeTestSuite6` | `@ALPHATHALWorkFlow` | `ALPHA-THAL` |
| `PlasmaComplete/HappyPathPlasmaComplete.feature` | `@PlasmaCompleteSmoke`, `@EXNGS-3397`, `@EXNGS-2600` | `@PlasmaCompleteWorkFlow`, `@PlasmaCompleteTnpReport` | `PCOMP-PC` |
| `RepeatExpansion/HappyPathRepeatExpansion.feature` | `@RepeatExpansionSmoke` | `@RepeatExpansionWorkFlow`, … | `RE-FXN`, `RE-FXN-PN` |

### Smoke suite batch map

| Tag | Features |
|-----|----------|
| `@SmokeTestSuite1` | Microbiome `HappyPathMB` |
| `@SmokeTestSuite2` | BRCA `HappyPathBRCA` |
| `@SmokeTestSuite3` | INH-500 `HappyPathINH500` |
| `@SmokeTestSuite4` | FRAX `HappyPathFrax`, SMA-PN+MCC |
| `@SmokeTestSuite5` | Myeloid positive |
| `@SmokeTestSuite6` | Alpha-Thal |
| `@SmokeTestSuite7` | Sickle |

### Step classes by domain

| Domain | Key step classes | Key page objects |
|--------|------------------|------------------|
| **Shared** | `LoginSteps`, `SampleReceivingSteps`, `IntakeReviewStep`, `Reporting`, `Verbals`, `CommonPageSteps` | `LoginPage`, `ReportingPage`, `PDFValidationsPage` |
| **FRAX** | `FraxSteps`, `RPFrax` | `FragmentAnalysisPage`, `ResultProcessingFrax` |
| **INH-500** | `Qpcr`, `LibraryPrep`, `Sequencing`, `LabQc`, `MLPA`, `LCG`, `GEL`, `Sanger`, `RPAnalyst`, `RPVariant` | Queue-specific `*Page.java` |
| **SMA** | `Qpcr`, `Dpcr`, `Sanger`, `RPSMA`, `MCC` | `ResultProcessingSma`, `DpcrSamplesPage` |
| **BRCA** | `LibraryPrep`, `Sequencing`, `LabQc`, `Sanger`, `MLPA`, `RPVariant` | `LibraryPrepV2Page`, `LabQCPage` |
| **Microbiome** | `AutomatedDNAExtraction`, `LibraryPrep`, `Sequencing`, `LabQc` | `LibraryPrepMBPage`, `LabQCPage` |
| **Myeloid** | `LibraryPrep`, `Sequencing`, `LabQc`, `DMLPA`, `Sanger`, `RPVariant` | `DMLPASamplePage`, `LabQCPage` |
| **Plasma Complete** | `PlasmaCompleteSteps`, `LibraryPrep`, `Sequencing`, `LabQc`, `RPAnalyst`, `RPVariant`, `Reporting`, `Verbals` | `ManualDNAExtractionPage`, `LibraryPrepPlatesPage`, `LabQCPage`, `ReportingPage` |

### Core constants and config

| Reference | Path |
|-----------|------|
| Test types | `src/main/java/constants/TestTypes.java` |
| Work queues | `src/main/java/constants/WQItems.java` |
| Env URLs / users | `src/test/resources/login.properties` |
| Test runner | `src/test/java/runners/TestRunner.java` |
| Test data init | `stepDefinitions/BaseStepDefinition.java` |

---

## Happy path vs regression (decision)

| Question | Happy path | Regression |
|----------|------------|------------|
| Full pipeline to report? | Yes | Rarely (except `FraxRegression`) |
| UI-only queue checks? | No | Yes |
| Folder | Domain folder | `Features/Regression/` |
| Browser | Fresh per scenario | Shared |
| Multi TestType in one file? | Usually one primary type | Common (`FraxRegression`) |

---

## Validation checklist (before merge)

- [ ] Feature is in correct **domain folder** (not `Regression/` unless approved domain regression)
- [ ] Smoke + workflow tags applied consistently with siblings
- [ ] `TestType` exists in `TestTypes.java`
- [ ] `Test Data setup` table has valid env and user
- [ ] Steps reuse existing glue (no duplicate step defs)
- [ ] Dry-run passes for new/changed scenarios
- [ ] `TestRunner` default tags unchanged unless explicitly requested
- [ ] Jira key in header/tag if story-driven
- [ ] Runtime Maven command documented
- [ ] **Impact search done** — all call sites of changed steps/methods reviewed; sibling smoke suites listed
- [ ] **Shared utils and Hooks untouched** unless explicitly approved

---

## Team instructions (living section)

> **For automation developers:** Add new rules, `@` file references, and acceptance criteria here.  
> **For the agent:** When the user submits instructions via `@HappyPath-Rules.md`, merge requirements into this section.

### Documented example — FRAX happy path (reference)

| Item | Reference |
|------|-----------|
| Feature | `Features/INHFeatures/HappyPathFrax.feature` |
| Tags | `@SmokeTestSuite4`, `@InsightReport`, `@happyPathFraxSmokeTest` |
| TestType | `FRAX-CARR` |
| Steps | `FraxSteps.java`, `RPFrax.java`, `Reporting.java` |
| Run | `mvn test "-Denv=qa" "-Dcucumber.filter.tags=@happyPathFraxSmokeTest and @InsightReport"` |

### Active team instructions

<!-- Append new instructions below -->

#### 2026-08-12 — MolOnc Intake Review user group (Ops Assistant)

- **Scope:** Intake Review only — `IntakeReviewPage.init()` calls `UserGroups.forIntakeReviewMolOnc(...)`.
- **Applies when:** `PCOMP-PC`, test family `PLASCOM`, or lab location `EXETW` (MolOnc).
- **Role:** generic `UserGroups.OPS_ASSISTANT` (`Ops Assistant`) — not site-prefixed MolOnc roles (deactivated).
- **Unchanged:** all other lab/test branches in `init()`; other queues still use their own `changeUserGroup` calls.

#### 2026-08-12 — Plasma Complete happy path (EXNGS-2600, EXNGS-3397)

- **Feature:** `Features/PlasmaComplete/HappyPathPlasmaComplete.feature`
- **Jira exports:** `target/jira-export/tickets/EXNGS-2600/`, `EXNGS-3397/` (with attachments)
- **Scenarios:**
  - `@PlasmaCompleteWorkFlow` — full pipeline through verbals (`EXNGS-3397` Exemplar scope; Cloverleaf JSON routing is integration)
  - `@PlasmaCompleteTnpReport` — TNP Report via Test Order quick search after manual extraction (`EXNGS-2600`)
- **New glue:** `PlasmaCompleteSteps.java` → `ManualDNAExtractionPage.tnpReport()`
- **Run:**
  ```powershell
  mvn test "-Denv=dev" "-Dcucumber.filter.tags=@PlasmaCompleteWorkFlow"
  mvn test "-Denv=dev" "-Dcucumber.filter.tags=@PlasmaCompleteTnpReport"
  ```
- **Out of UI scope:** Oncohub Cloverleaf 2.5.1 message build/route (3397 AC2-3); GO TSV demographic file drop (2600) — document in PR; validate via integration/manual.

#### 2026-07-29 — Cross-suite impact on happy path edits

- Changing shared glue or page methods requires grep across **all** domain folders and smoke suite tags before merge.
- Do not modify `FileManager`, `UserGroups`, `TestingToolOptions`, or `Hooks.java` for a single happy path without approval.

### Pending / requested

| Jira | Request | Status |
|------|---------|--------|
| EXNGS-2557 | Extend MB happy path for Sample Stats flags | **Done** | `@MBLabQCSampleStats` — LabQCPage EXNGS-2557 validators |
| EXNGS-3397 | Plasma Complete Oncohub Cloverleaf JSON | Happy path updated — integration AC manual |
| EXNGS-2600 | Plasma Complete TNP Report generation | Happy path TNP scenario added |

---

## Example agent invocation

```
@HappyPath-Rules.md

Add LabQC Sample Stats validation to HappyPathMB for EXNGS-2557 acceptance criteria.
Reuse LabQc steps and LabQCPage. TestType MCB-CORE. Dry-run first.
```
# Regression Rules

> **How to use:** In Cursor agent chat, attach `@Regression-Rules.md` plus your specific request.  
> The agent must follow every rule below, validate changes, run tests, and **append durable updates** to [Team instructions](#team-instructions-living-section) when you add new conventions or file references.

**Related docs:** [README.md](./README.md) · [TEST-CASE-DEVELOPMENT-PLAN.md](../TEST-CASE-DEVELOPMENT-PLAN.md) · [HappyPath-Rules.md](./HappyPath-Rules.md) · [Framework-Rules.md](./Framework-Rules.md) · [Jira-Rules.md](./Jira-Rules.md) · [Reporting-Rules.md](./Reporting-Rules.md)

---

## Global guardrails (apply to all work)

1. **Do not break existing rules** — preserve current tags, folder layout, hook behavior, and Maven entry points unless explicitly approved.
2. **Do not change a working workflow** without:
   - explicit approval from the requesting user,
   - confirmation it does not break other suites or CI,
   - verification that all touched directories/files are updated consistently.
3. **Do not leave updated code untested** — dry-run binding at minimum; targeted `mvn test` when env/VPN allows; document what was and was not run.
4. **Reuse before rewrite** — search existing step defs and regression features before adding glue or page objects.
5. **Best practices** — minimal diff, match naming in sibling features, Scenario Outline for data variation, traceability tags.
6. **Trace impact before you edit** — regression features reuse happy-path glue heavily; any change to an existing step or page method must be searched across all of `Features/Regression/` and domain folders.
7. **Protect shared utilities** — do not modify `FileManager`, `UserGroups`, `TestingToolOptions`, or similar cross-domain code for one regression file.
8. **Do not touch `Hooks.java`** without explicit approval — shared regression mode and driver lifecycle affect every file under `Features/Regression/`.

---

## Scope

This file governs **all regression scenarios** under:

```
src/test/resources/Features/Regression/
```

Regression here means **two patterns**:

| Pattern | Purpose | Browser |
|---------|---------|---------|
| **Queue UI regression** | Login once → minimal pipeline → validate buttons/columns/tabs per queue | **Shared** (`Hooks.isSharedMode()`) |
| **Domain multi-type regression** | Full pipeline like happy path, parameterized across TestTypes | Shared (still under `Regression/`) |

**Do not** put long happy-path smoke scenarios here — use domain folders per [HappyPath-Rules.md](./HappyPath-Rules.md).

---

## Must-follow rules

### Folder and naming

| Rule | Detail |
|------|--------|
| Location | Only `Features/Regression/` |
| File name | `{QueueOrDomain}Regression.feature` (e.g. `FraxRegression.feature`, `QpcrPlatesRegression.feature`) |
| Feature tag | camelCase + `Regression` suffix (e.g. `@fraxRegression`, `@qpcrPlatesRegression`) |
| Exception | `@intakeregression` (legacy lowercase) — do not rename without approval |

### Scenario structure (queue UI regression)

1. **Scenario 1:** `Given Test Data setup` → login → generate minimal samples → reach target queue.
2. **Scenarios 2..N:** UI validations only — **no re-login** (shared browser).
3. Use steps from `@CommonPageSteps` for column/button/tab validation.
4. Queue names must match constants in `ColumnNames` / `ButtonNames` (see `src/main/java/constants/`).

### Scenario structure (domain regression, e.g. FRAX)

1. `Scenario Outline` + `Examples` for TestType / sample count variation.
2. Reuse happy-path steps — **no duplicate step classes** for the same flow.
3. Sub-tags for partial runs (e.g. `@fraxFullRegression`, `@fraxPnRegression`).
4. `TestType` values must exist in `@TestTypes.java`.

### Tags and execution

- **Never change** `TestRunner.java` default tags for regression-only work — override at runtime:
  ```powershell
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@fraxRegression"
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@fraxFullRegression"
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@rpFraXRegression"
  ```
- Dry-run before first live run:
  ```powershell
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@yourRegressionTag" "-Dcucumber.execution.dry-run=true"
  ```

### Shared browser hook

- Regression mode activates when feature URI contains `/features/regression/` (see `@Hooks.java` → `isSharedMode()`).
- Do not move regression features out of `Regression/` without updating hook logic and getting approval.

### Impact review when changing features or shared glue

Regression suites **share one browser** and **reuse happy-path steps**. A small glue change can break many `@*Regression` tags at once.

| Rule | Detail |
|------|--------|
| **Search before edit** | Grep the entire repo for the step phrase, Java method, or page object you plan to change — include `Features/Regression/`, domain happy paths, and `Features/UnitTest/`. |
| **Parameters stay compatible** | Queue names, `TestType` values, DataTable columns, and method signatures must work for **every** scenario that calls the same glue — including shared-browser scenarios 2..N that do not re-login. |
| **No duplicate/overload behavior** | Do not add overloads or change defaults in a shared method if it alters behavior for unrelated regression or happy-path files. |
| **Shared utils off limits** | Do not change `FileManager`, `UserGroups`, `TestingToolOptions`, `CommonPageSteps`, or `Hooks.java` for one regression feature without explicit approval and a listed impact matrix. |
| **Dry-run related tags** | Dry-run the edited regression tag **and** any happy path or queue UI regression that shares the same step classes. |

**Example:** Editing `CommonPageSteps` column validation affects **all** `*PlatesRegression.feature` and `*SamplesRegression.feature` files — list every file before merging.

### Jira traceability

- Add story key in feature header comment and/or tag: `@EXNGS-2557`
- Link related happy path and step classes in feature header (see `FraxRegression.feature`).

---

## Reference map

### Primary folder

| Path | Role |
|------|------|
| `src/test/resources/Features/Regression/` | All regression `.feature` files (27 files) |

### Exemplar: FRAX domain regression

| Reference | Path / symbol |
|-----------|---------------|
| Regression feature | `Features/Regression/FraxRegression.feature` |
| Happy path source (reuse steps) | `Features/INHFeatures/HappyPathFrax.feature` |
| RP queue UI only | `Features/Regression/RPFraxRegression.feature` |
| Test types | `src/main/java/constants/TestTypes.java` — `FRAX-CARR`, `FRAX-DX`, `FRAX-NC`, `FRAX-PN` |
| Step glue | `FraxSteps.java`, `RPFrax.java`, `Reporting.java`, `LoginSteps.java` |
| Tags | `@fraxRegression`, `@fraxFullRegression`, `@fraxPnRegression` |
| Page objects | `FragmentAnalysisPage`, `ResultProcessingFrax`, `ReportingPage` |

### Exemplar: queue UI regression

| Reference | Path / symbol |
|-----------|---------------|
| Intake matrix | `Features/Regression/IntakeRegression.feature` — `@intakeregression` |
| Sample receiving | `Features/Regression/SampleReceivingRegression.feature` |
| qPCR / dPCR / Gel / LCG / Library / Sequencing | `*PlatesRegression.feature`, `*SamplesRegression.feature` |
| RP analyst / variant / SMA | `RPAnalystRegression.feature`, `RPVariantRegression.feature`, `RPSMARegression.feature` |
| Shared steps | `CommonPageSteps.java`, `LoginSteps.java` |
| Navigation | `PageNavigator.java`, `WorkQueueManager.java` |

### Key classes

| Class | Role |
|-------|------|
| `stepDefinitions/Hooks.java` | Shared regression mode, driver lifecycle |
| `stepDefinitions/CommonPageSteps.java` | Queue UI validation steps |
| `stepDefinitions/BaseStepDefinition.java` | Test data, env, shared context |
| `constants/TestTypes.java` | Valid TestType enum values |
| `constants/WQItems.java` | Work queue identifiers |
| `constants/ColumnNames.java`, `ButtonNames.java` | Expected UI matrices |

### Regression feature inventory (tags)

| Feature file | Feature tag |
|--------------|-------------|
| `FraxRegression.feature` | `@fraxRegression` |
| `RPFraxRegression.feature` | `@rpFraXRegression` |
| `IntakeRegression.feature` | `@intakeregression` |
| `SampleReceivingRegression.feature` | `@sampleReceivingRegression` |
| `QpcrPlatesRegression.feature` | `@qpcrPlatesRegression` |
| `QpcrSamplesRegression.feature` | `@qpcrSamplesRegression` |
| `DpcrPlatesRegression.feature` | `@dPCRPlatesRegression` |
| `DpcrSamplesRegression.feature` | `@dPCRSamplesRegression` |
| `gelPlatesRegression.feature` | `@gelPlatesRegression` |
| `gelSamplesRegression.feature` | `@gelSamplesRegression` |
| `LcgPlatesRegression.feature` | `@lcgPlatesRegression` |
| `LcgSamplesRegression.feature` | `@lcgSamplesRegression` |
| `LibraryPreparationPlatesRegression.feature` | `@libraryQueuePlatesRegression` |
| `LibraryPreparationSamplesRegression.feature` | `@libraryPreparationSamplesRegression` |
| `ManualExtractionPlatesRegression.feature` | `@manualExtractionPlatesRegression` |
| `ManualExtractionSamplesRegression.feature` | `@manualExtractionSamplesRegression` |
| `AutomationExtractionPlatesRegression.feature` | `@automatedExtractionPlatesRegression` |
| `AutomatedExtractionSamplesRegression.feature` | `@automatedExtractionSamplesRegression` |
| `SequencingRegression.feature` | `@sequencingRegression` |
| `RPAnalystRegression.feature` | `@rpAnalystRegression` |
| `RPVariantRegression.feature` | `@rpVariantRegression` |
| `RPSMARegression.feature` | `@rpSMARegression` |
| `SmaRegression.feature` | `@smaRegression` |
| `MccRegression.feature` | `@mccRegression` |
| `PlasmaCompleteRegression.feature` | `@plasmaCompleteRegression` |
| `PlasmaCompleteLabQCRegression.feature` | `@plasmaCompleteLabQcRegression` |
| `GelRegression.feature` | `@gelRegression` |
| `DmlpaSamplesRegression.feature` | `@dmlpaSamplesRegression` |

### Exemplar: SMA domain regression

| Reference | Path / symbol |
|-----------|---------------|
| Domain regression feature | `Features/Regression/SmaRegression.feature` |
| Happy path source (reuse steps) | `Features/INHFeatures/HappyPathSMA.feature` |
| Prenatal source | `Features/INHFeatures/SMAPNwithMCCHappyPath.feature` |
| RP queue UI only | `Features/Regression/RPSMARegression.feature` |
| Test types | `TestTypes.java` — `SMA`, `SMA-NC`, `SMA-PN` |
| Step glue | `Qpcr.java`, `Dpcr.java`, `Sanger.java`, `RPSMA.java`, `Reporting.java`, `LoginSteps.java` |
| Tags | `@smaRegression`, `@smaFullRegression`, `@smaPnRegression` |
| Page objects | `ResultProcessingSma`, `ReportingPage`, `PDFValidationsPage` |

### Exemplar: Plasma Complete domain regression

| Reference | Path / symbol |
|-----------|---------------|
| Domain regression feature | `Features/Regression/PlasmaCompleteRegression.feature` |
| Happy path source (reuse steps) | `Features/PlasmaComplete/HappyPathPlasmaComplete.feature` |
| Test types | `TestTypes.java` — `PCOMP-PC` |
| Step glue | `AutomatedDNAExtraction.java`, `LibraryPrep.java`, `LabQc.java`, `RPAnalyst.java`, `RPVariant.java`, `Reporting.java`, `LoginSteps.java` |
| Tags | `@plasmaCompleteRegression`, `@plasmaCompleteFullRegression` |
| Page objects | `DnaExtractionPage`, `LibraryPrepPlatesPage`, `LabQCPage`, `ReportingPage` |

### Exemplar: Gel domain regression

| Reference | Path / symbol |
|-----------|---------------|
| Domain regression feature | `Features/Regression/GelRegression.feature` |
| Happy path source (reuse steps) | `Features/INHFeatures/GelHappyPath.feature` |
| Queue UI only (shared browser) | `Features/Regression/gelSamplesRegression.feature`, `gelPlatesRegression.feature` |
| Test types | `TestTypes.java` — `ALPHA-THAL` |
| Step glue | `GEL.java`, `AllSteps.java`, `AutomatedDNAExtraction.java`, `LoginSteps.java` |
| Tags | `@gelRegression`, `@gelFullRegression` |
| Page objects | `GelSamplePage`, `GelPlatePage`, `CommonPageElements` |

### Exemplar: MCC domain regression

| Reference | Path / symbol |
|-----------|---------------|
| Domain regression feature | `Features/Regression/MccRegression.feature` |
| Happy path source (reuse steps) | `Features/INHFeatures/HappyPathMCC.feature` |
| Prenatal reporting source | `Features/INHFeatures/ReportingE2E/InhMCCPNReporting.feature` |
| SMA-PN + MCC combo source | `Features/INHFeatures/SMAPNwithMCCHappyPath.feature` |
| Test types | `TestTypes.java` — `MCC`, `MCC-PN` |
| Step glue | `MCC.java`, `Reporting.java`, `Verbals.java`, `LoginSteps.java` |
| Tags | `@mccRegression`, `@mccFullRegression`, `@mccPnRegression` |
| Page objects | `MCCPage`, `ReportingPage` |

### Gaps (known)

| Area | Status |
|------|--------|
| Microbiome LabQC regression | **Not yet** — happy path only: `Microbiome/HappyPathMB.feature` |
| MB Sample Stats (EXNGS-2557) | Candidate: new `MicrobiomeLabQCRegression.feature` or extend MB happy path — requires `@Jira-Rules.md` intake |

---

## Validation checklist (before merge)

- [ ] Feature file is under `Features/Regression/` with correct `*Regression.feature` name
- [ ] Feature tag matches convention and is unique
- [ ] Scenario 1 handles login; later scenarios do not re-login (queue UI pattern)
- [ ] All `TestType` values exist in `TestTypes.java`
- [ ] No duplicate step definitions when existing glue fits
- [ ] Dry-run passes: `-Dcucumber.execution.dry-run=true`
- [ ] Maven tag filter documented in PR / feature header
- [ ] No change to `TestRunner.java` default tags without approval
- [ ] Shared-mode behavior verified (feature path under `Regression/`)
- [ ] Jira key referenced if story-driven
- [ ] **Impact search done** — all call sites of changed steps/methods reviewed; related happy paths and queue regressions listed
- [ ] **Shared utils and Hooks untouched** unless explicitly approved

---

## Team instructions (living section)

> **For automation developers:** Add new rules, file `@` references, and acceptance criteria here.  
> **For the agent:** When the user submits instructions via `@Regression-Rules.md`, merge their requirements into this section and update reference tables above if needed.

### Documented example — FRAX regression feature

**Request:** Create new FRAX regression feature covering multiple test types.

**Related references:**

| Item | Reference |
|------|-----------|
| New feature | `Features/Regression/FraxRegression.feature` |
| Reuse steps from | `Features/INHFeatures/HappyPathFrax.feature` |
| Test types | `@TestTypes.java` — `FRAX-CARR`, `FRAX-DX`, `FRAX-NC`, `FRAX-PN` |
| Tags | `@fraxRegression`, `@fraxFullRegression`, `@fraxPnRegression` |
| Step classes | `FraxSteps.java`, `RPFrax.java`, `Reporting.java` |
| Run | `mvn test "-Denv=qa" "-Dcucumber.filter.tags=@fraxRegression"` |

### Active team instructions

#### 2026-07-10 — SMA domain regression feature

- **Goal:** Full-pipeline SMA regression across `SMA`, `SMA-NC`, and `SMA-PN` test types
- **Files:** `Features/Regression/SmaRegression.feature`
- **Reuse:** `HappyPathSMA.feature`, `SMAPNwithMCCHappyPath.feature`, `RPSMARegression.feature` (RP UI only)
- **Tags:** `@smaRegression`, `@smaFullRegression`, `@smaPnRegression`
- **Run:**
  ```powershell
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@smaRegression"
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@smaFullRegression"
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@smaPnRegression"
  ```
- **Validation:** dry-run required before first QA run

#### 2026-07-13 — MCC domain regression feature

- **Goal:** Full-pipeline MCC regression for `MCC-PN` + maternal `MCC` control, plus MCC queue validation paired with `SMA-PN`
- **Files:** `Features/Regression/MccRegression.feature`
- **Reuse:** `HappyPathMCC.feature`, `InhMCCPNReporting.feature`, `SMAPNwithMCCHappyPath.feature`
- **Tags:** `@mccRegression`, `@mccFullRegression`, `@mccPnRegression`
- **Run:**
  ```powershell
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@mccRegression"
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@mccFullRegression"
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@mccPnRegression"
  ```
- **Validation:** dry-run required before first QA run

#### 2026-07-20 — Plasma Complete domain regression feature

- **Goal:** Full-pipeline Plasma Complete regression for `PCOMP-PC` (manual extraction, CMBP/EXENC)
- **Files:** `Features/Regression/PlasmaCompleteRegression.feature`
- **Reuse:** `PlasmaComplete/HappyPathPlasmaComplete.feature`
- **Tags:** `@plasmaCompleteRegression`, `@plasmaCompleteFullRegression`
- **Run:**
  ```powershell
  mvn test "-Denv=dev" "-Dcucumber.filter.tags=@plasmaCompleteRegression"
  mvn test "-Denv=dev" "-Dcucumber.filter.tags=@plasmaCompleteFullRegression"
  ```
- **Validation:** dry-run required before first DEV run

#### 2026-07-25 — Gel domain regression feature

- **Goal:** Full Gel queue regression — samples, plate build/launch, LabTech QC, variant entry, workflow completion
- **Files:** `Features/Regression/GelRegression.feature`
- **Reuse:** `INHFeatures/GelHappyPath.feature` (queue UI: `gelSamplesRegression.feature`, `gelPlatesRegression.feature`)
- **Tags:** `@gelRegression`, `@gelFullRegression`
- **Run:**
  ```powershell
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@gelRegression"
  mvn test "-Denv=qa" "-Dcucumber.filter.tags=@gelFullRegression"
  ```
- **Validation:** dry-run required before first QA run

#### 2026-09-04 — Plasma Complete LabQC Data Analyst regression (EXNGS-4000)

- **Goal:** Validate MolOnc Data Analyst can access Plasma Complete Lab QC work queue and Sample Stats analysis
- **Files:** `Features/Regression/PlasmaCompleteLabQCRegression.feature`
- **Reuse:** `HappyPathPlasmaComplete.feature` pipeline through Sequencing; `CommonPageSteps` LAB_QC column/button validation
- **Tags:** `@plasmaCompleteLabQcRegression`, `@EXNGS-4000`
- **Java:** `PlasmaCompleteSteps.java`, `LabQCPage.java` (EXNGS-4000 methods only)
- **Run:**
  ```powershell
  mvn test "-Denv=dev" "-Dcucumber.filter.tags=@EXNGS-4000"
  mvn test "-Denv=dev" "-Dcucumber.filter.tags=@plasmaCompleteLabQcRegression"
  ```
- **Validation:** dry-run required before first DEV run

#### 2026-07-29 — Cross-suite impact on regression edits

- Any change to shared glue (`CommonPageSteps`, domain step classes, page objects) requires a full-framework usage search before merge.
- Do not modify `FileManager`, `UserGroups`, `TestingToolOptions`, or `Hooks.java` for a single regression file without approval.

### Pending / requested

| Jira | Request | Status |
|------|---------|--------|
| EXNGS-2557 | Microbiome LabQC Sample Stats regression | Not started — see `@Jira-Rules.md` |

---

## Example agent invocation

```
@Regression-Rules.md

Create queue regression for Microbiome LabQC Sample Stats per EXNGS-2557.
Reuse HappyPathMB LabQC steps. Reference @TestTypes.java MCB-CORE.
Dry-run only unless I approve QA run.
```
# Reporting Rules

> **How to use:** In Cursor agent chat, attach `@Reporting-Rules.md` plus your specific request.  
> The agent must follow every rule below, validate reporting changes, run tests when applicable, and **append durable updates** to [Team instructions](#team-instructions-living-section) when you add new conventions or file references.

**Related docs:** [insight-reporting/INTEGRATION-GUIDE.md](../insight-reporting/INTEGRATION-GUIDE.md) · [insight-reporting/ARCHITECTURE.md](../insight-reporting/ARCHITECTURE.md) · [PROJECT-MASTER-DIAGRAM.md](../PROJECT-MASTER-DIAGRAM.md) · [HappyPath-Rules.md](./HappyPath-Rules.md) · [Framework-Rules.md](./Framework-Rules.md)

---

## Global guardrails (apply to all work)

1. **Do not break existing rules** — preserve `TestRunner` plugin list, hook order, default report paths, and Jenkins publish steps unless explicitly approved.
2. **Do not change a working workflow** without explicit user approval, CI impact review, and consistent updates to hooks, plugins, and config files.
3. **Do not leave updated reporting code untested** — verify report artifacts exist after a dry-run or targeted test run; document what was generated.
4. **Opt-in over opt-out** — Insight and heavy capture stay tag-driven (`@InsightReport`); do not enable globally without approval.
5. **Best practices** — minimal plugin changes, keep Spark + Cucumber + Insight coexistence, no secrets in report output.
6. **Trace impact before you edit** — reporting hooks (`Hooks.java`, `InsightHooks.java`) and shared utilities (`ReportManager`, `VideoRecord`, `FileManager`) affect every suite; search all consumers before changing them.
7. **Protect shared utilities** — do not modify `FileManager` or driver/video lifecycle code for reporting-only needs without explicit approval.
8. **Do not touch `Hooks.java` hook order** without cross-review — Insight video attach depends on framework teardown sequence.

---

## Scope

This file governs **all test reporting and artifacts**:

| Layer | Technology | Output location |
|-------|------------|-----------------|
| **Extent Spark** | `ExtentCucumberAdapter` + `ReportManager` | `target/Spark/*.html`, screenshots under `target/Spark/Screenshots/` |
| **Cucumber Reports** | Built-in Cucumber plugins in `TestRunner` | `target/cucumber-report-html/`, `target/cucumber.json`, `target/cucumber/` (timeline) |
| **Surefire** | Maven Surefire | `target/surefire-reports/` |
| **Screen video** | `VideoRecord` (Monte Media) via `WebDriverController` | Scenario AVI during run; Insight may copy/convert to MP4 |
| **Insight Dashboard** | `@InsightReport` + `InsightHooks` + `CucumberInsightPlugin` | `target/insight-reports/runs/{buildNumber}/` |

---

## Must-follow rules

### TestRunner plugins (do not remove without approval)

Current `TestRunner.java` plugins (Insight step plugin loads via `META-INF/services/io.cucumber.plugin.Plugin`):

```java
plugin = {
    "com.aventstack.extentreports.cucumber.adapter.ExtentCucumberAdapter:",
    "pretty", "html:target/XMLReports/Report.xml",
    "json:target/cucumber-report-html/report.json",
    "html:target/cucumber-report-html/report.html",
    "timeline:target/cucumber",
    "json:target/cucumber.json"
}
```

**Rule:** Add plugins only when needed; never remove Spark or Cucumber JSON/HTML without team approval.

### Extent Spark (per-feature HTML)

| Reference | Path / behavior |
|-----------|-----------------|
| Adapter | `com.aventstack.extentreports.cucumber.adapter.ExtentCucumberAdapter` |
| Report manager | `utilities/ReportManager.java` — `ExtentSparkReporter` per feature name |
| Output | `target/Spark/{FeatureName}.html` |
| Screenshots on failure | `WebDriverController` → `target/Spark/Screenshots/ss_*.png` |
| File paths enum | `utilities/FileManager.java` — `SPARK`, `SCREENSHOTS` |

Spark initializes in `Hooks.commonSetup()` when `isSparkRun` is true. Shared regression mode keeps one Spark report for the feature file.

### Cucumber HTML / JSON / timeline

| Artifact | Path |
|----------|------|
| HTML report | `target/cucumber-report-html/report.html` |
| JSON (HTML plugin) | `target/cucumber-report-html/report.json` |
| JSON (root) | `target/cucumber.json` |
| Timeline | `target/cucumber/` |
| XML (legacy) | `target/XMLReports/Report.xml` |

Use Cucumber JSON for CI integrations; HTML for human review.

### Screen video recording

| Reference | Behavior |
|-----------|----------|
| `utilities/VideoRecord.java` | Monte Media screen capture |
| `utilities/WebDriverController.java` | `startVideoRecording()` / `stopVideoRecording()` |
| `stepDefinitions/Hooks.java` | Starts video `@Before(order=2)`; stops `@After(order=3)` for non-shared mode |
| Shared regression | One recording for entire feature (`sharedRecordingStarted` flag) |
| Jenkins | `jenkinsRun=true` skips local video on agent (see `initJenkins()` in `Hooks.java`) |

**Rule:** Do not change video start/stop timing without updating `InsightHooks` (order=1 attaches video after framework `@After(order=3)` teardown).

### Insight Reporting (`@InsightReport`)

Insight is **opt-in per scenario** via the `@InsightReport` tag.

| Reference | Path / role |
|-----------|-------------|
| Config | `src/test/resources/insight/config/insight.properties` |
| Facade | `insight/InsightReportingFacade.java` |
| Hooks | `insight/hooks/InsightHooks.java` — `@Before`/`@After`/`@BeforeStep`/`@AfterStep` |
| Plugin | `insight/collector/CucumberInsightPlugin.java` |
| Dashboard | `target/insight-reports/runs/{buildNumber}/index.html` |
| Run data | `execution-run.json` in run folder |
| Artifacts | `screenshots/`, `dom/`, `videos/` under run folder |

**Enable on a feature or scenario:**

```gherkin
@MBSmoke @InsightReport
Feature: Microbiome happy path
```

**Disable Insight only (keep Spark + Cucumber):**

```powershell
mvn test "-Denv=qa" "-Dcucumber.filter.tags=@MBSmoke" "-Dinsight.enabled=false"
```

**Config overrides (system properties):**

| Property | Default | Purpose |
|----------|---------|---------|
| `insight.enabled` | `true` | Master switch |
| `insight.output.dir` | `target/insight-reports` | Output root |
| `insight.build.number` | auto | Run folder name |
| `insight.devtools.enabled` | `true` | Network capture |
| `insight.capture.dom.on.failure` | `true` | DOM snapshot on fail |
| `insight.capture.dom.on.slow` | `true` | DOM snapshot on slow steps |

### Hook execution order (critical — do not reorder without approval)

```
@Before  order=2  — Hooks.java (driver, video, Spark init)
@Before  order=?  — InsightHooks (scenario start, if @InsightReport)
@After   order=3  — Hooks.java (stop video, quit driver)
@After   order=5  — InsightHooks (attach video, artifacts, finalize scenario)
@AfterAll        — Hooks.java (shared mode cleanup)
@AfterAll        — InsightHooks (generate dashboard)
```

### Custom / clinical reporting validation

Domain reporting E2E features live under `Features/INHFeatures/ReportingE2E/`. PDF and report content validation uses:

| Reference | Role |
|-----------|------|
| `stepDefinitions/Reporting.java` | Reporting workflow steps |
| `pages/ReportingPage.java`, `PDFValidationsPage.java` | UI + PDF checks |
| `utilities/PDFGenerator.java` | PDF helpers |

These are **functional test validations**, not framework report outputs. Tag and run them per [HappyPath-Rules.md](./HappyPath-Rules.md).

### Jenkins / CI publishing

Insight dashboard publishing pattern (see `INTEGRATION-GUIDE.md`):

```groovy
publishHTML([
    reportName: 'Insight Dashboard',
    reportDir: "target/insight-reports/runs/${env.BUILD_NUMBER}",
    reportFiles: 'index.html',
    keepAll: true,
    alwaysLinkToLastBuild: true
])
archiveArtifacts artifacts: 'target/insight-reports/**/*', fingerprint: true
```

**Rule:** CI report path changes require Jenkinsfile review — do not change output dirs without updating pipeline.

### Impact review for reporting and hook changes

Reporting touches **global lifecycle** code. Before editing:

| Area | Rule |
|------|------|
| `stepDefinitions/Hooks.java` | **Frozen by default** — driver init, video start/stop, Spark, shared regression mode. Walk all features and `InsightHooks.java` before any edit. |
| `insight/hooks/InsightHooks.java` | Hook order (3, 1, 5) depends on `Hooks.java` (2, 3). Do not reorder without updating both files and this doc. |
| `utilities/FileManager.java` | Paths for Spark, screenshots, downloads — do not change for one report type. |
| `utilities/ReportManager.java`, `VideoRecord.java` | Used by all scenarios; grep consumers before signature changes. |
| `TestRunner` plugins | Add only when needed; never remove Spark or Cucumber JSON without approval. |

Do not add overloads or change defaults in shared reporting utilities if unrelated suites would behave differently.

---

## Reference map

### When to use which report

| Need | Use | How |
|------|-----|-----|
| Step-by-step log with screenshots | Spark | Always on (via adapter) |
| CI pass/fail matrix | Cucumber JSON | `target/cucumber.json` |
| Human timeline view | Cucumber timeline | `target/cucumber/` |
| Debug flaky/slow steps, network, video sync | Insight | Add `@InsightReport` |
| Local replay of failure | Spark screenshot + video | Check `target/Spark/` after run |
| Release readiness / bottlenecks | Insight dashboard | Compare runs in `insight-reports/` |

### Default TestRunner tags (reporting note)

Default: `@happyPathFraxSmokeTest and @InsightReport` — FRAX smoke **with** Insight enabled.

Override at runtime without changing `TestRunner.java`:

```powershell
# Spark + Cucumber only (no Insight capture)
mvn test "-Denv=qa" "-Dcucumber.filter.tags=@MBSmoke and not @InsightReport"

# Insight with custom build id
mvn test "-Denv=qa" "-Dcucumber.filter.tags=@happyPathFraxSmokeTest and @InsightReport" "-Dinsight.build.number=dev-001"
```

### Insight plugin extension (advanced)

Custom notifications or exporters implement `insight/plugin/InsightPlugin.java` and register via `PluginRegistry` or SPI (`META-INF/services/insight.plugin.InsightPlugin`). See [PLUGIN-DEVELOPMENT.md](../insight-reporting/PLUGIN-DEVELOPMENT.md).

---

## Validation checklist (before merge)

- [ ] `TestRunner` plugin list unchanged unless explicitly requested
- [ ] Hook order preserved (`Hooks` order 2/3, `InsightHooks` order 5)
- [ ] `@InsightReport` added only where Insight capture is intended
- [ ] `insight.properties` changes documented; no secrets added
- [ ] After test/dry-run: expected artifacts exist under `target/Spark/`, `target/cucumber-report-html/`
- [ ] If Insight tagged: `target/insight-reports/runs/{build}/index.html` generates
- [ ] Jenkins publish paths still match if output dirs changed
- [ ] Video behavior verified for shared vs non-shared scenarios
- [ ] **Impact search done** if `Hooks.java`, `InsightHooks.java`, or shared reporting utils were modified
- [ ] **No unrelated suite regression** from parameter or hook-order changes

---

## Team instructions (living section)

> **For automation developers:** Add new rules, `@` file references, and acceptance criteria here.  
> **For the agent:** When the user submits instructions via `@Reporting-Rules.md`, merge requirements into this section and update reference tables above if needed.

### Documented example — enable Insight on a new smoke feature

| Item | Reference |
|------|-----------|
| Feature | `Features/Microbiome/HappyPathMB.feature` |
| Tag to add | `@InsightReport` at feature level |
| Run | `mvn test "-Denv=qa" "-Dcucumber.filter.tags=@MBSmoke and @InsightReport" "-Dinsight.build.number=dev-mb-001"` |
| Verify | `target/insight-reports/runs/dev-mb-001/index.html` |

### Active team instructions

<!-- Append new instructions below -->

#### 2026-07-29 — Reporting changes require hook impact review

- `Hooks.java` and `InsightHooks.java` are interdependent — do not change order or lifecycle without full framework walkthrough.
- Do not modify `FileManager` or shared video/report utilities for a single feature without approval.

### Pending / requested

| Jira | Request | Status |
|------|---------|--------|
| — | — | — |

---

## Example agent invocation

```
@Reporting-Rules.md

Add @InsightReport to HappyPathMB and verify dashboard generates after dry-run.
Do not change TestRunner default tags. Document Maven command for QA run.
```

```
