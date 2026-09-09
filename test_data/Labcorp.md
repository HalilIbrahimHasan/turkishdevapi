# LAB AUTOMATION ENGINEERING CONTRACT

## Java + Selenium + Cucumber + Maven + Jira

This document defines the mandatory operating rules for all automation development performed in this repository.

Treat these instructions as a project-level engineering contract.

The objective is not simply to make a test pass.

The objective is to create automation that is:

* Traceable to Jira acceptance criteria
* Easy to review
* Easy to maintain
* Easy to debug
* Easy to report
* Compatible with the existing automation architecture
* Reusable across future stories
* Deterministic and stable
* Supported by clear execution evidence

Every new Jira story must follow the complete lifecycle described below.

---

# 1. PRIMARY RULE: UNDERSTAND BEFORE IMPLEMENTING

Before writing or modifying code for a Jira story, inspect all available Jira information related to that story.

Review:

* Story title
* Description
* Acceptance Criteria
* Screenshots
* Attachments
* Comments
* Linked stories
* Related defects
* Existing test cases
* Business rules
* Edge cases
* Any examples included in Jira
* Any UI screenshots showing expected behavior
* Any recent comments that modify or clarify the original acceptance criteria

Do not automate only from the Jira title or only from the Acceptance Criteria section.

Build a complete understanding of the business requirement first.

Before implementation, internally create a mapping similar to:

Jira Story
→ Acceptance Criterion
→ Business Rule
→ Scenario
→ Feature Step
→ Step Definition
→ Page/Component Method
→ Assertion
→ Execution Evidence

Every acceptance criterion must be accounted for.

No acceptance criterion may silently be skipped.

If a requirement cannot be automated, explicitly identify it and document why.

---

# 2. REPOSITORY DISCOVERY IS REQUIRED

Before creating new automation, inspect the existing repository.

Review relevant areas including:

* Existing feature files
* Step definitions
* Page Objects
* Component Objects
* Utilities
* Helpers
* Hooks
* Driver management
* Configuration
* Test data management
* Reporting utilities
* Screenshot utilities
* Logging utilities
* Wait utilities
* API helpers if applicable
* Existing Jira integrations
* Existing reusable steps
* Existing assertions
* Maven configuration
* Cucumber configuration
* Tags
* Naming conventions
* Folder/package structure

Search the repository before creating new classes or methods.

Always prefer:

REUSE
→ EXTEND
→ REFACTOR SAFELY
→ CREATE NEW

Do not create duplicate implementations when suitable reusable functionality already exists.

---

# 3. NEVER CREATE A MEGA STEP

This is one of the most important rules in this project.

Never take an entire Acceptance Criterion and hide its implementation inside one generic Cucumber step.

BAD:

Given I complete the enrollment workflow

Where the Java implementation performs:

* Login
* Search
* Select patient
* Open page
* Enter data
* Save
* Validate result

This is prohibited.

Instead, break the business flow into meaningful, observable Cucumber steps.

GOOD:

Given the user is logged into the application
And the user navigates to Patient Search
When the user searches for patient "<patientId>"
And the user opens the matching patient record
And the user selects the Enrollment tab
And the user enters the required enrollment information
And the user submits the enrollment
Then the enrollment should be saved successfully
And the enrollment status should be displayed as "<expectedStatus>"

Each important business action must be independently represented.

The feature file should tell a reviewer what was automated without requiring them to read Java code.

---

# 4. FEATURE FILES MUST REPRESENT BUSINESS TRACEABILITY

Every meaningful action related to a Jira acceptance criterion should appear explicitly in the feature file whenever practical.

The feature file is not merely an execution script.

It is also a human-readable record of coverage.

Someone reviewing the feature should be able to answer:

* Which Jira requirement is covered?
* Which behavior is being tested?
* Which actions are performed?
* Which result is expected?
* Where did the test fail?

Avoid vague steps such as:

And everything is configured correctly

And I complete the workflow

And the values are validated

Prefer explicit business language.

---

# 5. BREAK ACCEPTANCE CRITERIA INTO TRACKABLE STEPS

For every Jira Acceptance Criterion:

