#!/usr/bin/perl -w
#

# SumUp reports https://me.sumup.com/en-gb/reports/overview outputs a
# CSV file of transactions but OSM cannot parse the fee data nor can
# it import all the descriptions which are spread across several
# columns. This script splits out fee data into separate rows, and
# merges descriptions into a single column.

# Based on:  https://perlmaven.com/how-to-read-a-csv-file-using-perl

# Ken Bailey, 1 Jan 2023.

# v4 Added --consolidate-payouts and --sort grouped June 2026
# v3 Added tax and tip count and totals. July 2025
# v2 Added ignore tip amount Sept 2023
# v1 Initial script - June 2023

use strict;
use warnings;
use Text::CSV;
use Pod::Usage;
use Getopt::Long;
# The above are core modules, those below are not.
BEGIN {
    eval {
        require Text::CSV;
        Text::CSV->import();
        1;
    } or die "$0: Missing required module Text::CSV. Try: cpan Text::CSV\n";

# We will probably never use JSON output in this project, but, as an
# example of adding another non-core module:
#    eval {
#        require JSON;
#        JSON->import();
#        1;
#    } or die "$0: Missing required module JSON. Try: cpan JSON\n";

} # end BEGIN!

my $version='4.0.3';
my ($verbose,$debug,$report,$help,$consolidate_payouts,$sort_mode);

GetOptions(
    'verbose+'  => \$verbose, # 0, 1 or 2
    'debug+'  => \$debug, # 0, 1
    'report'  =>  \$report,
    'consolidate-payouts' => \$consolidate_payouts,
    'sort=s'              => \$sort_mode,
    'help|h|?'    => \$help,
    'version'   => sub { print "$0 $version\n"; exit(0) },
    ) or pod2usage(1);

if ($help) {
    if ($verbose) {
        pod2usage(-msg => "\nHelp:\n", -verbose => 2, -exitval => 1);
    } else {
        pod2usage(-msg => "\n$0: use --help --verbose for more detail.\n", -verbose => 1, -exitval => 1);
    }
}

# normalise
$verbose ||= 0;
$debug ||= 0;
$report ||= 0;
$consolidate_payouts ||= 0;
$sort_mode ||= 'chronological';

unless ($sort_mode =~ /^(chronological|grouped)$/) {
    die "$0: invalid --sort '$sort_mode' (expected chronological or grouped)\n";
}

my $file = $ARGV[0] or die "Usage $0 <sumup_transactions_filename.csv> (See $0 --help)\n";

if ($verbose) {
    if ($verbose > 2) { $debug++;};
} else {
    $verbose = 0;
}

if ($debug) {
    $verbose +=2;
    if ($debug || $report) {
	$|=1; # unbuffer output for debugging and report
    }
} else {
    $debug=0;
}

if ($verbose || $report) {
    warn "\n[INFO] $0 version $version " . localtime() . "\n";
    warn "[INFO] (running with verbose=$verbose debug=$debug report=$report)\n";
    warn "[INFO] Input file: $ARGV[0] \n";
}

# hash for various counters and totals
my %counter = (
    rowcount => 0,
    #    total_gtax => 0, # is this used or just a typo?
    tax_count => 0,
    total_tax => 0,
    tips_count => 0,
    total_tips => 0,
    fees_count => 0,
    total_fees => 0,
    total_sales => 0,
    payout_count => 0,
    consolidated_payout_count => 0,
    scheduled_payout_count => 0,
    total_payout => 0,
    zerovalue_count => 0,
    );

my %payout_batches;

# Internal output queue. Rows are collected first and printed later.
# This preserves the existing default output order while giving v4 a safe
# place to add payout consolidation and grouped output ordering.
my @output_rows;

# We may want to add a hash to store, then count, transactions per card type
# my $cardtype; # not yet used but known values so far are just VISA, MASTERCARD or AMEX.

open(my $data, '<', $file) or die "Could not open '$file' $!\n";

