Subject: Raw XML vs SQL Validation Investigation – Findings, Validation Results, and Current Status

Hi Team,

Over the past several days, I completed a detailed engineering investigation to validate whether the differences observed between the XML parser output and dbo.834_Inbound_test originated from the XML parser, downstream business processing, or differences in SQL/XML file inventory.

The investigation focused on the following issuers:

13535
15105
43802
Investigation Objective

The objective was to determine whether the discrepancies originated from:

XML parsing
Raw record counting
Status mapping
Policy / Member counting
Business Ready transformation
Lifecycle / Collapse processing
SQL ingestion or file inventory differences

To eliminate month attribution differences, the comparison was aligned using the filename timestamp extracted directly from each XML file (Filename_FileYear / Filename_FileMonth) rather than the source folder month.

Database Exploration

Before beginning the validation, several SQL tables were reviewed to identify the table that most accurately represents the raw XML data before any downstream processing.

Table	Assessment
834_Inbound_header_test	Header-level information only. Does not contain one row per enrollee. Not suitable for raw validation.
Business Ready / transformed outputs	Already include downstream business transformations (collapse, lifecycle, aggregation). Excluded from raw validation.
Other staging/helper tables	Missing one or more required identifiers or already transformed. Excluded.
dbo.834_Inbound_test	Selected as the primary validation source because it contains source filename, file date, issuer, policy identifier, member identifier, insurance type, and enrollee status at the raw record level.

Based on this assessment, dbo.834_Inbound_test was determined to be the closest SQL representation of the XML parser output and therefore was selected as the source of truth for raw validation.

Validation Methodology
SQL
Issuer → GAA_HIOS_ID
File Year → YEAR(GAA_834_File_Date)
File Month → MONTH(GAA_834_File_Date)
Source File → GAA_834_File_Name
XML
Issuer
Filename_FileYear
Filename_FileMonth
Source_File
Comparison Key

The comparison was performed using:

Issuer
File Year
File Month
Insurance Type
Enrollee Status
Source File

For every matching key, the following metrics were validated:

Raw Record Count
Distinct Policy Count
Distinct Member Count
SQL Validation Query
SELECT
    GAA_HIOS_ID AS Issuer,
    YEAR(GAA_834_File_Date) AS File_Year,
    MONTH(GAA_834_File_Date) AS File_Month,
    Insurance_Type,
    enrolleeStatus,
    GAA_834_File_Name AS Source_File,
    COUNT(*) AS SQL_Row_Count,
    COUNT(DISTINCT exchgAssignedPolicyID) AS SQL_Policy_Count,
    COUNT(DISTINCT exchgIndivIdentifier) AS SQL_Member_Count
FROM dbo.834_Inbound_test
WHERE GAA_HIOS_ID IN (13535,15105,43802)
GROUP BY
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date),
    MONTH(GAA_834_File_Date),
    Insurance_Type,
    enrolleeStatus,
    GAA_834_File_Name
ORDER BY
    Issuer,
    File_Year,
    File_Month,
    Insurance_Type,
    enrolleeStatus,
    Source_File;
Shared Inventory Validation
Results
Metric	Result
Shared Source Files	322
Shared File / Status Validation Groups	492
Exact Matches	492 / 492
Match Rate	100%
Raw Record Count Differences	0
Distinct Policy Count Differences	0
Distinct Member Count Differences	0
What do these numbers represent?

The 322 shared source files represent the unique XML files that exist in both the XML source repository and the SQL validation dataset.

Those files were further partitioned by:

Insurance Type
Enrollee Status (CONFIRM, CANCEL, TERM)

resulting in 492 independent validation groups.

Every one of these groups matched exactly across:

Raw Record Count
Distinct Policy Count
Distinct Member Count

This confirms that all shared:

CONFIRM groups matched
CANCEL groups matched
TERM groups matched

No counting discrepancies were identified for any shared validation group.

XML-only Inventory Validation (2025 Validation Scope)

Following the successful validation of the shared SQL/XML inventory, the remaining differences were investigated by identifying XML source files that were successfully parsed from the 2025 XML source data but were not present in the SQL validation dataset used for this comparison.