1. Identify the business condition.
2. Identify prerequisites.
3. Identify user actions.
4. Identify system responses.
5. Identify validation points.
6. Identify negative or boundary conditions where relevant.
7. Create individually traceable Cucumber steps.

The goal is that when someone reviews the feature file they can clearly see:

Acceptance Criterion 1 → Covered
Acceptance Criterion 2 → Covered
Acceptance Criterion 3 → Covered

Do not compress several unrelated acceptance criteria into one Scenario unless the business flow genuinely requires it.

---

# 6. USE BACKGROUND FOR STABLE REUSABLE PRECONDITIONS

Many scenarios contain repeated setup actions that already exist in the framework.

Examples may include:

* Login
* Selecting environment
* Navigating to a common application area
* Selecting a standard organization
* Establishing common test data
* Opening a commonly used starting page
* Performing standard prerequisite configuration

When these steps are shared across the scenarios in a feature and do not represent the new behavior being tested, move or reuse them in `Background:` where appropriate.

Example:

Feature: Patient Enrollment Validation

Background:
Given the user is authenticated
And the user has selected the required laboratory
And the user is on the Patient Management page

Scenario: Validate enrollment status after submission
When the user searches for patient "<patientId>"
And the user opens the Enrollment section
And the user submits a new enrollment
Then the enrollment status should be "Active"

The Scenario should emphasize the NEW behavior being implemented.

Do not move important story-specific actions into Background merely to shorten scenarios.

Background must represent stable prerequisites, not hide business logic.

---

# 7. REUSE EXISTING STEPS WHEN THEY EXPRESS THE SAME BUSINESS ACTION

Before creating a new step definition, search the existing repository.

If a step already exists and accurately describes the required business action:

Reuse it.

Do not create:

Given the user logs into Labcorp

if an equivalent reliable step already exists such as:

Given the user is logged into the application

unless the business behavior is genuinely different.

Avoid duplicate step definitions with slightly different wording.

---

# 8. ASSERT EVERY MEANINGFUL UI ACTION

Every important step that changes or reads application state should have an appropriate validation.

Do not assume Selenium successfully clicking an element means the business action succeeded.

Examples:

Navigation action:
Verify expected page, header, URL, breadcrumb, component, or unique page indicator.

Search:
Verify results are displayed and the expected record exists.

Selection:
Verify selected value/state.

Save:
Verify success notification and/or persisted state.

Update:
Verify updated value is displayed or stored.

Deletion:
Verify record/state is no longer available.

Status transition:
Verify actual status equals expected status.

Modal:
Verify modal opened or closed as expected.

Table action:
Verify expected row or updated value.

Download:
Verify expected file/event where technically possible.

The purpose is to make failures highly localized.

A failure should reveal the exact business step that failed.

---

# 9. ASSERTIONS MUST PROVIDE USEFUL FAILURE MESSAGES

Assertions must clearly show:

* Jira Story
* Scenario
* Step or business action
* Expected value
* Actual value
* Relevant record identifier when available

BAD:

Assertion failed

GOOD:

Story LAB-1234 | Patient Enrollment | Expected Status: ACTIVE | Actual Status: PENDING | Patient ID: 123456

Failure messages must reduce debugging time.

---

# 10. DO NOT USE HARD-CODED SLEEPS

Never introduce arbitrary waits such as:

Thread.sleep(5000)

unless there is an extraordinary documented reason.

Use the existing project wait strategy.

Prefer:

* Explicit waits
* Expected conditions
* Polling utilities
* Existing fluent wait helpers
* Application-specific synchronization utilities

Automation must wait for application state, not arbitrary time.

---

# 11. FOLLOW PAGE OBJECT / COMPONENT ARCHITECTURE

Do not place raw Selenium implementation directly inside feature files.

Avoid placing complex Selenium logic directly in step definitions when a Page Object or Component Object is appropriate.

Preferred responsibility:

Feature File
→ Business behavior

Step Definition
→ Coordination and readable business intent

Page / Component Layer
→ UI interaction and element behavior

Utility Layer
→ Generic reusable technical behavior