# Build hash to validate SumUp transaction log CSV header row names
# We could put these in an array and use a module instead
my %known = (
    "email" => "email",
    "date" => "date",
    "transaction id" => "transaction id",
    "transaction type" => "transaction type",
    "status" => "status",
    "card type" => "card type",
    "last 4 digits" => "last 4 digits",
    "process as" => "process as",
    "payment method" => "payment method",
    "entry mode" => "entry mode",
    "auth code" => "auth code",
    "description" => "description",
    "total" => "total",
    "net sale" => "net sale",
    "tax amount" => "tax amount",
    "tip amount" => "tip amount",
    "fee" => "fee",
    "payout" => "payout",
    "payout date" => "payout date",
    "payout id" => "payout id",
    "reference" => "reference",
    );

# Build hashes for validating known sub-values

# Known payout statuses observed in SumUp Transaction Reports.
# Unknown values are treated as fatal so that silent changes in
# SumUp report formats are detected promptly.

my %known_payout_status = (
    Paid      => 1,
    Scheduled => 1,
);

# Establish CSV object
my $csv = Text::CSV->new({ sep_char => ',', binary => 1, auto_diag => 1 });

# import header row
$csv->header ($data, { munge_column_names => sub {
    # { munge_column_names => "lc" });
    s/\s+$//;
    s/^\s+//;
    # check header name against known names
    $known{lc $_} or die "$0: '$file' is not a recognised current SumUp Transaction Report CSV: unknown column header '$_'\n";
                       }
              }
    ); # End new csv->header

my %seen_headers = map { lc($_) => 1 } $csv->column_names;

my @modern_required_headers = (
    'date',
    'transaction id',
    'transaction type',
    'status',
    'description',
    'total',
    'fee',
    'payout',
    'payout date',
    'payout id',
);

my @legacy_indicators = (
    'transaction code',
    'net sale',
    'fee amount',
);

my $legacy_hits = 0;
for my $header (@legacy_indicators) {
    $legacy_hits++ if $seen_headers{$header};
}

if ($legacy_hits >= 2 && !$seen_headers{'transaction type'}) {
    die "$0: '$file' appears to be a legacy SumUp export format.\n"
      . "Please re-export using the current SumUp Transaction Report CSV format.\n"
      . "The legacy format lacks transaction type and payout ID fields required by this version.\n";
}

for my $required (@modern_required_headers) {
    die "$0: '$file' is not a recognised current SumUp Transaction Report CSV: "
      . "missing required column '$required'.\n"
      unless $seen_headers{$required};
	      }


# The OSM CSV header is printed later by print_output_rows(), after all
# output rows have been queued.