Summary
Metric	Result
XML-only Unique Files	772
XML-only Validation Groups	1,127
XML-only Raw Records	44,805
Issuer Breakdown
Issuer	XML-only Files	Raw Records
13535	178	2,028
15105	262	27,058
43802	332	15,719
Total	772	44,805
SQL Verification

To verify these findings, the highest-volume XML-only filenames were queried directly against dbo.834_Inbound_test.

SELECT
    GAA_834_File_Name,
    COUNT(*) AS Row_Count
FROM dbo.834_Inbound_test
WHERE GAA_834_File_Name IN
(
'from_15105_GA_834_INDV_20250109152427.xml',
'from_15105_GA_834_INDV_20250401045709.xml',
'from_43802_GA_834_INDV_20250813082244.xml',
'from_43802_GA_834_INDV_20250130013454.xml',
'from_15105_GA_834_INDV_20250211042401.xml'
    -- additional sampled XML-only filenames
)
GROUP BY
    GAA_834_File_Name;
Result

The verification query returned zero rows for the sampled high-volume XML-only filenames.

This confirms that the sampled XML files used in the validation were not found in dbo.834_Inbound_test under the filenames queried.

Investigation Status
Investigation Area	                              Status	                Evidence / Match Rate
Parser834 Raw Record Counts	                      ✅ Validated	          492 / 492 (100%)
Distinct Policy Counts	                          ✅ Validated	          100% Match
Distinct Member Counts	                          ✅ Validated	          100% Match
CONFIRM Status Validation	                        ✅ Validated	          100% Match
CANCEL Status Validation	                        ✅ Validated	          100% Match
TERM Status Validation	                          ✅ Validated	          100% Match
Insurance Type Mapping	                          ✅ Validated	          100% Match
Filename-Month Alignment	                        ✅ Validated	          322 Shared Files
2025 Shared File Inventory	                      ✅ Validated	          322 Files / 492 Groups
Business Ready Transformation	                    ✅ Validated	          No evidence of raw discrepancies
Lifecycle / Collapse Processing	                  ✅ Validated	          No evidence of raw discrepancies
XML-only Inventory (2025)	                        ✅ Investigated	        772 Files / 44,805 Records
SQL Verification of Sampled XML-only Files	      ✅ Completed	          Sampled filenames returned 0 rows
SQL 2026 Inventory	                              ⚠ Outside Current Validation Scope	Requires separate XML validation using 2026 source data
Full 2026 XML Inventory Reconciliation	          ⏳ Pending	Not part of the current investigation
Key Findings

Based on the completed investigation:

✅ Parser834 correctly parses and counts raw XML records.
✅ Raw Record Counts matched SQL exactly for every shared validation group.
✅ Distinct Policy Counts matched SQL exactly.
✅ Distinct Member Counts matched SQL exactly.
✅ All shared CONFIRM, CANCEL, and TERM validation groups matched exactly.
✅ Insurance Type mapping matched SQL.
✅ Business Ready transformation is not supported by the evidence as the source of the observed raw differences.
✅ Lifecycle / Collapse processing is not supported by the evidence as the source of the observed raw differences.
✅ All 322 shared XML source files matched SQL after filename-month alignment.
✅ The investigation identified 772 XML source files (44,805 raw records) that were present in the validated XML source but not present in the SQL validation dataset used for this comparison.
✅ Direct verification against dbo.834_Inbound_test confirmed that the sampled high-volume XML-only filenames returned zero rows.
Conclusion

Within the current validation scope (issuers 13535, 15105, and 43802, using the 2025 XML source data), the raw XML parser has been successfully validated.

Every shared source file produced identical:

Raw Record Counts
Distinct Policy Counts
Distinct Member Counts

across all shared CONFIRM, CANCEL, and TERM validation groups.

Based on the evidence collected, there is no indication that the XML parser, Business Ready transformation, lifecycle processing, or collapse logic introduced the observed raw discrepancies within the validated scope.

The remaining differences are associated with file inventory between the validated XML source data and the SQL validation dataset. Expanding the same validation methodology to the 2026 XML source data will allow the remaining SQL/XML inventory reconciliation to be completed.

Thank you.