Assertions / Validation Layer
→ Meaningful validations when architecture supports it

Keep responsibilities separated.

---

# 12. LOCATOR RULES

Before adding a new locator:

Search whether the element already exists.

Prefer stable selectors in approximately this order where applicable:

1. Stable unique IDs
2. Approved data-test / automation attributes
3. Stable name attributes
4. Semantically stable CSS
5. Carefully scoped XPath

Avoid brittle absolute XPath.

BAD:

/html/body/div[4]/div[2]/div[3]/button[1]

Avoid selectors based only on transient styling classes.

A locator must represent the UI element, not the current DOM accident.

---

# 13. DO NOT BREAK EXISTING AUTOMATION

When implementing a new Jira story:

Preserve existing behavior.

Do not unnecessarily rename:

* Existing steps
* Existing methods
* Existing classes
* Existing packages
* Existing feature files
* Existing tags
* Existing configuration

Before changing reusable code, determine what existing scenarios depend on it.

If extending existing functionality can solve the requirement safely, prefer extension over destructive modification.

If refactoring is necessary:

* Preserve existing behavior
* Run impacted tests
* Document material changes

---

# 14. MAKE ENGINEERING DECISIONS AUTONOMOUSLY

After understanding the requirement and repository, make reasonable implementation decisions without stopping for trivial questions.

Do not ask for permission for routine engineering decisions such as:

* Where a new Page Object method belongs
* Whether an existing helper can be reused
* Whether a reusable utility should be extracted
* Whether duplicate logic should be consolidated
* Whether selectors should move to the appropriate Page Object
* Whether common setup belongs in Background

Use the repository conventions as the primary guide.

However:

Never invent a business rule that Jira does not support.

If business behavior is genuinely ambiguous and cannot be determined from:

* Jira
* Existing automation
* Application behavior
* Screenshots
* Comments
* Attachments
* Related tests

flag the ambiguity clearly rather than silently guessing.

---

# 15. SCENARIO VS SCENARIO OUTLINE

Use `Scenario` when testing one concrete business flow.

Use `Scenario Outline` when the same behavior must be validated against multiple meaningful datasets or rule variations.

Do not use Scenario Outline merely to make a test look reusable.

Example:

Scenario Outline: Validate supported specimen types
When the user selects specimen type "<specimenType>"
Then the corresponding processing option should be "<processingOption>"

Examples:
| specimenType | processingOption |
| Blood        | Standard         |
| Urine        | Standard         |
| Tissue       | Specialized      |

Examples must represent legitimate business variations.

---

# 16. POSITIVE, NEGATIVE, AND BOUNDARY COVERAGE

Do not limit automation to only the happy path when the Acceptance Criteria implies additional behavior.

Evaluate whether the story requires:

* Positive case
* Negative case
* Required field validation
* Invalid input
* Boundary value
* Permission-based behavior
* Empty state
* Duplicate data
* Existing record
* Different status
* Cancel behavior
* Save behavior
* Edit behavior
* Read-only behavior
* Error handling

Only add cases supported by business requirements or strongly established application behavior.

Do not manufacture meaningless tests merely to increase test count.

---

# 17. CREATE A COVERAGE MATRIX BEFORE FINALIZING

For every story, maintain an internal mapping:

| Jira AC | Scenario   | Steps              | Assertions             | Status  |
| ------- | ---------- | ------------------ | ---------------------- | ------- |
| AC1     | Scenario 1 | Given/When/Then... | UI/Business Assertions | Covered |
| AC2     | Scenario 2 | Given/When/Then... | UI/Business Assertions | Covered |
| AC3     | Scenario 3 | Given/When/Then... | UI/Business Assertions | Covered |

Before declaring development complete:

Every Acceptance Criterion must be:

* Covered
* Not Applicable with explanation
* Blocked with explanation

Never leave an AC unmapped.

---

# 18. TEST DATA MUST BE CONTROLLED

Reuse the repository's existing test-data strategy.

Avoid unnecessary hard-coded production-like records.

Prefer:

* Existing test data fixtures
* Configuration
* Scenario Outline Examples
* Data factories
* Approved test accounts
* Dynamic data generators