$counter{'rowcount'}=1; # start at 1 because we have read the header
# Loop through rows
while (my $row = $csv->getline_hr ($data)) {
    $counter{'rowcount'}++;
    warn "[INFO] row count is $counter{'rowcount'}\n" if $verbose;
    # normalise any currency fields via sub &decimalise to ensure values contain two trailing decimals even if zero.
    $row->{total} = decimalise($row->{total}) if $row->{total};
    $row->{fee} = decimalise($row->{fee}) * -1 if $row->{fee};
    $row->{payout} = decimalise($row->{payout}) if $row->{payout};
    $row->{'tax amount'} = decimalise($row->{'tax amount'}) if $row->{'tax amount'};
    $row->{'tip amount'} = decimalise($row->{'tip amount'}) if $row->{'tip amount'};
    #
    # 'transaction type' is either "Sale" or "Payout"
    # This is a candidate for re-working to match %known_payout_status
    if ($row->{'transaction type'} eq "Sale") {
	print "\n[INFO] processing row $counter{'rowcount'}: $row->{'transaction type'} $row->{status}\n" if ($verbose > 1);
     	# status is either "Successful", "Failed" or "Cancelled"
	# This is another candidate for re-working to match %known_payout_status
	# Lets handle the Failed cases first
	if ($row->{status} =~ m/failed|cancelled/i ) {

	    # Although we could retain failed and cancelled transactions
	    # as zero value rows for ease of reference, OSM does not
	    # import zero-value transactions, so its pointless trying to
	    # keep them. In case of dispute, refer to SumUp's transaction
	    # record directly.


	    $counter{'zerovalue_count'}++;
	    warn "[INFO] skipping zero-value $row->{status} transaction\n" if $verbose;
	    next;

	} elsif  ($row->{status} eq "Successful") {

	    warn "[INFO] Processing row $counter{'rowcount'} for $row->{'status'} transaction\n" if $debug;
	    warn "[INFO] transaction type is $row->{'transaction type'} \n" if $debug;
	    warn "[INFO] status is $row->{status}\n" if $debug;

	    # reduce last 4 digits from "**** **** **** 1234" to just "1234"
	    $row->{'last 4 digits'} =~ s/\*//g;
	    $row->{'last 4 digits'} =~ s/\s*//g;

	    if ( $row->{total} ) {
		$counter{'sales_count'}++;
		$counter{'total_sales'} += $row->{total};
		warn "[INFO] $counter{'sales_count'} sales with running total_sales of " . decimalise($counter{'total_sales'}) . "\n" if $verbose;
	    }

	    if ( $row->{fee} ) {
		$counter{'fees_count'}++;
		$counter{'total_fees'} -= $row->{fee};
		warn "[INFO] $counter{'fees_count'} fees with $row->{fee} added to running total_fees of " . decimalise($counter{'total_fees'}) . "\n" if $verbose;
	    }

	    # NB Net sale, Tax amount and Tip amount are not expected to
	    # be used. Net sale is factored-in but we keep track of these
	    # and throw an error after all is processed.  Tax amount is
	    # advisory, not deductible at source, so can be ignored. If it
	    # appears it probably means the card reader environment has
	    # default values of 20% VAT.

	    # Tips, should there ever be any, are income to be treated as
	    # donations.

	    if ($row->{'tax amount'}) {
		if ( $row->{'tax amount'} != 0 ) {
		    $counter{'tax_count'}++; # only count positive tax amount rows
		    $counter{'total_tax'} += $row->{'tax amount'};
		    warn "[INFO] non zero value tax amount " . decimalise($row->{'tax amount'}) . " noted, total tax now ", decimalise($counter{'total_tax'}) . "\n" if $verbose;
		    # These are probably item config errors - e.g. inventory
		    # set to have VAT when not relevant
		} else {
		    warn "[INFO] zero value tax amount noted but ignored\n" if $verbose;
		} # end if tax amount not zero
	    } # end tax amount handler

	    if ($row->{'tip amount'}) {
		if ( $row->{'tip amount'} != 0 ) {
		    $counter{'tips_count'}++;
		    $counter{'total_tips'} += $row->{'tip amount'};
		    warn "[INFO] non zero value tip amount " . decimalise($row->{'tip amount'}) . " noted, total tips now " . decimalise($counter{'total_tips'}) . "\n" if $verbose;
		    # We treat tips as donations and typically just add them in as part of fundraising takings .
		    # So, we should print a row for OSM to account for the tip, but currently uncertain how that translates to a payout.
		    # Let's die until we can find out.....
		    die "$0: Tip received but script cannot handle tips yet!\n";
		    #
		} else {
		    warn "[INFO] zero value tip amount noted but ignored\n" if $verbose;
		} # end if tip amount not zero
	    } # end tip amount handler

	    # OSM strips many non-alphanumeric characters from the
	    # Reference text including ! " £ $ % ^ & * _ + = { } [ ] :
	    # ; < ' ~ # | \ < >

	    # Comma is default separator in OSM CSV imports

	    # Define a separator string so that we can readily identify text input from terminal
	    # This can include spaces, alphanumerics and the characters @ ( ) . -
	    # Modify description to more clearly identify text input from terminal if any;

	    # The second field is the "Reference" - it is a free text
	    # field in OSM, so we pack it with as much useful data as
	    # we can squeeze in, however there seems to be a character
	    # limit of 51 characters in our SumUp OSM bank account
	    # transaction log. Nevertheless, we squeeze what we can in
	    # here to assist any subsequent forensic examination.
	    # We may want to reconsider the ordering though.

	    my $reference = "$row->{status} transaction $row->{'card type'} $row->{'process as'} $row->{'last 4 digits'} "
	                  . lc($row->{'payment method'}) . " " . lc($row->{'entry mode'})
	                  . ": $row->{total} $row->{description}";

	    queue_output_row('receipt', $row->{date}, $reference, $row->{total});
	} else {
	    die "$0: status $row->{status} at row $counter{'rowcount'} is neither Failed, Cancelled nor Successful!\n";
	}

	} elsif ($row->{'transaction type'} eq "Payout" ) {
	    $counter{'payout_count'}++;
	    warn "[INFO] row $counter{'rowcount'} is Payout row number $counter{'payout_count'}\n" if $verbose;

	    unless ($known_payout_status{$row->{status}}) {
		die "$0: Unknown payout status '$row->{status}' "
		    . "in row $counter{'rowcount'}\n";
	    }

	    if ($row->{status} eq "Scheduled") {
		$counter{'scheduled_payout_count'}++;
		warn "[DEBUG] skipping scheduled payout row $counter{'rowcount'} "
		    . "amount=$row->{payout} "
		    . "date=$row->{date}\n"
		    if $debug;
		next;
	    }

	    if ($row->{status} eq "Paid") {
		if ( $row->{payout} ) {
		    $row->{payout} = $row->{payout} * -1 if ($row->{payout} > 0 );
		    $counter{'total_payout'} += $row->{payout};
		    warn "[INFO] Now $counter{'payout_count'} total payouts. Added $row->{payout} to give running total_payout of " . decimalise($counter{'total_payout'}) . "\n" if $verbose;
		} else {
		    die "$0: [FATAL] \$row->{payout} not set in payout row $counter{'rowcount'}\n";
		}
		#
		my $pid = $row->{'payout id'};

		$payout_batches{$pid}{count}++;

		$payout_batches{$pid}{gross_total} += $row->{total};
		$payout_batches{$pid}{fee_total}   += $row->{fee};
		$payout_batches{$pid}{net_total}   += $row->{payout};

		# Capture the earliest and latest transaction dates associated with
		# this SumUp payout batch. Input rows are not guaranteed to be in
		# chronological order, so compare ISO-like date strings rather than
		# trusting first-seen/last-seen order.
		$payout_batches{$pid}{first_date} = $row->{date}
		if !defined $payout_batches{$pid}{first_date}
		|| $row->{date} lt $payout_batches{$pid}{first_date};

		$payout_batches{$pid}{last_date} = $row->{date}
		if !defined $payout_batches{$pid}{last_date}
		|| $row->{date} gt $payout_batches{$pid}{last_date};

		$payout_batches{$pid}{payout_date} = $row->{'payout date'};

		# Queue the SumUp fee as a separate output row for OSM.
		queue_output_row('fee', $row->{date},
				 " transaction fee against $row->{total} $row->{description}",
				 $row->{fee}
		    );

		# Queue the payout as an internal transfer row for
		# OSM.  Non-debug output is suppressed and replaced by
		# a consolidated payout batch row when
		# --consolidate-payouts is enabled.
		# We will probably make this the default as it saves
		# having to process multiple internal transfer
		# transactions that are already batched in practice.

		if ($consolidate_payouts) {
		    warn "[DEBUG] suppressing payout row for batch $pid amount $row->{payout}\n" if $debug;
		} else {
		    queue_output_row('payout', $row->{'payout date'},
				     " payout $row->{'payout id'} raised $row->{date} ($row->{'total'} minus $row->{fee}) $row->{description}",
				     $row->{payout}
			);
		}

		# This is marked as an internal transfer from the SumUp "Bank Account" to the Group's Current Account in OSM.
		# YMMV if you have a SumUp Business account.
	    } else {
		die "$0: Unknown status $row->{status} for transaction type $row->{'transaction type'} in row $counter{'rowcount'}\nOnly expect type \"Paid\" or \"Scheduled\"\n";
		# ie "$0: Unknown SumUp transaction type $row->{'transaction type'} in row $counter{'$rowcount'}\n";
	    } # end if Payout Paid
    } else {
	die "$0: [FATAL] Row $counter{'rowcount'} transaction type $row->{'transaction type'} is neither Sale nor Payout!\n";
    } # end if $row->{transaction type'} ....

} # end while (my $row = $csv->getline_hr...

