#! /usr/bin/perl -w

# split_pairwise_col.pl
# dummy script for ka_ks_pipe, maybe will make useful later, not now
# 11-27-18

use strict;
use warnings;
use Getopt::Long;

my $usage = "\n$0\n" .
			"\t--in <bed file>\n" .
			"\t--out <output renamed gff> \n\n";

my $input;
my $output;

GetOptions ( "in=s" => \$input,
  "out=s" => \$output
) or die "$usage\n";

if ( (!(defined $input)) || (!(defined $output)) ) {
  print "$usage";
  exit;
}

open (my $in_fh, '<', $input) || die "Cannot open the input file $input\n\n";
open (my $out_fh, '>', $output) || die "Cannot open output fasta: $output\n\n";

while (my $line = <$in_fh>) {
	chomp $line;
	my @line = split("\t",$line);
	my @first = split(",",$line[0]);
	my @second = split(",",$line[1]);
	if (defined $first[1]) {
		for (my $j=0; $j < @first; $j++) {
			if (defined $second[1]) {
				#second is split too, pairwise
				for (my $i=0; $i < @second; $i++) {
					print $out_fh "$first[$j]\t$second[$i]\n";
				}
			}
			else {
				#second not split
				print $out_fh "$first[$j]\t$line[1]\n";
			}
		}
	}
	else {
		if (defined $second[1]) {
			#second split but not first
			for (my $i=0; $i < @second; $i++) {
				print $out_fh "$line[0]\t$second[$i]\n";
			}
		}
		else {
			#neither split
			print $out_fh "$line\n";
		}
	}  
}

close $in_fh;
close $out_fh;

exit;