When test data is created by the automation, clean it up when appropriate.

Tests must be independently runnable wherever practical.

One scenario should not depend on another scenario having executed first unless the framework explicitly designs such dependency.

---

# 19. EXECUTE THE AUTOMATION AFTER IMPLEMENTATION

Implementation is not complete after code compilation.

After developing the story:

1. Compile the project.
2. Run applicable unit/helper tests if available.
3. Run the specific Cucumber scenario.
4. Run all scenarios created for the story.
5. Run relevant regression scenarios impacted by modified reusable code.
6. Execute the workflow against the UI.
7. Verify assertions.
8. Review screenshots.
9. Review logs.
10. Review generated reports.

Continue until the implementation is stable or a genuine external blocker is identified.

Do not stop merely because the first test execution fails.

---

# 20. DEBUG FAILURES TO ROOT CAUSE

When a test fails, inspect:

* Stack trace
* Selenium errors
* Cucumber step output
* Screenshots
* Browser state
* Application message
* Network/API information if available through current framework
* Existing logs
* Locator reliability
* Timing/synchronization
* Test data
* Environment issues
* Previous step state

Classify failures when useful:

* Automation defect
* Application defect
* Test data issue
* Environment issue
* Requirement mismatch
* Locator issue
* Timing issue
* Dependency issue

Fix automation defects before generating the final report.

Do not hide failures with retries unless the existing framework deliberately uses controlled retry logic.

---

# 21. SCREENSHOT AND FAILURE EVIDENCE

Use the existing screenshot/reporting infrastructure.

At minimum:

On failure:

* Capture screenshot
* Record failing step
* Record expected result
* Record actual result
* Record exception/error
* Record relevant test data or business identifier

Where the framework already supports screenshots for important successful validations, use them consistently.

Do not flood reports with unnecessary screenshots.

Evidence should be useful.

---

# 22. REPORT ONLY TEST CASE SUMMARY + EXECUTION SUMMARY

For Jira attachment purposes, generate a concise professional report.

Do not create an excessively technical developer report.

The report should focus on:

## Section A — Story Information

* Jira Story ID
* Story Title
* Execution Date
* Environment
* Browser if relevant
* Automation Status

## Section B — Test Case Coverage Summary

For each Acceptance Criterion show:

* AC reference
* Scenario/Test Case
* Covered steps
* Expected result
* Coverage status

Example:

| AC  | Test Scenario                | Covered Behavior                 | Status  |
| --- | ---------------------------- | -------------------------------- | ------- |
| AC1 | Validate patient search      | Search and result verification   | Covered |
| AC2 | Validate enrollment creation | Enrollment submission and status | Covered |
| AC3 | Validate required field      | Required field message           | Covered |

## Section C — Execution Summary

Include:

* Total scenarios
* Passed
* Failed
* Skipped
* Pass percentage
* Execution duration
* Final status

## Section D — Expected vs Actual

For meaningful validations:

| Scenario              | Expected        | Actual          | Result |
| --------------------- | --------------- | --------------- | ------ |
| Enrollment submission | Status = Active | Status = Active | PASS   |

Keep the report concise enough for Jira reviewers.

---

# 23. PASS RATE PIE CHART

Include a small pie chart in the Jira execution report representing:

* Passed
* Failed
* Skipped, when applicable

Example:

Total Tests: 12
Passed: 11
Failed: 1
Skipped: 0
Pass Rate: 91.67%

The chart should be readable when attached to Jira.

Do not make the report visually excessive.

---

# 24. TRACE REPORT BACK TO THE JIRA STORY

The report must explicitly show which Jira Acceptance Criteria were automated.

The report is evidence that:

Story Requirement
→ Automated Test
→ Executed Result

A reviewer should not need to inspect source code to determine coverage.

---

# 25. JIRA TEST CASE CREATION

After successful implementation and execution:

Create or update the appropriate Jira Test Case using the project's current Jira workflow.

The Jira Test Case should contain:

* Clear test title
* Story reference
* Preconditions
* Test steps
* Expected result per relevant action
* Test data where appropriate
* Automation status
* Execution result

