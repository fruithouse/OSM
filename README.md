# SumUp to OSM Converter

A Perl utility to convert SumUp (https://sumup.com) transaction reports into a simplified CSV format suitable for import into Online Scout Manager (OSM) Accountancy Tools.

## Background

SumUp transaction reports contain a mixture of sales transactions, fees and payouts. OSM's CSV import facility cannot directly interpret all of the information provided by SumUp.

This script:

* Converts SumUp transaction exports into OSM-compatible CSV.
* Separates transaction fees into distinct accounting entries.
* Generates payout entries suitable for reconciliation.
* Combines relevant transaction information into a single reference field.
* Ignores failed and cancelled transactions.
* Reports unexpected tax and tip values.

The script was originally developed for use by UK Scout Groups using Online Scout Manager (OSM https://www.onlinescoutmanager.co.uk/) Accountancy Tools, but may be useful for other organisations using SumUp.

## Requirements

* Perl 5
* Text::CSV

Install Text::CSV if required:

```
cpan Text::CSV
```

or via your distribution package manager.

## Usage

Generate a transaction report from the SumUp web interface:

1. Log in to SumUp.
2. Open **Download Centre**.
3. Export **Transactions** as CSV.
4. Use the resulting CSV file as input.

Run:

```
perl sumup-to-osm.pl transactions-report.csv > osm-import.csv
```

Optional reporting:

```
perl sumup-to-osm.pl --report transactions-report.csv
```

Verbose diagnostics:

```
perl sumup-to-osm.pl --verbose transactions-report.csv
```

## Output Format

The generated CSV contains:

```
Date,Reference,Amount
```

which can be imported into an OSM bank account.

## Status

Current version: 3.0

The repository history preserves major development milestones from 2023 onwards.

## Author

Ken Bailey
