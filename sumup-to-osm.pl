#!/usr/bin/perl

# SumUp reports https://me.sumup.com/en-gb/reports/overview outputs a
# CSV file of transactions but each row contains both gross income,
# SumUp's fee as an expense and the residual payout that is transfreed
# to the client. OSM cannot parse the fee data nor can it import all
# the descriptions which are spread across several columns. This
# script splits the data into separate rows for gross income, fee and
# net payout and merges descriptions into a single column. Output is
# sent to STDOUT.

# SumUp outputs transactions in a current and, optionally, a legacy
# format which has less detail and fewer columns.  Of these, "last 4
# digits" and "payout id" are significant. The script still should
# work against the legacy format but it generates warnings as a less
# detailed transcaction description is derived.

# Based on:  https://perlmaven.com/how-to-read-a-csv-file-using-perl
# Ken Bailey, 1 Jan 2023.
# Polished with: ChatGPT 3.5 1 Jun 2024.

use strict;
use warnings;
use Text::CSV;
# set value to 1 or more to enable debug output on STDERR
use constant DEBUG => 0;

sub decimalise {
        warn "$0: in sub decimalise\n" if DEBUG;
	
	my ($value) = @_;
	warn "$0: in sub decimalise $value\n" if DEBUG;
	die "$0: sub decimalise called with no value @_\n" unless defined($value);
	warn "$0: in sub decimalise $value\n" if DEBUG;
	$value =~ s/\s//g;
	#
	die "$0: Non-numeric value $value passed to sub decimalise\n" unless ($value =~ m/^[\d\.]*$/);
	# ensure currency values contain trailing decimals even if zero.
	unless ($value =~ m/^[\d\.]*$/ ) {
	    warn "$0: value $value does not contain numbers or dots\n";
	    $value = "0.00";
	}
	# pad to two decimal digits
	$value .= "0" if $value =~ m/\.\d$/;
	# pad to two decimal zeros if not decimal
	$value .= "0" if $value =~ m/\.\d$/;
	# pad to two zeroes if not zero
	$value .= ".00" unless $value =~ m/\.\d{2}$/;
	# prepend leading zero if starts with dot
	$value = "0" . $value if ($value =~ m/^\./ );
	warn "$0: sub decimalise @_ returning $value\n" if DEBUG;
	die "$0: sub decimalise return value $value does not match required pattern\n" unless ($value =~ m/^\d+\.\d\d$/);
	return $value;
}

sub process_row {
    my ($row, $rowcount) = @_;
    warn "$0: in sub process_row $row, $rowcount\n" if DEBUG;

    foreach my $key (keys %$row) {
        warn "debug: row key is '$key', value is '$row->{$key}'\n" if DEBUG;
    }
    
    if (defined($row->{'last 4 digits'})) {
	# reduce last 4 digits from "**** **** **** 1234" to just "1234"
	$row->{'last 4 digits'} =~ s/[*\s]//g;
    } else {
	# last 4 digits is not provided in SumUp transaction report legacy format 
        warn "Row $rowcount: 'last 4 digits' not defined, legacy format input suspected\n";
        $row->{'last 4 digits'} = "(no card digits provided)";
    }
    
    unless (defined($row->{'payout id'})) {
        warn "Row $rowcount: 'payout id' not defined, legacy format input suspected\n";
        $row->{'payout id'} = "(no payout id provided)";
    }

    my @currency_values = ('total', 'fee', 'payout', 'tax amount', 'tip amount');
    for my $key (@currency_values) {
        warn "debug: key is $key, \$row->{$key} is $row->{$key}\n" if DEBUG;
	$row->{$key} = decimalise($row->{$key}) if defined $row->{$key};
	
	# NB Net sale,Tax amount,Tip amount are not yet used in this script. Net sale is factored-in but throw error if the other two appear.
	if  ($key =~ m/^tax amount|tip amount$/) {
	    warn "debug: checking $key, \$row->{$key} is zero\n" if DEBUG;
	    if  (defined $row->{$key}) {
		warn "$0: row $rowcount $key contains non-zero value $row->{$key}\n" unless ( $row->{$key} =~ m/^[0\.]*$/);
		sleep DEBUG if DEBUG;
	    }
	}
    }
	return $row;
}

