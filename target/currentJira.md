


# LAB AUTOMATION ENGINEERING CONTRACT — WORKFLOW, COVERAGE & EXECUTION ADDENDUM

> These rules are mandatory and extend the existing LAB AUTOMATION ENGINEERING CONTRACT.
> If an older rule conflicts with this addendum, use the safer rule that provides greater business traceability and preserves the existing framework.

---

# 39. USE ACTUAL LAB WORKFLOW TERMINOLOGY

Never replace established application/business terminology with generic names when the real workflow name is known.

Feature files, reports, Jira Test Cases, execution summaries, screenshots, failure messages, and coverage matrices should use the same terminology used by the application, Jira story, and existing automation framework.

For the currently established workflows, use names such as:

* Sample Generation
* Sample Receiving
* Intake Review
* Automated DNA Extraction
* Manual DNA Extraction
* Library Prep
* Sequencing
* Lab QC / LabQC
* Sample Stats
* Reporting
* Verbals
* Quick Search / Test Order
* TNP Report

Domain-specific names must also be preserved where applicable, including:

* Plasma Complete
* Microbiome
* MolOnc
* FRAX
* BRCA
* MCC
* GEL
* Repeat Expansion
* INH

Do not rename an established workflow merely to make the automation appear generic.

Example:

BAD:

`When the user processes the sample`

PREFERRED:

`When the user completes Intake Review for the sample`

or:

`When the sample is processed through Automated DNA Extraction`

The Cucumber feature should describe the business workflow in language recognizable to QA, developers, product owners, and laboratory users.

---

# 40. MAP THE STORY AGAINST THE ACTUAL WORKFLOW

After retrieving a Jira story, determine exactly which portion of the laboratory workflow the story affects.

Example:

Jira Story
→ Sample Generation
→ Sample Receiving
→ Intake Review
→ Automated DNA Extraction
→ Library Prep
→ Sequencing
→ LabQC
→ Reporting
→ Verbals

The story may affect:

* one workflow stage;
* several workflow stages;
* an entire happy path;
* a regression-only behavior;
* a permission/user-group behavior;
* reporting;
* an integration boundary.

Do not automatically execute or modify the entire pipeline if the requirement concerns only one stage.

However, when upstream stages are required to place the sample into the correct state, reuse the established pipeline steps rather than recreating them.

---

# 41. CREATE A LIVE JIRA COVERAGE CHECKLIST BEFORE IMPLEMENTATION

Immediately after the full Jira ticket pack has been reviewed, create a Story Coverage Checklist.

This checklist is mandatory.

It must be created BEFORE implementation begins and updated throughout development and execution.

Example:

## STORY COVERAGE CHECKLIST

Story: `EXNGS-XXXX`

### Jira Intake

* [x] Story title reviewed — DONE
* [x] Description reviewed — DONE
* [x] Acceptance Criteria reviewed — DONE
* [x] Comments reviewed — DONE
* [x] Screenshots reviewed — DONE
* [x] Attachments reviewed — DONE
* [x] Linked issues reviewed — DONE
* [x] Existing Test Cases reviewed — DONE
* [x] Recent requirement clarifications reviewed — DONE

### Requirement Coverage

* [x] AC1 mapped — DONE
* [x] AC2 mapped — DONE
* [ ] AC3 mapped — PENDING
* [ ] Negative coverage evaluated — PENDING
* [ ] Boundary coverage evaluated — PENDING

### Framework Analysis

* [x] Existing feature files searched — DONE
* [x] Existing step definitions searched — DONE
* [x] Page Objects searched — DONE
* [x] Existing locators searched — DONE
* [x] Existing utilities/helpers searched — DONE
* [x] Existing assertions searched — DONE
* [x] Existing test data strategy reviewed — DONE
* [x] Shared-code impact analyzed — DONE

### Implementation

* [x] Feature scenario created/updated — DONE
* [x] Existing steps reused where possible — DONE
* [x] Missing step definitions implemented — DONE
* [x] Page/component changes implemented — DONE
* [x] Assertions implemented — DONE
* [x] Jira traceability tag added — DONE

### Execution

* [x] Compilation — DONE
* [x] Cucumber dry-run — DONE
* [x] Target scenario UI execution — DONE
* [x] Story scenarios execution — DONE
* [x] Relevant regression — DONE
* [x] Screenshots reviewed — DONE
* [x] Logs reviewed — DONE
* [x] Insight evidence reviewed — DONE

