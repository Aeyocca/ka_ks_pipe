#! /usr/bin/perl -w

# list_orthologs.pl
# take in blast file and and syntenic anchors file (optional, highly recommended)
# spit out translation table of the highest confidence reference ortholog for each query (if one exists)
# made as part of ka_ks_pipeline
# code taken from blast_filter.pl comp_trans.pl anchors_to_trans.pl
# Alan E. Yocca
# 11-12-18

use strict;
use warnings;
use Getopt::Long;


my $usage = "\n$0\n" .
			"\t--blast <blast input m8 format>\n" .
			"\t--bit_score <bitscore value above which to keep>\n" .
				"\t\t<default: 1>\n" .
			"\t--e_value <e-value to filter out below>\n" .
				"\t\t<default 1e-4>\n" .
			"\t--align_length <alignment length to filter out below>\n" .
			"\t--filter_order <comma separated list ordered of things to filter out, match command line flags exactly>\n" .
				"\t\t<optional, if you want, if not defined, will just take the order of things on command line>\n" .
				"\t\t<default: bit_score, then alignment length>\n" .
			"\t--anchor <anchor file output from python MCScanX>\n" .
			"\t--force <if specified, force overwrite outputs instead of asking>\n" .
			"\t--no_tag <no tag, can't really remember why I add the tag anyway...>\n" .
			"\t--self_comp <this is a self comparison, so discard hits to self>\n" .
				"\t\t<SPECIFY \"true\" if self comp>\n" .
				"\t\t<easier to handle with pipeline>\n" .
			"\t-o <output translation table> \n\n";


my $self_comp;
my $no_tag='';
my $force='';
my $blast;
my $output;
my $filter_order;
my $bit_score=1;
my $align_length;
my $e_value=0.0001;
my $anchor;

#only keeping 1 hit, best hit
my $number_hits=1;


GetOptions ( "blast=s" => \$blast,
  "self_comp=s" => \$self_comp,
  "no_tag" => \$no_tag,
  "force" => \$force,
  "o=s" => \$output,
  "filter_order=s" => \$filter_order,
  "bit_score=i" => \$bit_score,
  "align_length=i" => \$align_length,
  "e_value=i" => \$e_value,
  "anchor=s" => \$anchor
) or die "$usage\n";

if ( (!(defined $blast)) || (!(defined $output)) || (!(defined $anchor))) {
  print "$usage";
  exit;
}

if (-e $output && (!($force))) {
print "File: $output or exist, is it okay to overwrite it?\n"; 
my $answer = <STDIN>;
	if ($answer =~ /^y(?:es)?$/i) {
		print "Excellent!\n";
	}
	else {
		die "fine, I will not overwrite your files, but I will also not run this script\n";
	}
}

if (!(defined $filter_order)) {
	#initialize with comma so can add to it in the loop
	my $temp_filter_order = ",";
	for (my $i=0; $i<@ARGV; $i++) {
		next if ($ARGV[$i] ne "bit_score" || $ARGV[$i] ne "e_value" || $ARGV[$i] ne "align_length");
		$temp_filter_order = $temp_filter_order . $ARGV[$i] . ",";
	}
	$filter_order = $temp_filter_order;
}

#hopefully it will work
#test
#print "$filter_order\n";

open (my $blast_fh, '<', $blast) || die "Cannot open the blast file $blast\n\n";
#open (my $out_fh, '>', $output) || die "Cannot open output fasta: $output\n\n";

#blast m8 format with array index:
#0: query	
#1: subject	
#2: %id	
#3: alignment length
#4: mismatches	
#5: gap openings	
#6: query start
#7: query end
#8: subject start
#9: subject end	
#10: E value
#11: bit score

#actually, should just load cns into hash, then loop through blast


#load blast into 2d array to sort, 
#this might get a little dicey if big blast file, 
#I'm working with arabidopsis and on a cluster so I am not worried, 
#not taking the time to do otherwise, 
#I mean, you have to load it all in to sort, right?


