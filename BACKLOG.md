# SumUp to OSM Converter Backlog

This document records planned enhancements, ideas and known limitations for the `sumup-to-osm.pl` utility.

The primary purpose of the script is to convert SumUp Transaction Report CSV exports into a simplified CSV format suitable for import into Online Scout Manager (OSM) Accountancy Tools.

The long-term goal is to eliminate the need for this script entirely by encouraging OSM to provide native support for SumUp transaction imports.

## Current Release

Version 4.0 (June 2026)

## Planned (v4.1)

### Regression Testing

Create a repeatable formalised documented test process using
representative historical transaction exports.

Acceptance criteria:

* Receipt totals unchanged
* Fee totals unchanged
* Payout totals unchanged
* Overall total unchanged

The v4 output must reconcile exactly with v3 output totals.

### Validation consistency

Background:

Several fields have a limited number of valid values:
```
Sale    -> Successful
Sale    -> Failed
Sale    -> Cancelled
Payout  -> Scheduled
Payout  -> Paid
```

Current state:

 We use a mixture of styles to check the validity of certain fields
 against known values, e.g. Payout Status may be 'Paid' or 'Scheduled'.
 In the case of the latter, we use a hash. In other cases we just
 process the options inline.

Future state:
 All sub-type validity tests will use hashes for clarity and consistency.

## Future Enhancements

### Tip Handling

Current behaviour:

```
Script aborts deliberately if a non-zero tip is encountered.
```

Future behaviour:

* Treat tips as donations/income.
* Include appropriate accounting entries.
* Preserve reconciliation against payout totals.

### Documentation Improvements

* Update POD examples.
* Improve README examples.
* Document payout consolidation behaviour.

### Read From STDIN

Permit:

```
cat transactions.csv | sumup-to-osm.pl
```

### Multiple Input Files

Permit:

```
sumup-to-osm.pl file1.csv file2.csv ...
```
* This will need to avoid potential duplication of transactions

### Enhanced Reconciliation Reporting

Investigate:

* Correlation between SumUp Payout IDs and bank statement references.
* Detection of missing or duplicated payout batches.
* Optional reconciliation summaries.

## Hardening

Current behaviour:
```
Unpredictable failure in case of csv format changes or file corruption
```

Future behaviour:
```
* add --strict to include checks, for example
  gross - fee = payout
  payout id present on payout rows
  payout date present
  transaction type is Sale or Payout
  Sale status is Successful/Failed/Cancelled
  Payout status is Paid
  dates match expected format
  currency values are numeric

  Add %known_sale_status and %known_fee_status etc in keeping with %known_payout_status

```

## OSM Feature Request

Long-term objective:

Work with OSM developers to provide native support for importing SumUp Transaction Reports.

Evidence gathered by this project may be used to support an enhancement request, particularly:

* Payout consolidation requirements.
* Internal transfer classification workload.
* Real-world reconciliation requirements.
* Example transaction exports and accounting workflows.

## Rejected / Deferred

### JSON Output

Not currently required.

The sole consumer of script output is OSM, which imports CSV files.

SumUp already provides extensive reporting facilities via its web interface.