Do not create a vague test case consisting of only:

Step: Execute automation
Expected: Test passes

The Jira test case should reflect meaningful business steps.

---

# 26. ATTACH EXECUTION EVIDENCE TO JIRA

After successful execution:

Attach the execution summary/report to the appropriate Jira story/test case according to existing team conventions.

Where supported, include:

* Execution report
* Relevant screenshot evidence
* Test result reference
* Build/execution identifier
* Automation status

Do not attach unnecessary raw artifacts unless the current Jira workflow requires them.

The primary Jira attachment should remain a concise Test Case + Execution Summary report.

---

# 27. DO NOT CLAIM SUCCESS UNTIL UI EXECUTION PASSES

Do not declare a story complete because:

* Code compiles
* Step definitions exist
* Feature file exists
* Maven build succeeds without executing the target test
* Static analysis succeeds

Completion means:

Requirement analyzed

* Coverage mapped
* Automation implemented
* UI executed
* Assertions passed
* Relevant regression checked
* Evidence generated
* Jira test case/report prepared

If the application is unavailable or a legitimate external dependency blocks execution, state:

`IMPLEMENTED — EXECUTION BLOCKED`

Do not report it as PASSED.

---

# 28. TAGGING AND TRACEABILITY

Follow existing project tagging conventions.

Where compatible with current framework, preserve direct Jira traceability using tags such as:

@LAB-1234

or the repository's equivalent standard.

Do not invent an incompatible tagging scheme if the repository already has one.

---

# 29. LOGGING

Important actions should produce useful logs.

Where supported, log:

* Scenario
* Step/business action
* Page/component
* Key identifier
* Important expected value
* Important actual value
* Failure reason

Avoid useless noise such as logging every getter or every Selenium command.

Logs should support diagnosis.

---

# 30. IDEMPOTENCY AND TEST ISOLATION

Whenever possible:

* A scenario should run independently.
* Re-running a scenario should not corrupt the environment.
* Existing data should not cause unpredictable behavior.
* Cleanup should occur when test-created data requires it.
* Test execution order should not determine outcome.

Avoid hidden scenario dependencies.

---

# 31. DO NOT OVERENGINEER

Do not introduce a new abstraction, framework, utility, factory, manager, or pattern merely because it is technically possible.

Create new architecture only when:

* Existing architecture cannot cleanly support the requirement
* Reuse across several tests is likely
* It removes meaningful duplication
* It improves maintainability
* It follows existing repository patterns

Simple and maintainable is preferred over clever.

---

# 32. CODE QUALITY

All new code must:

* Follow current project naming conventions
* Avoid duplicate logic
* Use meaningful names
* Keep methods focused
* Avoid excessively large methods
* Avoid deeply nested logic where possible
* Keep selectors in appropriate page/component classes
* Keep business language in feature files
* Keep low-level Selenium logic out of feature files
* Preserve compatibility with Java, Selenium, Cucumber, and Maven versions used by the repository

---

# 33. NO SILENT MODIFICATION OF BUSINESS EXPECTATIONS

Never change an expected result merely because the application currently behaves differently.

If:

Expected according to Jira = A

but

Actual UI behavior = B

the automation should identify the mismatch.

Do not modify the test to expect B merely to make it pass.

Potential application defects must remain visible.

---

# 34. STORY IMPLEMENTATION WORKFLOW

For every new Jira story, follow this exact sequence:

### Phase 1 — Jira Analysis

Read:

* Story
* Description
* Acceptance Criteria
* Comments
* Screenshots
* Attachments
* Related issues
* Existing test cases

### Phase 2 — Repository Analysis

Inspect:

* Existing feature files
* Existing steps
* Pages/components
* Utilities
* Assertions
* Reporting
* Test data
* Hooks
* Jira integration

### Phase 3 — Coverage Design

Create:

* AC mapping
* Scenarios
* Scenario Outlines where useful
* Background design
* Expected assertions
* Required test data
* Positive/negative coverage

### Phase 4 — Feature Development

Write explicit Cucumber steps.

Do not use mega steps.

### Phase 5 — Implementation

Reuse or extend:

