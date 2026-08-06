37301 Cross Validation Investigation – Automation vs Enrollments_TEST (Evidence Summary)

Hi Hari, Swathi, Taylor,

Following our previous discussions regarding the differences between Automation (raw inbound 834 data) and Enrollments_TEST/UI, I completed additional record-level validation using SQL, UI Enrollment History, Household Details, and original inbound 834 XML files.

The objective of this investigation was to determine whether the reported differences are caused by missing inbound 834 transactions or by differences in how enrollment information is represented across the available data sources.

Below is a summary of the findings supported by SQL validation, UI verification and raw inbound XML evidence.

Investigation Scope
Data Sources
Automation (Raw Inbound 834)
Enrollments_TEST
UI Enrollment History
UI Household Details
Original Inbound XML Files


Investigation Population

Swathi provided an FFM report containing approximately 6,168 records.

Since multiple enrollees can belong to the same policy, the report represents approximately 4,000+ unique Policy IDs.

The investigation was performed in two independent phases:

Phase A

Policies identified in Automation

Phase B

Policies not identified in Automation

Each phase was validated independently.


Evidence 1
Policy Validation Against Automation
Investigation

The unique Policy IDs from the FFM report were searched directly against Automation.

Result
Approximately 347 Policy IDs were successfully identified.
Every matching policy belonged to Issuer 37301.
Matching records were verified against the original inbound XML files.
Evidence

FFM Policy List
        │
        ▼
Automation Search
        │
        ▼
347 Matching Policies
        │
        ▼
Original XML Verified

Observation

This confirms that a portion of the reported FFM policies already exists within the inbound 834 
population and can be traced back to original XML transactions and UI records.

Evidence 2
Member-Level Analysis for Matching Policies

For the policies identified in Automation, enrollee-level comparison was performed.
image
Result
Category	                              Count

| Category                        |   Count |
| ------------------------------- | ------: |
| Matched Subscribers             | **292** |
| Business Only Subscribers       |  **22** |
| Business Only Spouse            | **118** |
| Business Only Child / Dependent | **185** |
| Other / Unmapped                |   **8** |

image instead
Evidence

347 Matching Policies
        │
        ▼
Member-Level Comparison
        │
        ▼
292 Subscriber Matches
        │
        ▼
Remaining differences primarily
Spouse / Child / Other

Observation

Within the policies identified in Automation, subscriber records represent the majority of successful enrollee matches.


Evidence 3
Household History Preserves Policy Lifecycle

Several households were manually investigated using UI Enrollment History.

image

Observation

The same household may contain multiple policy versions over time. This is critical and may explain old policies 
from previous years kept as all versions in Enrollment Test records and in UI also we are able to find new policies 
searching by old policy ids
Historical policy IDs continue to appear alongside newer policy versions within household history.


Evidence 4
Enrollment History Spans Multiple Coverage Years

The investigated households frequently contained enrollment activity across multiple coverage years.

Observed scenarios included:

2024 records
2025 renewals
2026 enrollments
Carrier transitions
Policy replacements
Terminations
Re-enrollments
Observation

Enrollment history represents a continuous household lifecycle rather than a single enrollment event.

Evidence 5
Investigation of Policies Not Found in Automation

To better understand the remaining differences, multiple Policy IDs that were not identified in Automation were selected from the beginning, middle and end of the FFM report.

This sampling approach was used to avoid focusing on isolated examples.

The following representative records were investigated:

image

Observation A

Searching by Policy ID consistently returned a valid policy in UI.

The policy itself exists within the business system.

Observation B

Although the Policy ID exists,

the expected FFM Enrollee ID was not attached to that policy.

Instead,

different household members were displayed.

Example

image 

Observation C

The expected enrollee frequently exists elsewhere in the system.

Several investigated enrollee IDs were located under different enrollment histories, different policies or different carrier transitions.

Observation D

The same behavior was observed while reviewing other issuers within UI.

In several examples, inbound activity existed for another issuer, while no corresponding inbound transaction was identified for Issuer 37301 for the same policy lifecycle.


Observation

These repeated patterns suggest that the reported Policy ID and Enrollee ID may both exist within the system, but not necessarily as the same Policy–Enrollee relationship.


Evidence 6
Policy and Enrollee Pair Validation

Representative examples were validated against:

Enrollments_TEST
Automation
Raw inbound XML

The following pattern was consistently observed.

Validation	Result
Policy exists	✅
Enrollee exists	✅
Exact Policy–Enrollee pair reproduced	❌
Exact pair found in raw inbound XML

example
Reported

image

The expected enrollee exists in the system but is associated with a different enrollment history.

Observation

Across the investigated examples, both Policy IDs and Enrollee IDs were found independently.

However, the reported Policy–Enrollee relationship itself could not be reproduced in either Enrollments_TEST or raw inbound XML.

Evidence Matrix
image

Current Investigation

The following scenarios continue to be investigated:

Remaining unmatched Policy IDs
Remaining unmatched Enrollee IDs
Coverage year transitions (2024–2026)
Legacy / FFM migration scenarios
Additional household lifecycle scenarios

Conclusion

Based on the evidence collected so far, the observed differences cannot be attributed to a single scenario.

The investigation confirms multiple repeatable patterns, including:

Policies that already exist in inbound Automation.
Strong subscriber-level matching within the identified Automation policies.
Household histories that preserve multiple policy generations and coverage years.
Policies that exist in UI but are associated with different enrollee relationships than those reported in the comparison.
Policy IDs and Enrollee IDs that exist independently, while the reported Policy–Enrollee relationship itself could not be reproduced in either Enrollments_TEST or raw inbound XML for the sampled cases.

The investigation will continue as we validate the remaining unmatched records and additional lifecycle scenarios.

Thank you.