sub main {
    my $file = shift @ARGV or die "$0: Need to get CSV file on the command line\n";
    open(my $data, '<', $file) or die "$0: Could not open '$file for read': $!\n";

    # Build array of known headers in lower case
    # NB It would help maintenance to put these in alphabetical order 
    my @known_headers = ('email', 'date', 'transaction id', 'transaction type', 'status', 'card type', 'last 4 digits',
                         'process as', 'payment method', 'entry mode', 'auth code', 'description', 'total', 'net sale',
                         'tax amount', 'tip amount', 'fee', 'payout', 'payout date', 'payout id', 'reference');
    
    # Convert the known header array to a hash to validate header row names
    my %known_headers = map { $_ => 1 } @known_headers;

    if (DEBUG) {
        warn "debug: \@known_headers is ", scalar @known_headers, "\n";
        foreach my $headerkey (sort keys %known_headers) {
            warn "debug: header key $headerkey\n";
        }
    }
    # Establish CSV object; note use of quote_space
    my $csv = Text::CSV->new({ sep_char => ',', binary => 1, auto_diag => 0, quote_space => 'false' });

    # import header row
    # Note: We started out using $csv->header ($data, { munge_column_names => sub { ... })
    # but switched to this to manage Text::CSV INI failure   
    my $headers = $csv->getline($data);
    foreach my $header (@$headers) {
        $header =~ s/^\s*|\s*$//g;  # Trim leading and trailing spaces
        $header =~ s/\s+/ /g;       # Replace multiple spaces with a single space
    }

    if (DEBUG) {
        warn "debug: read headers: ", join(", ", @$headers), "\n";
    }

    for my $header (@$headers) {
        if (!defined $header || $header eq '') {
            die "$0: Header  contains an empty field\n";
        }
        if (!$known_headers{lc $header}) {
            die "$0: Unknown column '$header' in $file\n";
        }
    }

    $csv->column_names(map { lc $_ } @$headers);

    # print new header row for OSM
    print "Date,Reference,Amount\n";
    my $rowcount = 1;
    # Loop through rows
    while (my $row = $csv->getline_hr($data)) {
        $rowcount++;
        $row = process_row($row, $rowcount);

        if (defined $row->{status}) {
	    # zero value transactions such as failed or cancelled ones are ignored by OSM
            if ($row->{status} =~ /failed|cancelled/i) {
                warn "Row $rowcount: Skipping zero-value $row->{status} transaction\n" if DEBUG;
                next;
            } elsif ($row->{status} =~ /successful/i) {
                print "$row->{date},\"$row->{'card type'} $row->{'process as'} $row->{'last 4 digits'} " .
                      lc($row->{'payment method'}) . " " . lc($row->{'entry mode'}) .
		    " $row->{'description'}\",$row->{'total'}\n";

		warn "$row->{date},\"$row->{'card type'} $row->{'process as'} $row->{'last 4 digits'} " .
		    lc($row->{'payment method'}) . " " . lc($row->{'entry mode'}) .
		    " $row->{'description'}\",$row->{'total'}\n" if DEBUG;
            } elsif ($row->{status} =~ /paid/i) {
		die "$0: payout $row->{'payout'} plus fee $row->{'fee'} does not equal total $row->{'total'} in row $rowcount!\n" unless ( $row->{'payout'} + $row->{'fee'} == $row->{'total'} ); 
                print "$row->{date},\"transaction fee against £$row->{'total'} $row->{'description'}\",-$row->{'fee'}\n";
                warn "$row->{date},\"transaction fee against £$row->{'total'} $row->{'description'}\",-$row->{'fee'}\n" if DEBUG;
                print "$row->{'payout date'},\"payout $row->{'payout id'} raised $row->{date} (£$row->{'total'} minus £$row->{'fee'}) $row->{'description'}\",-$row->{payout}\n";
		warn "$row->{'payout date'},\"payout $row->{'payout id'} raised $row->{date} (£$row->{'total'} minus £$row->{'fee'}) $row->{'description'}\",-$row->{payout}\n" if DEBUG;
            } else {
                die "$0: Unknown status $row->{status} at row $rowcount\n";
            }
        } else {
            warn "Row $rowcount: 'status' not defined\n" if DEBUG;
        }
    }

    warn "Processing completed: $rowcount rows\n" if DEBUG;
}

main();

