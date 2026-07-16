# 834 Raw Ingestion Validation and Initial Comparison with Vimo/Sisense Business Metrics

Hi Hari,

I completed the raw 834 ingestion validation and an initial comparison
against the Vimo/Sisense enrollment report. I wanted to share the
current findings before we proceed with any additional business-rule
assumptions.

------------------------------------------------------------------------

# Executive Summary

The raw ingestion pipeline has been fully validated from the XML source
through Azure SQL.

We compared our Azure data against the Vimo/Sisense report using two
different approaches:

1.  **Annual Distinct Counts**
2.  **Latest Status (CONFIRM / CANCEL / TERM / UNMAPPED)**

Neither approach fully reproduces the Sisense metrics, which suggests
that the remaining differences are primarily related to business
definitions rather than XML parsing or data ingestion.

## Initial Comparison Summary

  ----------------------------------------------------------------------------
  Metric                 Our Database         Vimo / Sisense        Difference
  --------------- ------------------- ---------------------- -----------------
  **2025                **1,526,788**            **986,505**        **+540,283
  Enrollments**                                                     (+54.8%)**

  **2025                **1,520,172**          **1,295,282**        **+224,890
  Enrollees**                                                       (+17.4%)**

  **2026                  **824,989**            **697,774**        **+127,215
  Enrollments**                                                     (+18.2%)**

  **2026                  **853,341**            **970,746**        **−117,405
  Enrollees**                                                       (−12.1%)**
  ----------------------------------------------------------------------------

## Raw XML Successfully Loaded

  Coverage Year     Raw Transaction Rows
  --------------- ----------------------
  **2025**                 **2,141,037**
  **2026**                 **1,029,577**
  **Total**                **3,170,614**

**Please note:** The Sisense report displays business-level aggregated
Enrollment and Enrollee metrics, not raw XML transaction rows.
Therefore, the raw row counts above are included only to demonstrate
ingestion completeness and should not be compared directly with the
Sisense totals.

------------------------------------------------------------------------

# 1. Raw 834 Ingestion Validation

### 2025

-   Files discovered: **42,513**
-   Files successfully loaded: **42,458**
-   Duplicate files skipped by file hash: **55**
-   Failed files: **0**
-   Raw rows loaded: **2,141,037**

### 2026

-   Files successfully loaded: **28,291**
-   Failed files: **0**
-   Raw rows loaded: **1,029,577**
-   The two previously failed files were successfully reprocessed and
    validated.

Additional validation performed:

-   Every discovered XML file is tracked in the file log.
-   Duplicate detection uses **file_hash**.
-   Retry processing was validated successfully.
-   Row counts between `inbound_automation` and
    `inbound_automation_file_log` match exactly.
-   No duplicate file hashes exist.
-   No NULL Member IDs were found.
-   Only two issuers contain NULL Policy IDs, which appears to be source
    data rather than a parser issue.
-   XML spot checks confirmed that every enrollee record was
    successfully captured.

Based on these validations, I do not currently see evidence of raw XML
parsing or Azure loading issues.

------------------------------------------------------------------------

# 2. Raw Data Stored in Azure

The raw Azure table stores one row per parsed enrollee transaction while
preserving complete XML lineage.

Metadata enrichment applied during ingestion: - Issuer normalization -
Insurance type normalization - Enrollee status mapping - Coverage year
derivation - Source file metadata - File year/month metadata - Raw JSON
payload - Raw record hash - Complete ingestion lineage

Business Ready logic **not** applied during raw ingestion: - Business
month reassignment - Transaction deduplication - Maintenance-chain
collapse - Lifecycle selection - Prior-year filtering - Model H
aggregation - Business-ready enrollment collapse

------------------------------------------------------------------------

# 3. Comparison Approach

The comparison was generated directly from Azure SQL using:

-   HIOS Issuer ID
-   Insurance Type
-   Coverage Year

Enrollment key: - `policy_id` - fallback: `health_coverage_policy_no`

Enrollee key: - `member_id` - fallback: `issuer_indiv_identifier` -
fallback: `exchg_assigned_enrollee_id`

No additional business rules were applied in this initial comparison.

------------------------------------------------------------------------

# 4. Latest Status Analysis

A second comparison was generated using only the latest transaction for
each enrollment and enrollee.

Statuses evaluated: - CONFIRM - CANCEL - TERM - UNMAPPED

This comparison includes: - Enrollment Total - Enrollee Total - Latest
CONFIRM - Latest CANCEL - Latest TERM - Latest UNMAPPED

------------------------------------------------------------------------

# 5. Key Findings

-   Raw ingestion appears complete and reliable.
-   XML parsing and Azure loading do not indicate data loss.
-   2025 differences remain significant.
-   2026 aligns much more closely with Sisense than 2025.
-   Latest CONFIRM does not appear to be equivalent to Sisense
    Effectuated.
-   CANCEL + TERM + UNMAPPED do not align with Sisense Pending.
-   Mixed issuer-level differences suggest remaining gaps are driven by
    business definitions rather than ingestion.

------------------------------------------------------------------------

# 6. Attachments

-   Azure Annual Summary
-   Latest Status Comparison
-   Vimo / Sisense Report
-   Raw Ingestion Validation Reports
-   Pipeline Business Summary Outputs

------------------------------------------------------------------------

# 7. Questions

1.  Which business identifier defines **Enrollment Total**?
2.  Which identifier defines **Enrollee Total**?
3.  How is **Effectuated** determined?
4.  Which date determines **Coverage Year**?
5.  Is the annual report based on annual distinct counts, monthly
    rollups, or a point-in-time snapshot?

------------------------------------------------------------------------

# Current Conclusion

-   The raw ingestion process appears complete and reliable.
-   XML parsing and Azure loading do not currently indicate data loss.
-   Two independent comparison methods (Annual Distinct and Latest
    Status) were evaluated.
-   Neither reproduces the Sisense metrics, suggesting the remaining
    differences are driven primarily by business definitions rather than
    ingestion or parsing.
-   The attached comparisons should help identify which additional
    business rules or Vimo-specific definitions are required to fully
    align the results.

Throughout this analysis, we intentionally avoided making assumptions
about Vimo's business rules. Instead, we validated the raw ingestion
first and progressively tested multiple business interpretations so each
remaining difference could be isolated, measured, and explained.

Thank you,

**Selma**