my @blast;
while (my $line = <$blast_fh>) {
	chomp $line;
	next if ($line =~ /^#/);
	my @info = split("\t",$line);
	#Skip if identical gene
	next if ($info[0] eq $info[1] && defined $self_comp && $self_comp eq "true");
	push(@blast, \@info);
}

my @filter_order = split(",",$filter_order);

my $filter_number = 0;
#define sort string
my $sort_code= " ";
#for the queryid / refid sorting:
my $op;

for (my $i=0; $i<@filter_order; $i++) {
	#not even sure this will work, try test
	#yea this isn't going to workout
	#make strings to put.. but how can interpret variable in string.... maybe different subroutines depending on number of fields then separate strings for the number of fields, then would still be six different loops, still a little different if starts is one.. we can try
	#can we just sort by all columns, but the b a thing switching on start / stop.. :/
	next if (!defined $filter_order[$i]);
	if ($filter_order[$i] eq "bit_score") {
		$sort_code = $sort_code . '\$b->[11] <=> \$a->[11]' . ' || ';
	}
	elsif ($filter_order[$i] eq "align_length") {
		$sort_code = $sort_code . '\$b->[3] <=> \$a->[3]' . ' || ';
	}
	elsif ($filter_order[$i] eq "e_value") {
		$sort_code = $sort_code . '\$a->[10] <=> \$b->[10]' . ' || ';
	}
	else {
		die "Make sure the filter_order matches one of the optional flags\n$usage";
	}
	$filter_number = $filter_number + 1;
}

#defaults
my @sorted_blast;
if ($filter_number == 0) {
	#default
	print "using default sort: bit score then alignment length\n";
	$sort_code = $sort_code . '\$a->[11] <=> \$b->[11]' . ' || ';
	$sort_code = $sort_code . '\$a->[3] <=> \$b->[3]' . ' || ';
	@sorted_blast = sort {
		$b->[11] <=> $a->[11] ||
		$b->[3] <=> $a->[3]
	} @blast;
}
else {
	#remove last ' || ' added
	$sort_code =~ s/\s\|\|\s$//;
	@sorted_blast = sort {custom_sort()} @blast;
	sub custom_sort {
		eval qq{$sort_code};
	}
}

#test
#print "$sort_code\n";
#die;

#sort blast 2d array, hmm, should group by query hit right? like queryID
#ahh I think I want to sort each is what I wants, best way to do that? first sort by query ID, yupp, well thats for my purposes, I'll make sure to specify on cmd line



#hmm, just print out now right? ahh make hash to trim if number of hits falls
#not sure why you would want to filter out after x amount of specific reference hits, if you really need that, either rerun the blast search, or simply switch the ref / query columns in your blast file

#hash with queryid => number of times seen
my %seen_it;
#blast translation hash
my %blast_trans;

#output file, just going to be blast.best_hit
my $blast_filtered = $blast . "_best_hit";
if (-e $blast_filtered && (!(defined $force))) {
print "File: $blast_filtered or exist, is it okay to overwrite it?\n"; 
my $answer = <STDIN>;
	if ($answer =~ /^y(?:es)?$/i) {
		print "Excellent!\n";
	}
	else {
		die "fine, I will not overwrite your files, but I will also not run this script\n";
	}
}
open (my $blast_out_fh, '>', $blast_filtered) || die "Cannot open blast output: $blast_filtered\n\n";

#hash that stores the best reference transcript for each gene
#key is query gene,
#value is best reference transcript
my %best_reference;
# I need to link each query gene to every single one of its best transcripts, 
# hash of arrays? that works right?
# then loop through until you get a match, man thats clunky, but how else to do it??

PRINT_BLAST: for (my $i=0; $i<@sorted_blast; $i++) {
	#HoA best_reference processing
	#check if that transcript has been loaded, if so, skip
	#looping through every time, but will never get above the size of max number of transcripts so we good
	#loop control:
	my $best_ref_check = 1;
	#dont worry about loop name, just need something to tell perl to break out of
	if (defined $best_reference{$sorted_blast[$i][0]}) {
		FEBR: foreach my $transcript ($best_reference{$sorted_blast[$i][0]}) {
			#split transcript to base
			my @base_transcript = split(/\./,$transcript);
			my @base_reference = split(/\./,$sorted_blast[$i][1]);
			if ($base_transcript[0] = $base_reference[0]) {
				#get out of this foreach loop and skip
				$best_ref_check = 0;
				#print "immediately lasting febr\n";
				last FEBR;
			}
		}
		#print "still in if loop\n";
	}
	#print "outside of if loop\n";
	if ($best_ref_check) {
		#haven't seen this transcript yet, add to HoA
		push( @{ $best_reference { $sorted_blast[$i][0] }}, $sorted_blast[$i][1])
	}
	if ($seen_it{$sorted_blast[$i][0]}) {
		if ($seen_it{$sorted_blast[$i][0]} >= $number_hits) {
			next PRINT_BLAST;
		}
		else {
			$seen_it{$sorted_blast[$i][0]} = $seen_it{$sorted_blast[$i][0]} + 1;
		}
	}
	else {
		#set to 1
		$seen_it{$sorted_blast[$i][0]} = 1;
	}
	for (my $j=0; $j < @{$sorted_blast[$i]}; $j++) {
		print $blast_out_fh "$sorted_blast[$i][$j]\t";
	}
	#load into blast translation hash
	$blast_trans{$sorted_blast[$i][0]} = $sorted_blast[$i][1];
	print $blast_out_fh "\n";
}

close $blast_out_fh;
close $blast_fh;

##################################################################
######			create anchor translation hash				######
##################################################################

open (my $anchor_fh, '<', $anchor) || die "Cannot open the anchor file $anchor\n\n";

my %seen_it_ref;
#keep count of duplicates:
my $seen_it = 0;

#relics of anchors_to_trans.pl, keep it, additionally if want to reverse anchor trans hash, can just flip these two
my $ref_col = 1;
my $query_col = 0;

my %anchor_trans;

ANCHOR: while (my $line = <$anchor_fh>) {
	chomp $line;
	next if ($line =~ /^#/);
	my @line = split("\t",$line);
	#skip same hits if self comp
	next if ($line[0] eq $line[1] && defined $self_comp && $self_comp eq "true");
	#looks like column 1 is always ref
	#col 2 query
	#col 3 bit score
	#can run it so ref is in column 1 or two, so fix that:
	if ($anchor_trans{$line[$query_col]}) {
		#some bit scores have the letter "L" next to them in the .lifted.anchors file
		#it stands for "lifted" as this hit came from the unfiltered last file
		#and the anchors file was made from the filtered file 
		#this should handle both cases
		my @number = split("L",$anchor_trans{$line[$query_col]}[2]);
		my @line_two = split("L",$line[2]);
		if ($number[0] > $line_two[0]) {
			#next one we encountered is not greater than current best, skip
			next ANCHOR;
		}
		elsif ($number[0] == $line_two[0] && $anchor_trans{$line[$query_col]}[$ref_col] ne $line[$ref_col]) {
			##########RELICS OF anchors_to_trans.pl, leaving in here##############
			#testing case where two AT gene IDs have the same bit score, 
			#figure out later if it comes to this
			#print $out_fh "ATs: $seen_it_augustus{$line[$aug_col]}[$at_col]\t$line[$at_col]\n";
			#print $out_fh "AUGs: $seen_it_augustus{$line[$aug_col]}[$aug_col]\t$line[$aug_col]\n";
			#print $out_fh "scores: $seen_it_augustus{$line[$aug_col]}[2]\t$line[2]\n";
			#die "Found augustus gene with two equal bit score AT genes:\n" .
			#"$seen_it_augustus{$line[$aug_col]}[$at_col] and $line[$at_col]\n" .
			#"scores (respectively): $number[0] and $line[2]\n";
			########just comment it all out, we will just keep the first one we run into############
			next ANCHOR;
		}
		else {
			#need to overwrite current hit because we found one better
			$anchor_trans{$line[$query_col]} = \@line;
		}
	}
	else {
		$anchor_trans{$line[$query_col]} = \@line;
	}
}



#loop below outputs:
#Chr4.g3076.t4   AT4G28490
#Chr2.g1787.t5   AT2G21490
#Chr5.g1131.t1   AT5G55900
#foreach my $k (keys %seen_it_augustus) {
#	$anchor_trans{$seen_it_augustus{$k}[$query_col]} = $seen_it_augustus{$k}[$ref_col];
#}


#now anchor trans hash is $anchor_trans{$seen_it_augustus{$k}[$query_col] to $seen_it_augustus{$k}[$ref_col]
#what are the keys??

#now we have anchor HoA and blast hash, lets compare
#HoA: accession -> line of anchor file 
#blast hash: accession -> tair
my $same_both = 0;
my $diff_def = 0;
my $def1 = 0;
my %out_trans;

#hash to check values, make sure unique tag added
my %value_check;
#my $dummy = 0;

#going to delete trans2 key-value pairs if different so can see how many defined in trans2 but not trans1
#variable specs going to be a little rough, will try to explain, bear with me
#to make matters worse, anchor file does not have transcript identifiers, so need to go back for that
#but since filtered only the best hit, if they disagree.... the information is lost... nooooo
#need to go back even further, but then would have to loop through every reference hit for this given query....
#see if we even need to do this
foreach my $query_anchor (keys %anchor_trans) {
	#new plan:
	#add transcript to anchor_trans value
	#add tag if seen this transcript before
	
	#adding transcript:
	BRTS: foreach my $transcript ($best_reference{$query_anchor}) {
		#split transcripts to base
		my @base_transcript = split(/\./,$transcript);
		if ($base_transcript[0] eq $anchor_trans{$query_anchor}[$ref_col]) {
			$anchor_trans{$query_anchor}[$ref_col] = $transcript;
			#and can break out of this loop
			#print "lasting brts\n";
			last BRTS;
		}
		else {
			#still searching
		}
	}	
	#should check if didn't find anything because that can be a problem right? well not really,
	#only a problem if there are some in cds file that don't have a transcript
	#and same base that do have transcript, then will be unambiguous
	#but if some unique IDs don't have transcript identifier (eg .1, .2),
	#then this will still be able to unambiguously id in cds file
	#thats what really matters here
	
	#add tag if seen transcript before:
	if (defined $value_check{$anchor_trans{$query_anchor}[$ref_col]}){	
		$value_check{$anchor_trans{$query_anchor}[$ref_col]} += 1;
	}
	else {
		$value_check{$anchor_trans{$query_anchor}[$ref_col]} = 1;
	}
	$anchor_trans{$query_anchor}[$ref_col] .= "_" . 
		$value_check{$anchor_trans{$query_anchor}[$ref_col]};
	
	#add to final hash:
	$out_trans{$query_anchor} = $anchor_trans{$query_anchor}[$ref_col];
}

#######old method code chunk, leave incase need to borrow from later
#	#check if added this reference gene to out_trans already
#	#if so, add a tag to it
#	if (defined $value_check{$anchor_trans{$query_anchor}[$ref_col]}){	
#		$value_check{$anchor_trans{$query_anchor}[$ref_col]} += 1;
#	}
#	else {
#		$value_check{$anchor_trans{$query_anchor}[$ref_col]} = 1;
#	}
#	#add tag:
#	my $pretag = $anchor_trans{$query_anchor}[$ref_col];
#	my @base_transcript;
#	#print "blast query: $blast_trans{$query_anchor}\n";
#	if (defined $blast_trans{$query_anchor}) {
#		if ($blast_trans{$query_anchor} =~ /\./) {
#			@base_transcript = split(/\./,$blast_trans{$query_anchor});
#		}
#		else {
#			$base_transcript[0] = $blast_trans{$query_anchor};
#		}
#	}
#	else {
#		$base_transcript[0] = "nope";
#	}
#	#print "base: $base_transcript[0]\n";
#	$anchor_trans{$query_anchor}[$ref_col] .= "_" . $value_check{$anchor_trans{$query_anchor}[$ref_col]};
#	#same in both files:
#	#below states: If anchor translation for a given query is the same as best blast hit
#	#print "blast trans: $blast_trans{$query_anchor}\n";
#	#print "pretag: $pretag\n";
#	#print "base_trans: $base_transcript[0]\n";
#	#if ($dummy == 100) {
#	#	die;
#	#}
#	#$dummy += 1;
#	if (defined $blast_trans{$query_anchor} && $pretag eq $base_transcript[0]) {
#		#inside this loop, I keep track of how many times the two agree with each other,
#		#gives me an idea of how useful taking this approach really is instead of simply taking best blast hit
#		$same_both = $same_both + 1;
#		#I delete the value so later I canz
#		#go through and fill in all translations that aren't in anchor trans
#		delete $blast_trans{$query_anchor};
#		$out_trans{$query_anchor} = $anchor_trans{$query_anchor}[$ref_col];
#	}
#	#trans1 does not match trans2, both both are defined
#	#in case of disagreement, take the anchors file one
#	elsif (defined $blast_trans{$query_anchor}) {
#		$diff_def = $diff_def + 1;
#		#find best transcript if exists in blast file:
#		BRTS: foreach my $transcript ($best_reference{$query_anchor}) {
#			#split transcripts to base
#			my @base_transcript = split(/\./,$transcript);
#			if ($base_transcript[0] eq $anchor_trans{$query_anchor}[$ref_col]) {
#				$anchor_trans{$query_anchor}[$ref_col] = $transcript;
#				#and can break out of this loop
#				#print "lasting brts\n";
#				last BRTS;
#			}
#			else {
#				#still searching
#			}
#		}
#		#print "right outside brts\n";
#		#die;
#		$out_trans{$query_anchor} = $anchor_trans{$query_anchor}[$ref_col];
#		delete $blast_trans{$query_anchor};
#	}
#	#blast_trans not defined,,, hmm okay
#	#if blast isn't defined then anchors will not be defined because anchors file
#	#made from blast file (or last whatever the heck you used)
#	#get that extra check in there just in case in anchors but not the blast file
#	#blast not defined by anchors is, don't anticipate ever entering this but just in case:
#	else {
#		$out_trans{$query_anchor} = $anchor_trans{$query_anchor}[$ref_col];
#		$def1 = $def1 + 1;
## depreciated warning, solved it... I think... nope thats weird, why... ahh not best, should remove this loop
## no still good to check
#		print "WARNING!!!\t" .
#			"Anchor found, but no blast found. " .
#			"possible no transcript identifier for this guy: " . 
#			"$query_anchor\t$anchor_trans{$query_anchor}[$ref_col]\n";
#	}
#}

my $def2 = scalar keys %blast_trans;
foreach my $key2 (keys %blast_trans) {
	#check if added this reference gene to out_trans already
	#if so, add a tag to it
	if (defined $value_check{$blast_trans{$key2}}){	
		$value_check{$blast_trans{$key2}} += 1;
	}
	else {
		$value_check{$blast_trans{$key2}} = 1;
	}
	#add tag
	if ($no_tag) {
		#no tag adding
	}
	else {
		#add tag
		#print "added tag\n";
		#die;
		$blast_trans{$key2} .= "_" . $value_check{$blast_trans{$key2}};
	}
	$out_trans{$key2} = $blast_trans{$key2};
}

open (my $out_fh, '>', $output) || die "Cannot open output $output\n\n";

foreach my $out_key (keys %out_trans) {
	print $out_fh "$out_key\t$out_trans{$out_key}\n";
}

#print out some stats
#print "Agreement between the two trans files:\t$same_both\n";
#print "Disagreement between two trans files:\t$diff_def\n";
#print "Only defined in anchor trans:\t$def1\n";
#print "Only defined in blast trans:\t$def2\n";

exit;


