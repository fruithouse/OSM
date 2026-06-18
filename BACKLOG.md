# SumUp to OSM Converter Backlog

This document records planned enhancements, ideas and known limitations for the `sumup-to-osm.pl` utility.

The primary purpose of the script is to convert SumUp Transaction Report CSV exports into a simplified CSV format suitable for import into Online Scout Manager (OSM) Accountancy Tools.

The long-term goal is to eliminate the need for this script entirely by encouraging OSM to provide native support for SumUp transaction imports.

## Current Release

Version 3.0 (July 2025)

## In Development (v4.0)

### Payout Consolidation

Add:

```
--consolidate-payouts
```

Group all payout rows sharing the same SumUp Payout ID into a single output transaction.

Current behaviour:

* One payout row is emitted for each successful sale.
* Large events can generate hundreds of payout rows.
* Each payout row must be manually classified as an Internal Transfer within OSM.

Proposed behaviour:

* Emit one consolidated payout transaction per payout batch.
* Description to include:

  * Number of sales in batch
  * First and last sale date/time
  * SumUp Payout ID

Example:

```
120 sales 20260613T1043-20260614T1550 payout 1718120
```

The original payout detail remains available in the source SumUp CSV and optional debug output.

### Output Ordering

Add:

```
--sort chronological
--sort grouped
```

chronological:
Preserve existing behaviour.

grouped:
Output rows in the following order:

```
1. Payouts
2. Fees
3. Receipts
```

This reduces repetitive transaction classification work within OSM.

### Reporting

Add:

```
--report
```

Provide a reconciliation summary including:

* Number of sales
* Number of fees
* Number of payout rows
* Number of payout batches
* Gross sales total
* Fee total
* Net payout total

May also provide a per-payout summary.

### Regression Testing

Create a repeatable test process using representative historical transaction exports.

Acceptance criteria:

* Receipt totals unchanged
* Fee totals unchanged
* Payout totals unchanged
* Overall total unchanged

The v4 output must reconcile exactly with v3 output totals.

## Planned (v4.1)

### Tip Handling

Current behaviour:

```
Script aborts if a non-zero tip is encountered.
```

Future behaviour:

* Treat tips as donations/income.
* Include appropriate accounting entries.
* Preserve reconciliation against payout totals.

### Documentation Improvements

* Update POD examples.
* Improve README examples.
* Document payout consolidation behaviour.

## Future Enhancements

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

### Enhanced Reconciliation Reporting

Investigate:

* Correlation between SumUp Payout IDs and bank statement references.
* Detection of missing or duplicated payout batches.
* Optional reconciliation summaries.

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