### Jira Delivery

* [x] AC coverage verified — DONE
* [x] Test Case created/updated — DONE
* [x] Execution Summary generated — DONE
* [x] Screenshots/evidence prepared — DONE
* [x] Coverage report attached — DONE
* [x] Story/Test Case association verified — DONE

The checklist must reflect reality.

NEVER mark an item DONE simply because code was generated.

---

# 42. CHECKLIST STATUS RULES

Use only meaningful status values:

`DONE`

`PENDING`

`IN PROGRESS`

`BLOCKED`

`N/A — <reason>`

Never use DONE for:

* code that has not executed;
* assertions that have not been exercised;
* AC coverage that has not been verified;
* regression that has not actually run;
* Jira attachment that has not actually been created/attached.

A checkmark means the activity was completed and verified.

---

# 43. ACCEPTANCE CRITERIA COVERAGE CHECKLIST

In addition to the engineering checklist, maintain an AC-specific coverage table.

Example:

| AC  | Business Requirement          | Workflow             | Scenario              | Assertions              | Evidence             | Status    |
| --- | ----------------------------- | -------------------- | --------------------- | ----------------------- | -------------------- | --------- |
| AC1 | Data Analyst can access queue | LabQC                | Access LabQC          | Role + queue validation | Screenshot           | ✅ DONE    |
| AC2 | Sample Stats are visible      | LabQC / Sample Stats | Validate Sample Stats | Column/value validation | Screenshot + Insight | ✅ DONE    |
| AC3 | Unauthorized role cannot edit | LabQC                | Permission validation | Control disabled        | Screenshot           | ⏳ PENDING |

Every AC must finish as one of:

`✅ DONE`

`⚪ N/A — documented reason`

`⛔ BLOCKED — documented reason`

No AC may disappear from the report.

---

# 44. CHECKLIST MUST BE UPDATED DURING IMPLEMENTATION

The checklist is a living artifact.

Do not create it only at the end.

Update it as work progresses:

`PENDING → IN PROGRESS → DONE`

or:

`PENDING → BLOCKED`

This provides a visible record of what remains unfinished.

Before every final completion statement, inspect the checklist.

If a required item remains PENDING, the story is NOT complete.

---

# 45. THREE CONSECUTIVE FAILURE GATE

The automation agent may diagnose and fix failures autonomously.

However, it must NEVER enter an unlimited retry/fix loop.

If the SAME LOGICAL WORKFLOW STEP fails three consecutive times during the same debugging cycle:

**STOP EXECUTION IMMEDIATELY.**

Status:

`USER INTERVENTION REQUIRED`

Example:

Attempt 1
`Intake Review → Clinical Indicator selection failed`

Investigate → fix → retry.

Attempt 2
`Intake Review → Clinical Indicator selection failed`

Investigate → fix → retry.

Attempt 3
`Intake Review → Clinical Indicator selection failed`

STOP.

Do not perform Attempt 4 automatically.

---

# 46. FAILURE COUNTER IS BUSINESS-STEP BASED

The retry counter belongs to the logical workflow action, not merely to a Java method, exception type, browser session, or Maven execution.

Restarting:

* Browser
* WebDriver
* Scenario
* Maven
* JVM

does NOT reset the counter when the underlying failure remains the same.

Example:

`Library Prep → Qubit result cannot be submitted`

failing three times remains three failures even if WebDriver was restarted between attempts.

---

# 47. EVERY RETRY REQUIRES INVESTIGATION

Never perform blind retries.

Required sequence:

FAIL
→ Capture evidence
→ Diagnose
→ Classify probable root cause
→ Make justified correction
→ RETRY

For each attempt record:

* Attempt number
* Workflow
* Exact Cucumber step
* Expected result
* Actual result
* Exception/error
* Screenshot
* Relevant sample/order/test identifier
* Probable root cause
* Change made before retry

---

# 48. STOP EARLY FOR PROVEN EXTERNAL BLOCKERS

Three attempts are the MAXIMUM autonomous retry allowance.

They are not mandatory.

Stop immediately when evidence establishes an external blocker such as:

* Environment unavailable
* VPN unavailable
* Required TestType unavailable
* Automation user lacks required permission
* Required test data cannot be generated
* External integration unavailable
* Application/server failure
* Required upstream manual activity incomplete
* Jira requirements contradict each other
* Business expectation cannot be determined safely

Status:

`BLOCKED — USER INTERVENTION REQUIRED`

