#!/usr/bin/perl -w
#

# SumUp reports https://me.sumup.com/en-gb/reports/overview outputs a
# CSV file of transactions but OSM cannot parse the fee data nor can
# it import all the descriptions which are spread across several
# columns. This script splits out fee data into separate rows, and
# merges descriptions into a single column.

# Based on:  https://perlmaven.com/how-to-read-a-csv-file-using-perl

# Ken Bailey, 1 Jan 2023.

use strict;
use warnings;
use Text::CSV;

my $file = $ARGV[0] or die "Need to get CSV file on the command line\n";
my $debug=1;

open(my $data, '<', $file) or die "Could not open '$file' $!\n";

# Build hash to validate header row names
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

# Establish CSV object
my $csv = Text::CSV->new({ sep_char => ',', binary => 1, auto_diag => 1 });

# import header row
$csv->header ($data, { munge_column_names => sub {
    # { munge_column_names => "lc" });
    s/\s+$//;
    s/^\s+//;
    # check header name against known names
    $known{lc $_} or die "Unknown column '$_' in $data";
			 }
	      }
    );

# print new header row for OSM
print "Date,Reference,Amount\n";

my $rowcount=1;
# Loop through rows
while (my $row = $csv->getline_hr ($data)) {
    $rowcount++;
    # reduce last 4 digits from "**** **** **** 1234" to just "1234"
    $row->{'last 4 digits'} =~ s/\*//g;
    $row->{'last 4 digits'} =~ s/\s*//g;

    # ensure currency values contain trailing decimals even if zero.
    $row->{total} = decimalise($row->{total}) if $row->{total};
    $row->{fee} = decimalise($row->{fee}) if $row->{fee};
    $row->{payout} = decimalise($row->{payout}) if $row->{payout};
    $row->{'tax amount'} = decimalise($row->{'tax amount'}) if $row->{'tax amount'};
    $row->{'tip amount'} = decimalise($row->{'tip amount'}) if $row->{'tip amount'};
    
    # NB Net sale,Tax amount,Tip amount are not yet used in this script. Net sale is factored-in but throw error if the other two appear.
    if ($row->{'tax amount'}) {
	if ( $row->{'tax amount'} != 0 ) {
	die "$0: non-zero value $row->{'tax amount'} in tax amount field not coded into script\n" 
	} else {
	    warn "zero value tax amount noted but ignored\n" if $debug;
	}
    }

        if ($row->{'tip amount'}) {
	if ( $row->{'tip amount'} != 0 ) {
	die "$0: non-zero value $row->{'tip amount'} in tip amount field not coded into script\n" 
	} else {
	    warn "zero value tip amount noted but ignored\n" if $debug;
	}
    }
    

    #    $row->{'net sale'} = decimalise($row->{'net sale'}) if $row->{'net sale'}; 


    # OSM strips many non-alphanumeric characters from the Reference text including ! " £ $ % ^ & * _ + =  { } [ ]  : ; < ' ~ # | \ < >  
    # Comma is default separator in CSV imports
    # Define a separator string so that we can readily identify text input from terminal
    # This can include spaces, alphanumerics and the characters @ ( ) . -
    # Modify description to more clearly identify text input from terminal if any;
    
    $row->{description} = ". $row->{description}." if $row->{description};

   
    if ( $row->{status} =~ m/failed|cancelled/i ) {
	# Although we could retain failed and cancelled transactions as zero value rows for ease of reference, OSM does not import zero-value transactions, so pointless trying to keep them.
	# "$row->{date}, $row->{status} transaction $row->{'card type'} $row->{'process as'} $row->{'last 4 digits'} " . lc($row->{'payment method'}) . " " . lc($row->{'entry mode'}) . ": $row->{total} $row->{description}, 0\n";
	warn "$0: skipping zero-value $row->{status} transaction\n";
    next;
} elsif ($row->{status} =~ m/success/i) {
    
    print "$row->{date}, $row->{'card type'} $row->{'process as'} $row->{'last 4 digits'} " . lc($row->{'payment method'}) . " " . lc($row->{'entry mode'}) . "$row->{description}, $row->{total}\n";
    
} elsif ($row->{status} =~ /paid/i) {
    print "$row->{date}, transaction fee against $row->{total} $row->{description}, \-$row->{fee}\n";
    print "$row->{'payout date'}, payout $row->{'payout id'} raised $row->{date} ($row->{'total'} minus $row->{fee}) $row->{description}, \-$row->{payout}\n";	
} else {
    die "$0: Unknown status $row->{status} at row $rowcount\n";
    }# end if
} # end while

warn "$0: all done $rowcount rows\n" if $debug;

exit;

sub decimalise {
    my $value = "@_";
    warn "debug: decimalise $value\n" if $debug;
    $value =~ s/\s//i; # strip any whitespace
    die "$0: non-numeric value $value passed to sub decimalise\n" unless ($value =~ m/^[\d\.]*$/);
    # check if value has decimal point or not
    unless ($value =~ m/^\d*\.\d*$/ ) {
	# if not, then append decimal point and two zeroes
	warn "debug:appending trailing decimal and two zeroes to $value\n" if $debug;
	$value .= ".00";
    }
    # check if decimal has two digits and iif only one, append trailing zero
    unless ($value =~ m/^\d*\.\d\d$/ ) {
	warn "debug:appending trailing zero to $value\n" if $debug;
	# if not, then append decimal point and two zeroes
	$value .= "0";
    }

    warn "debug: decimalised $value\n" if $debug;
    return("$value");
}