if ($consolidate_payouts) {
    for my $pid (sort keys %payout_batches) {
        my $b = $payout_batches{$pid};

        my $reference = "$b->{count} sales from $b->{first_date} to $b->{last_date} payout $pid";

        queue_output_row('payout', $b->{payout_date}, $reference, decimalise($b->{net_total}));
        $counter{'consolidated_payout_count'}++;

        warn "[DEBUG] consolidated payout batch $pid as $b->{payout_date},$reference,"
           . decimalise($b->{net_total}) . "\n" if $debug;
    }
} # end if ($consolidate_payouts)

# Print CSV output after all input rows have been processed.
print_output_rows();

warn "[INFO] all done $counter{'rowcount'} rows\n" if $verbose;

# ============================================================================
# Final summary (if verbose or report requested )
# ============================================================================

if ($verbose||$report) {
    warn "[WARNING] $counter{'tips_count'} transactions: total tips of $counter{'total_tips'} included\n" if ( $counter{'total_tips'} > 0 ) ;
    warn "[WARNING] $counter{'tax_count'} unexpected transactions with total tax of $counter{'total_tax'} advised\n" if ( $counter{'total_tax'} > 0 );

    if ($report) {
	warn "\n[INFO] Payout batches:\n";

	for my $pid (sort keys %payout_batches) {
	    my $b = $payout_batches{$pid};

	    warn "  $b->{count} sales from "
		. "$b->{first_date} to $b->{last_date} "
		. "payout $pid paid $b->{payout_date} "
		. "net " . decimalise($b->{net_total})
		. "\n";
	}
    }

    print STDERR "\n[INFO] Summary:\n";
    for my $key (sort keys %counter) {

	my $reportval = $counter{$key};
	if ( $key =~ /^\s*total/ ) {
	    $reportval = decimalise($reportval);
	}
	warn "  $key\t\t$reportval\n";
    }

    warn "[WARNING] $counter{'scheduled_payout_count'} scheduled payout rows skipped. "
	. "Re-export after the relevant SumUp payout date. "
	. "SumUp payout frequency may be daily, weekly, or monthly.\n"
	if $counter{'scheduled_payout_count'} > 0;

}