Do not waste three executions on a known external blocker.

---

# 49. THREE-FAILURE ESCALATION PACKAGE

When the Three Failure Gate is triggered, provide:

## Story

`EXNGS-XXXX`

## Scenario

`Scenario name`

## Workflow

`Intake Review / LabQC / Library Prep / etc.`

## Failed Step

Exact Cucumber step.

## Attempts

`3/3`

## Expected

Expected business behavior.

## Actual

Observed application behavior.

## Evidence

* Screenshots
* Logs
* Insight evidence
* DOM when available
* Video when useful
* Relevant sample/order/test identifier

## Root Cause Classification

Choose the best-supported category:

* Automation defect
* Application defect suspected
* Test data issue
* Environment issue
* Permission/user-group issue
* Business-rule mismatch
* Locator issue
* Synchronization issue
* External dependency
* Requirement ambiguity
* Unknown

## Changes Attempted

Explain what was changed between attempts.

## User Decision Required

State exactly what is needed before continuing.

---

# 50. NEVER BYPASS A FAILED WORKFLOW STEP

After the Three Failure Gate:

Do NOT:

* skip the failing Cucumber step;
* comment out the step;
* remove its assertion;
* weaken the assertion;
* change Jira expected behavior;
* force a status/value;
* insert arbitrary sleeps;
* create an artificial pass;
* continue downstream as if the workflow succeeded.

The workflow may continue only after the blocked step is legitimately resolved.

---

# 51. PRESERVE FAILURE EVIDENCE USING EXISTING FRAMEWORK

Use the existing reporting infrastructure.

Prefer existing:

* Insight reporting
* Screenshots
* DOM capture
* Video recording
* Cucumber results
* Framework logs

Do NOT create another parallel reporting framework merely to support this rule.

Do NOT modify Hook lifecycle/order merely to capture retry evidence.

Protected framework behavior remains protected.

---

# 52. STORY REPORT MUST SHOW CHECKLIST PROGRESS

The Jira-facing report must now contain a concise Coverage Checklist.

Required report structure:

## A. Story Information

Story ID
Story Title
Environment
Execution Date
TestType
Domain
Workflow(s) affected
Final Automation Status

## B. Acceptance Criteria Coverage

Show:

AC
Requirement
Workflow
Scenario
Validation
Evidence
Status

## C. Automation Completion Checklist

Show major completion gates with:

`✅ DONE`

`⏳ PENDING`

`⛔ BLOCKED`

`⚪ N/A`

Do not expose unnecessary implementation details to Jira reviewers.

## D. Execution Summary

Total
Passed
Failed
Skipped
Pass Rate
Duration

Include the existing small pass/fail/skipped pie chart.

## E. Expected vs Actual

For each important business validation.

## F. Evidence

Include or reference only useful evidence:

* Relevant screenshots
* Execution report
* Insight execution/build identifier
* Relevant failure evidence
* Application result evidence

---

# 53. SCREENSHOTS MUST PROVE BUSINESS COVERAGE

Do not attach screenshots merely because screenshots exist.

A Jira screenshot should help prove:

* the expected queue/page was reached;
* the expected value appeared;
* the expected status changed;
* the expected permission was applied;
* Sample Stats showed the expected data;
* the report was generated;
* the relevant success/error state occurred.

Where practical, associate screenshot evidence with the corresponding AC.

Example:

`AC2 → LabQC Sample Stats visible → screenshot_03.png`

This creates:

Jira AC
→ Scenario
→ Validation
→ Screenshot
→ Execution Result

---

# 54. CREATE OR UPDATE THE JIRA TEST CASE FROM VERIFIED COVERAGE

The Jira Test Case must represent what was ACTUALLY implemented and verified.

It should include:

* Story reference
* Test Case title
* Domain
* Workflow
* Preconditions
* Test data
* Meaningful business steps
* Expected result for relevant steps
* AC coverage
* Automation status
* Execution result
* Environment
* Evidence/report reference

Never generate a generic Jira Test Case such as:

Step: Run automation
Expected: Automation passes

The Jira Test Case should be understandable without opening the Java implementation.

---

# 55. JIRA TEST CASE MUST INCLUDE FINAL COVERAGE STATUS

When the story reaches completion, update the Jira Test Case with final coverage.

Example:

## Coverage

AC1 — ✅ DONE
AC2 — ✅ DONE
AC3 — ✅ DONE
AC4 — ⚪ N/A — Integration-only Cloverleaf validation

