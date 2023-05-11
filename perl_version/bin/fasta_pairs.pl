#! /usr/bin/perl -w

# fasta_pairs.pl
# take one header from each of two fasta files, or specify a tab separated file
# make sure headers are unique UP TO THE FIRST SPACE, because chomping that off
# since working with tair10 and thats how a lot of tools do it
# Alan E. Yocca
# 11-13-18
# updated 08-29-18 to provide inverse function

use strict;
use Getopt::Long;

my $usage = "\n$0\n" .
				"\t--one <header from first fasta to pull out>\n" .
				"\t--two <fasta file>\n" .
				"\t--first_fasta <fasta file corresponding to --one >\n" .
				"\t--second_fasta <fasta file corresponding to --two or second column of --list_pairs>\n" .
				"\t--list_pairs <tab separated list of pairs to extract>\n" .
					"\t\t<will still output single file, but all pairs will be in it>\n" .
				"\t-o <output> \n\n";

my $one;
my $two;
my $first_fasta;
my $second_fasta;
my $list_pairs;
my $out;

GetOptions (	'one=s' => \$one, 
		'two=s' => \$two,
		'first_fasta=s' => \$first_fasta,
		'second_fasta=s' => \$second_fasta,
		'list_pairs=s' => \$list_pairs,	
		'o=s' => \$out
) or die "$usage\n";


if ( defined $list_pairs || defined $one && defined $two ) {
	#good!
}
else {
  print "$usage";
  exit;
}

if (!defined $out || ! defined $first_fasta || ! defined $second_fasta) {
  print "$usage";
  exit;
}

open (my $ff_fh, '<', $first_fasta) || die "Cannot open the first fasta: $first_fasta\n\n";
open (my $sf_fh, '<', $second_fasta) || die "Cannot open the second fasta: $second_fasta\n\n";
open (my $out_fh, '>', $out) || die "Cannot open output: $out\n\n";

my %genes_one;
my %genes_two;

if (defined $list_pairs) {
	open (my $lp_fh, '<', $list_pairs) || die "Cannot open the list file: $list_pairs\n\n";
	while (my $line = <$lp_fh>) {
		chomp $line;
		my @pairs = split("\t", $line);
		$genes_one{$pairs[0]} = 1;
		$genes_two{$pairs[1]} = 1;
	}
	close $lp_fh;
}
else {
	$genes_one{$one} = 1;
	$genes_two{$two} = 1;
}
#loop control to handle wrapped fastas
my $loop = 0;
my $count = 0;

while (my $line = <$ff_fh>) {
	chomp $line;
	my @trans = split(">",$line);
	if ($trans[1]) {
		my @line = split(" ",$trans[1]);
		if ($genes_one{$line[0]}) {
			if ($count == 0) {
				print $out_fh "$line\n";
				$loop = 1;
				$count = $count + 1;
			}
			else {
				print $out_fh "\n$line\n";
				$loop = 1;
				$count = $count + 1;
			}
		}
		else {
			$loop = 0;
		}
	}
	else {
		if ($loop) {
			print $out_fh "$line";
		}
	}
}

while (my $line = <$sf_fh>) {
	chomp $line;
	my @trans = split(">",$line);
	if ($trans[1]) {
		my @line = split(" ",$trans[1]);
		if ($genes_two{$line[0]}) {
			if ($count == 0) {
				print $out_fh "$line\n";
				$loop = 1;
				$count = $count + 1;
			}
			else {
				print $out_fh "\n$line\n";
				$loop = 1;
				$count = $count + 1;
			}
		}
		else {
			$loop = 0;
		}
	}
	else {
		if ($loop) {
			print $out_fh "$line";
		}
	}
}

print "genes printed to output: $count\n";

close $ff_fh;
close $sf_fh;
close $out_fh;

exit;