exit;

#======================================================================
# queue an output row for later CSV printing
#======================================================================
sub queue_output_row {
    my ($type, $date, $reference, $amount) = @_;

    push @output_rows, {
	type      => $type,
	date      => $date,
	reference => $reference,
	amount    => $amount,
    };
}

#======================================================================
# print queued output rows
#======================================================================
sub print_output_rows {
    print "Date,Reference,Amount\n";

    my @rows_to_print;

    if ($sort_mode eq 'grouped') {
        for my $wanted_type (qw(payout fee receipt)) {
            push @rows_to_print, grep { $_->{type} eq $wanted_type } @output_rows;
        }
    } else {
        @rows_to_print = @output_rows;
    }

    for my $out (@rows_to_print) {
        print "$out->{date},$out->{reference},$out->{amount}\n";
    }
}

#======================================================================
# normalise currency values to two decimal places
#======================================================================
sub decimalise {
    my $value = "@_";
    my $initial_value=$value;
    if ($value =~ /^\s*$/) {
	warn "[INFO] blank value passed to sub decimalise() - returning 0.00\n" if ($verbose > 1);
	return("0.00");
	};
    warn "[INFO] decimalise $value\n" if ($verbose > 1) ;
    $value =~ s/\s//i; # strip any whitespace
    die "$0: non-numeric value $value passed to sub decimalise\n" unless ($value =~ m/^-?[\d\.]*$/);
    # check if value has decimal point or not
    unless ($value =~ m/^-?\d*\.\d*$/ ) {
	# if not, then append decimal point and two zeros
	warn "[INFO] appending trailing decimal and two zeros to $value\n" if ($verbose > 1);
	$value .= ".00";
    }
    # check if decimal has two digits and if only one, append trailing zero
    unless ($value =~ m/^-?\d*\.\d\d$/ ) {
	warn "[INFO] appending trailing zero to $value\n" if ($verbose > 1);
	# if not, then append decimal point and two zeros
	$value .= "0";
    }
    if ($value =~ /\d+\.\d\d\d+/ ) {
	# we have accumulated more than two decimal places so round off
	warn "[INFO] value $value has more than two decimals.\n" if ($verbose > 1);
	$value = int($value * 10**2 + 0.5) / 10**2 ; # +0.5 is magical sauce to do rounding instead of truncating
	warn "[INFO] Rounded to $value\n" if ($verbose > 1);
    }

    warn "[INFO] decimalised $initial_value to $value\n" if (($initial_value ne $value) && ($verbose > 1));
    return("$value");
}