## Execution

Scenario: `@EXNGS-XXXX`

Environment: DEV

Result: PASS

## Evidence

Execution Summary attached
Relevant screenshots attached
Insight Run ID recorded

This provides an auditable connection between requirement and automation.

---

# 56. JIRA DELIVERY MUST USE VERIFIED ARTIFACTS ONLY

Never attach a report to Jira claiming successful coverage before the corresponding execution is complete.

Order:

Jira Story Analysis
→ Coverage Checklist
→ Automation Design
→ Implementation
→ Dry Run
→ UI Execution
→ Assertions
→ Regression
→ Evidence Review
→ Coverage Verification
→ Report
→ Jira Test Case Update
→ Jira Evidence Attachment

Jira is the final traceability layer, not a substitute for execution.

---

# 57. DIFFERENTIATE UI-AUTOMATABLE AND INTEGRATION-ONLY COVERAGE

Some stories include requirements outside the Exemplar UI automation boundary.

Examples may include:

* Cloverleaf message creation/routing
* GO TSV/file delivery
* External system processing
* Infrastructure behavior

Do not pretend these are UI automated.

Mark them explicitly:

`N/A FOR UI AUTOMATION — INTEGRATION COVERAGE REQUIRED`

or:

`INTEGRATION / MANUAL COVERAGE`

The Jira coverage report must still show the AC so that it is never silently omitted.

---

# 58. USE EXISTING DOMAIN WORKFLOWS BEFORE INVENTING NEW ONES

Before creating a new workflow abstraction, inspect existing happy-path and regression implementations.

Examples:

Plasma Complete:
reuse established Plasma Complete pipeline.

Microbiome:
reuse established Microbiome happy path and LabQC behavior.

FRAX:
reuse established FRAX conventions.

GEL:
reuse existing Gel happy-path/regression workflow.

Do not build:

`GenericCompleteLabWorkflow`

simply because several workflows appear similar.

Reuse established domain behavior first.

Generalization requires genuine repeated behavior and must preserve domain-specific business rules.

---

# 59. REPORT EXACT WORKFLOW FAILURE LOCATION

Failure reporting must identify the actual business stage.

BAD:

`Scenario failed.`

BETTER:

`EXNGS-XXXX | Plasma Complete | LabQC | Sample Stats | Expected Data Analyst access = Enabled | Actual = Access Denied`

The objective is that the user can immediately determine:

WHAT failed
WHERE it failed
WHAT was expected
WHAT actually happened

without searching through Java stack traces.

---

# 60. STORY COMPLETION DASHBOARD

Before Jira delivery, produce a compact completion view:

## STORY AUTOMATION STATUS

Story: `EXNGS-XXXX`

Coverage: `4/4 AC accounted for`

Automation:
`✅ DONE`

Dry Run:
`✅ DONE`

UI Execution:
`✅ DONE`

Assertions:
`✅ DONE`

Regression:
`✅ DONE`

Evidence:
`✅ DONE`

Jira Test Case:
`✅ DONE`

Jira Report:
`✅ DONE`

Final Status:

`PASSED`

If something remains unresolved:

UI Execution:
`⛔ BLOCKED`

Reason:
`LabQC service unavailable`

Final Status:

`IMPLEMENTED — EXECUTION BLOCKED`

Never display all green checkmarks when an actual required completion gate was not completed.

---

# 61. FINAL COMPLETION GATE

A Jira automation story is complete ONLY when:

* All Jira information has been reviewed.
* Every AC has a documented disposition.
* Relevant workflow stages have been identified.
* Existing framework reuse has been evaluated.
* Feature steps clearly represent the business flow.
* Meaningful actions have assertions.
* Automation compiles.
* Dry-run passes.
* Required UI execution has completed.
* No unresolved Three Failure Gate exists.
* Relevant regression has completed.
* Evidence has been reviewed.
* Coverage checklist accurately reflects completion.
* Jira Test Case reflects actual automated coverage.
* Execution report has been generated.
* Required screenshots/evidence are associated with coverage.
* Jira delivery is complete according to the project's supported Jira workflow.

Only then:

`PASSED`

Otherwise use the appropriate status:

`IMPLEMENTED — EXECUTION BLOCKED`

`USER INTERVENTION REQUIRED`

`FAILED — APPLICATION DEFECT SUSPECTED`

`PARTIAL COVERAGE — <reason>`

Never convert an incomplete story into PASSED merely to close the workflow.