* Step definitions
* Page Objects
* Components
* Utilities
* Test data
* Assertions

Create new components only where justified.

### Phase 6 — Validation

Run:

* Compilation
* Target scenarios
* Story test suite
* Relevant regression

### Phase 7 — Failure Resolution

Review:

* Logs
* Screenshots
* Error messages
* Selectors
* Waits
* Data
* Application behavior

Fix automation defects and repeat execution.

### Phase 8 — Coverage Verification

Confirm every Jira Acceptance Criterion has a disposition.

### Phase 9 — Reporting

Generate:

* Test Case Summary
* Execution Summary
* Expected vs Actual
* Pass/fail counts
* Pass percentage
* Pie chart

### Phase 10 — Jira

Create/update:

* Test Case
* Execution result
* Story association
* Report attachment
* Evidence

Only after these phases is the story considered automation complete.

---

# 35. REQUIRED FINAL SELF-REVIEW

Before completing any Jira story, ask internally:

* Did I read every Acceptance Criterion?
* Did I review Jira screenshots, attachments, and comments?
* Did I inspect existing repository implementations?
* Did I reuse existing steps where appropriate?
* Did I avoid creating mega steps?
* Can each important business action be seen in the feature file?
* Did I put stable common prerequisites in Background where appropriate?
* Does every meaningful action have validation?
* Are failure messages useful?
* Did I avoid hard-coded sleeps?
* Did I preserve existing architecture?
* Did I avoid duplicated locators and utilities?
* Did I cover applicable negative/boundary behavior?
* Did I run the actual UI test?
* Did I inspect failures and logs?
* Did I verify impacted regression behavior?
* Is every AC mapped?
* Is the Jira Test Case meaningful?
* Does the report show expected vs actual?
* Does the report include pass rate?
* Is execution evidence ready for Jira?

If any answer is NO, the work is not complete.

---

# 36. FEATURE FILE DESIGN EXAMPLE

Avoid:

Scenario: Verify order
When I process the order
Then the order should be correct

Preferred:

Background:
Given the user is authenticated
And the user is on the Order Management page

Scenario: Create an order for a valid patient
When the user searches for patient "123456"
And the patient record is displayed
And the user opens the Orders section
And the user selects test "CBC"
And the user enters the required order information
And the user submits the order
Then a successful order confirmation should be displayed
And the generated order number should be visible
And the order status should be "Submitted"

Each meaningful action is visible and individually diagnosable.

---

# 37. FINAL COMPLETION RESPONSE FORMAT

At the end of each Jira story implementation, provide a concise engineering summary in this format:

## Story

Jira: LAB-XXXX
Title: ...

## Coverage

Acceptance Criteria: X/X Covered

## Automation

Scenarios Created: X
Scenario Outlines: X
New Steps: X
Reused Steps: X

## Framework Changes

Pages Modified/Created: ...
Utilities Modified/Created: ...
Other Changes: ...

## Execution

Total: X
Passed: X
Failed: X
Skipped: X
Pass Rate: XX%

## Regression

Relevant regression executed: YES/NO
Result: ...

## Jira

Test Case Created/Updated: YES/NO
Execution Report Generated: YES/NO
Report Attached: YES/NO

## Final Status

PASSED

or

IMPLEMENTED — BLOCKED: <exact external blocker>

or

FAILED — APPLICATION DEFECT SUSPECTED: <clear evidence>

Do not use vague completion messages such as:

"Implementation completed successfully."

Provide evidence.

---

# 38. CORE PHILOSOPHY

The feature file must tell the business story.

The Java implementation must support that story.

Assertions must prove the story.

The execution report must provide evidence.

Jira must provide traceability.

Never optimize for fewer Cucumber steps.

Optimize for:

CLARITY

* TRACEABILITY
* DEBUGGABILITY
* REUSABILITY
* MAINTAINABILITY
* BUSINESS COVERAGE

The final automation should allow another engineer, QA analyst, developer, product owner, or auditor to open the Jira story and understand exactly:

What requirement was covered,
how it was automated,
what was executed,
what was expected,
what actually happened,
and whether the story passed.
