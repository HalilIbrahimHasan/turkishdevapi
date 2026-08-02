37301 Deep Dive – Evidence Summary, Findings, and Questions for Next Investigation

Hi Hari, Swathi, Taylor, and Chandra,

Following our investigation into the gaps between Automation (raw inbound 834 data) and Enrollments_TEST/UI, we completed a detailed record-level analysis for Issuer 37301 (Educators Health Plans Life, Accident and Health, Inc.).

Below is a summary of the analysis, supporting evidence, and the areas where we would appreciate clarification before proceeding further.

1. Scope of Investigation

We focused on:

Issuer 37301
Coverage Year 2026
Raw inbound automation records (dbo.inbound_automation)
Business records (dbo.Enrollments_TEST)
UI observations
FFM migration investigation (PY242526_Applicants_test)
2. Raw Automation Validation

The raw inbound pipeline continues to appear healthy.

Current raw population:

Metric	Value
Total 2026 raw rows	1,029,577

The pipeline validation confirms:

all processed inbound files are tracked,
duplicate files are prevented by file hash,
parser loads one row per inbound enrollee transaction,
raw data is inserted successfully,
no evidence of broad parser or loading failures has been identified.
3. Initial Gap

For issuer 37301 (Coverage Year 2026):

Source	Policies	Enrollees
Enrollments_TEST	3,900	5,450
Raw Automation	1,452	1,453

This prompted a detailed record-level comparison.

4. Cross Validation Results

After comparing individual enrollee and policy identifiers, we identified three categories.

A. Policy and Enrollee both found

These records exist in both systems.

Example:

Policy 211121265
Policy 1000289327

These confirm that inbound processing and automation successfully captured the records.

B. Enrollee found, Policy missing

Examples include:

211121283
333747
333577
212195806
583404

In these cases:

the enrollee exists in Automation,
but the policy identifier does not.

This suggests that the individual exists in inbound data while the business policy differs or was created through another business process.

C. Neither Policy nor Enrollee found

Examples include multiple records from Household 97970.

Neither the policy identifier nor the enrollee identifier exists in inbound automation.

These records currently appear to exist only within the business/UI side.

5. Detailed Case Investigation

We investigated one specific enrollee.

Enrollee:

1000162542

Business records show:

Policy	Issuer	Status
211121265	60224	Terminated
1000289327	89942	Pending
211121283	37301	Enrolled

Automation investigation:

Issuer	Found
60224	Yes
89942	Yes
37301	No

Additional verification:

Searching inbound automation by:

policy id = 211121283
enrollee id = 1000162542 (restricted to issuer 37301)

returned no records.

This indicates that the enrollee is successfully processed from other issuers, while no inbound 834 record could be located for the Educators Dental enrollment.

6. FFM Migration Investigation

We also investigated the highlighted households from the migration analysis.

Households:

3966
97970
98174

Applicants were confirmed to exist across:

2024
2025
2026

using:

PY242526_Applicants_test

This confirms applicant continuity across years.

However,

this does not demonstrate that an inbound 834 was received for each policy created during annual enrollment or redetermination.

7. Current Evidence

Based on the investigation completed so far, our current evidence indicates:

Automation successfully captures inbound 834 records that are available.
The parser successfully processed the enrollee when inbound records existed (examples: issuers 60224 and 89942).
For the Educators Dental example investigated, neither the policy nor the issuer-specific enrollee record could be located within the inbound automation data.
We therefore do not currently have evidence suggesting parser or ingestion loss for this example.
The gap appears more consistent with records that were not available within the inbound 834 files received by automation.
8. Questions / Clarifications

As we continue the investigation, we would appreciate clarification on several business questions.

1.

What do the different values in the Source column represent?

Examples:

ON
CN
RR
EDE
RF

Do these represent:

enrollment creation channel,
application source,
migration source,
or another business process?
2.

For annual redetermination or migrated households,

are there scenarios where business records are created without a corresponding inbound 834 being received from the issuer?

3.

For policy 211121283, is there an expected inbound 834 transaction?

Or was this policy created through another business workflow?

4.

If available, is there another upstream source besides inbound 834 that contributes records to Enrollments_TEST?

Next Steps

Our proposed next steps are:

Continue classifying remaining missing policies into root-cause categories.
Compare additional issuers using the same methodology.
Trace selected policies through UI account activity, outbound records, inbound records, and business tables.
Continue validating whether missing records are absent from inbound 834 or originate through another business process.

Thank you everyone for your support throughout this investigation. We believe this approach is helping narrow the gap from a large population-level difference to specific record-level root causes, and we appreciate any guidance on the business processes behind the remaining unmatched records.

Best,

Selma Kazanci