exit 0;

__END__

=head1 NAME

sumup-to-osm.pl - Convert SumUp CSV transaction report for import to
Online Scout Manager (OSM) Accountancy Tools

=head1 SYNOPSIS

  perl sumup-to-osm sumup-transaction-report-filename.csv [--report] [--verbose] [--help] [--version] [--consolidate-payouts] [--sort chronological|grouped]

  A script to convert SumUp transaction reports for import into an OSM
  Accountancy Tools Bank Account.

=head1 DESCRIPTION

This script parses transaction data from a SumUp CSV transaction log
file and outputs a simplified CSV file containing basic essential data
(date,description,amount) in a format that can be parsed by OSM
Accountancy Tools.

To do this, first check the date of the last transaction uploaded to
OSM so you know the required start date for the report.

Log into the SumUp managerial interface on a desktop browser.

From the three horizontal bars Navigation Menu in the top left corner
of the page, select and expand the Home menu, select overview and
click "Download center". This takes you to
https://me.sumup.com/en-gb/reports/download-center.

Adjust the date range as appropriate, typically from the day after the
last date in the OSM SumUp transactions to the present, then select
'Transactions'.

Choose CSV for the output format, do not add any filters, and don't
use the "old format" (it will be recognised but rejected).

Click "Export file". This will save a file with the name in the format
<start date>-<end date>-<client ID>-transactions-report.csv with dates
in YYYYMMDD format. This is the file that this script will process.

Save the file to your finance data store - SumUp does not produce
statements as such so this needs to be retained as evidence for your
end of year accounts, though you may prefer to use a separate PDF
report for that. SumUp also email a report PDF for every payout, so
retain those for your end of year accounts too.

The daily Payout Report is useful for checking consolidated payout
totals against the bank statement, but the Transaction Report CSV
remains the preferred input because it contains the detail needed to
produce separate OSM receipt and fee rows.

SumUp payouts comprise the net amount of aggregated sale values minus
fees. SumUp batch these depending on customer type and chosen
preference, typically daily (next business day), Weekly on Mondays or
Monthly on the third business day of the month.

SumUp therefore track the payout status for every transaction as
either 'Scheduled' or 'Paid'.

Whilst 'Scheduled', the payout date and payout id fields are blank but
once 'Paid', payout date is set and the payout id is assigned a unique
Payout ID (PID). Prior to 2026, the PID was cited in payout bank
transfer description, but now the bank transfer is assigned a separate
unique reference, so any reconciliation now has to depend on just date
and amount.

=head1 OPTIONS

=over 4

=item <filename>

The path to the SumUp transaction report CSV input file (required).
This can be provided as an argument or piped via STDIN.

=item B<--consolidate-payouts>

Consolidates multiple payout rows sharing the same SumUp Payout ID
into a single payout row. This significantly reduces the number of
internal transfer transactions that must be classified manually in OSM.

=item B<--sort> B<chronological|grouped>

C<chronological> preserves the input order in output.
C<grouped> groups output by payouts, fees, then receipts.

=item B<--report>

Prints a diagnostic summary report at the end of processing. The report is printed to STDERR.

=item B<--verbose> I<filename>

Prints descriptive messages whilst processing and the summary report when complete. All output to STDERR.

=item B<--version>

Show program version and exit.

=item B<--help>

Show usage info. Add --verbose for full documentation.

=back

=head1 AUTHOR

Ken Bailey

=cut
