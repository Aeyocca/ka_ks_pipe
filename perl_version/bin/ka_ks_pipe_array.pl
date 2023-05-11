#! /usr/bin/perl -w

# ka_ks_pipe_array.pl
# bash was too slow with file i/o so hopefully translating to perl will make it much faster
# 12-10-18
# probably going to rip code from:
# Michael McKain
# Props to him, thank you
# Alan E. Yocca


use strict;
use warnings;
use Getopt::Long;


my $usage = "\n$0\n" .
			"\t--query <query>\n" .
			"\t--ref <ref>\n" .
			"\t--wkdir <working directory>\n" .
			"\t--ref_peptide_check <0 or 1>\n" .
			"\t--query_peptide_check <0 or 1>\n" .
				"\t\t<this and ref check done in ka_ks_pipe.sbatch>\n" .
			"\t--script_dir <script directory>\n" .
			"\t--keep_files <keep files??>\n" .
			"\t--resume <read through meta file first??>\n" .
				"\t\t--not boolean, provide \"true\" if want to\n" .
			"\t--split_file <split translation file>\n\n";

#Needs read in as arg:
	#${RESUME}
	#${REF}
	#${QUERY}
	#${WKDIR}
	#${script_trans}
		# I think I might drop this? check if is part of jcvi.compara stuff
	#${ref_peptide_check}
	#${query_peptide_check}
	#${SCRIPT_DIR}
	#${SPLIT_FILE}

my $resume;
my $query;
my $ref;
my $wkdir;
my $ref_peptide_check;
my $query_peptide_check;
my $script_dir;
my $split_file;
my $keep_files = '';

GetOptions ( "query=s" => \$query,
  "ref=s" => \$ref,
  "wkdir=s"  => \$wkdir,
  "ref_peptide_check=s"  => \$ref_peptide_check,
  "query_peptide_check=s"  => \$query_peptide_check,
  "script_dir=s" => \$script_dir,
  "split_file=s" => \$split_file,
  "resume=s" => \$resume,
  "keep_files" => \$keep_files
) or die "$usage\n";

if ( (!(defined $query)) || !defined $ref || ! defined $script_dir || ! defined $split_file || ! defined $ref_peptide_check || ! defined $query_peptide_check) {
  print "$usage";
  exit;
}


#A lottt to unpack here, read in possibilities and get to work, see what we needs:
#just writing every variable in that loop I see


#Made in ka_ks_pipe_array.sbatch
#inside loop:
	#${dN}
	#${dS}
	#${dNdS}
	#${EXTENSION}
	#${pair[0]}
	#${pair[1]}
	#${ref_extract}
		#along with script_trans, check if you actually need to do this check
	#${extract_count}
		#see if it pulled two out using grep, executing perl scripts in this hmmm
		#maybe a way to have them return an exit value??
		#would be faster theoretically to just die in this script if not found 2
		#otherwise would cost to check after making output file
	#${CTL_FILE}
		#need to make sure length of this file name and seqfile name short enough ugh
		

#outside loop:
	#${SPLIT_FILE_BASE}
		#the array specific output so not jumping over each other for output

#Needs read in as arg:
	#${RESUME}
	#${REF}
	#${QUERY}
	#${WKDIR}
	#${script_trans}
		# I think I might drop this? check if is part of jcvi.compara stuff
	#${ref_peptide_check}
	#${query_peptide_check}
	#${SCRIPT_DIR}
	#${SPLIT_FILE}

#thats good for now, add more as you need them

#first thing, read in ref and query gene
#loop through split file
#ooooo lets load all ref_query stuff into a hash and go through hash so only have to i/o pep/cds once
#thats neat..

#load ref query pairs into hash
#changed my mind, make array instead of hash
#seq check so only load part of fastas into memory
open (my $split_fh, '<', $split_file) || die "Cannot open the split file $split_file\n\n";
my (@rq_pairs, %seq_check,%resume_check);

if ($resume eq "true") {
	print "Resume is set to true, only running on those not in loop meta file\n";
	(my $split_file_base_resume = $split_file) =~ s|^.*/||g;
	my $loop_ks_out_resume = $wkdir . "/03_codeml/01_split/" . $split_file_base_resume . ".ka.ks.meta.txt";
	my $ksout_resume_fh;
	open ($ksout_resume_fh, '>', $loop_ks_out_resume) or $ksout_resume_fh = open_reading($loop_ks_out_resume);
	while (my $line = <$ksout_resume_fh>) {
		chomp $line;
		my @line = split("\t",$line);
		my $pair = $line[5] . "\t" . $line[6];
		$resume_check{$pair} = 1;
	}
}


PAIR_LOADING: while ( my $line = <$split_fh>) {
	chomp $line;
	#if already calculated, don't work on
	if (defined $resume_check{$line}) {
		#have this rq pair done already
		next PAIR_LOADING;
	}
	my @line = split("\t",$line);
	push @rq_pairs, $line;
	#these are when reading data in from fastas so don't have to take the whole file in
	$seq_check{$line[0]} = 1;
	$seq_check{$line[1]} = 1;
	print "Query gene: $line[1]\n";
}
close $split_fh;

#extract cds and pep of everything
#check if pep exists
my $EXTENSION = ".cds";
#define here, because will populate if I need to,
#want to only do this once, so outside
#the rq_pairs looping
my (%ref_cds, %query_cds);
if ($ref_peptide_check && $query_peptide_check) {
	#pep exists
	#debug
	print "Pep exists!!\n";
	$EXTENSION = ".pep";
	#populate cds hashes here
	my $ref_cds_full_path= $wkdir . "/01_data/" . $ref . ".cds";
	my $query_cds_full_path= $wkdir . "/01_data/" . $query . ".cds";
	%ref_cds = getSeq($ref_cds_full_path,\%seq_check);
	%query_cds = getSeq($query_cds_full_path,\%seq_check);
}
my $ref_gene_full_path= $wkdir . "/01_data/" . $ref . $EXTENSION;
my $query_gene_full_path= $wkdir . "/01_data/" . $query . $EXTENSION;
my %ref_seq = getSeq($ref_gene_full_path,\%seq_check);
my %query_seq = getSeq($query_gene_full_path,\%seq_check);
#ugh, should make this a subroutine but eh give it a shot

#nice, next, loop through split file,

#open ks file for this loop
(my $split_file_base = $split_file) =~ s|^.*/||g;

my $loop_ks_out = $wkdir . "/03_codeml/01_split/" . $split_file_base . ".ka.ks.meta.txt";
my $ksout_fh;
open ($ksout_fh, '>', $loop_ks_out) or $ksout_fh = open_reading($loop_ks_out);

use IPC::Run3 qw(run3);



foreach my $pairs (@rq_pairs) {
	my ($ref_gene, $query_gene) = split("\t",$pairs);
	#checks:
	print "Starting on gene pair:\n" .
	"Ref: $ref_gene\n" . "Query: $query_gene\n";
	#create fasta variable
	my $fasta = ">" . $ref_gene . "\n" .
				$ref_seq{$ref_gene} . "\n" .
				">" . $query_gene . "\n" .
				$query_seq{$query_gene};
	#pass fasta variable to muscle, the fun part
	#use IPC::Run3 qw(run3);
	my ($aligned, $err);
	my $muscle_exe = $script_dir . "/muscle3.8.31_i86linux64";
	run3 [$muscle_exe], \$fasta, \$aligned, \$err;
	print "Muscle Std Error: \n$err\n";
	
	#check for pep, convert to nucleotide if need to
	if ($ref_peptide_check) {
		#convert to cds alignment
		#need to edit pal2nal to read in variables...
#####	debug
#		#find whats uninit in next block:
#		print "ref gene: $ref_gene\n" .
#		"ref_gene seq: $ref_cds{$ref_gene}\n" .
#		"query gene: $query_gene\n" . 
#		"query_gene seq: $query_cds{$query_gene}\n";
#		die;
#####
		my $cds_fasta = ">" . $ref_gene . "\n" .
				$ref_cds{$ref_gene} . "\n" .
				">" . $query_gene . "\n" .
				$query_cds{$query_gene};
		my $pal2nal_exe = $script_dir . "/pal2nal_aey.pl";
		my $p2n_opt_outf = "-output";
		my $p2n_opt_outv = "paml";
		my $p2n_opt_alnf = "-aln";
		my $p2n_opt_cdsf = "-cds";
		my ($cds_aln, $pal2nal_err);
		use IPC::Run3 qw(run3);
		run3 [$pal2nal_exe, 
			$p2n_opt_outf, 
			$p2n_opt_outv, 
			$p2n_opt_alnf, 
			$aligned, 
			$p2n_opt_cdsf, 
			$cds_fasta], undef, \$cds_aln, \$pal2nal_err;
		print "pal2nal error:\n$pal2nal_err\n";
		$aligned = $cds_aln;
	}
	
	##print alignment out to file for codeml to use
	my $aln_out = $wkdir . "/02_aln/" . $ref . "." . $query . "." .
					$ref_gene . "." . $query_gene . ".aln.cds";
	my $aln_out_fh;
	open ($aln_out_fh, '>', $aln_out) or $aln_out_fh = open_reading($aln_out);
	print $aln_out_fh "$aligned\n";
	close $aln_out_fh;
	
	#add things to new codeml ctl file
	#Codeml, what a pain.. max ctl file length 95 characters
	###################################
	#Also, creates files in output directory 
	#for intermediate processes, 
	#but don't have unique names
	#So give each output a unique output directory
	#ref query pair directory
	my $RQpdir = $ref . "." . $query . "." .
				$ref_gene . "." . $query_gene;
	my $CTL_FILE= $RQpdir . ".codeml.ctl";
	my $codeml_dir = $wkdir . "/03_codeml/01_split/" . $RQpdir; 
	my @previous_codeml_out = <$codeml_dir/*>;
	foreach my $file (@previous_codeml_out) {
		unlink($file);
	}	
	mkdir $codeml_dir;
	chdir $codeml_dir;
	if ( length($CTL_FILE) > 95) {
		#Too long, new tmp name based on date
		use POSIX qw(strftime);
		#year(last 2 digits)_month(abr)_dayofmonth(zero padded)_hour_minute_second
		my $tmp_date = strftime "%y_%b_%d_%H_%M_%S", localtime;
		$CTL_FILE= $tmp_date . ".codeml.ctl";
		print "CTL file length too long (thanks codeml), new codeml ctl file name: $CTL_FILE\n";
	}
	unlink($codeml_dir . "/" . $CTL_FILE);
	
	#populate CTL_FILE, need to make seqfile path relative, then check if still too long
	#if so, move to current directory and change to tmp_date
	#thanks codeml this isnt a pain at all, use vertical bars so don't have to escape slashes
	$aln_out =~ s|$wkdir|\.\./\.\./\.\.|ig;
	if ( length($aln_out) > 155 ) {
		#Too long, new tmp name based on date
		use POSIX qw(strftime);
		#year(last 2 digits)_month(abr)_dayofmonth(zero padded)_hour_minute_second
		my $tmp_date = strftime "%y_%b_%d_%H_%M_%S", localtime;
		use File::Copy qw(move);
		move $aln_out, $tmp_date . ".aln.cds";
		$aln_out = $tmp_date . ".aln.cds";
		print "aln file length too long (thanks codeml), new aln filename: $aln_out\n";
	}
	my $ctl_params = "seqfile = " . $aln_out;
	$ctl_params .= "\n" . "outfile = " . $RQpdir . ".ka.ks.txt\n";
	my $ctl_stat = $script_dir . "/codeml.ctl.static";
	open (my $ctl_stat_fh, '<', $ctl_stat) || die "Cannot open the static codeml ctl file $ctl_stat\n\n";
	while (my $ctl_line = <$ctl_stat_fh>) {
		chomp $ctl_line;
		#think can just not chomp here?? o whale
		$ctl_params .= $ctl_line . "\n";
	}
	close $ctl_stat_fh;
	my $ctl_fh;
	open ($ctl_fh, '>', $CTL_FILE) or $ctl_fh = open_reading($CTL_FILE);
	print $ctl_fh "$ctl_params";
	close $ctl_fh;
	#run codeml in here, store output in variable, and extract necessary information
	#ugh, can't store output in variable.. but can extract necessary values in here
	system "$script_dir/codeml $CTL_FILE";
	
	#parse the output, ripped from Mike McKain
	open (my $codeml_out_fh, '<', $RQpdir . ".ka.ks.txt") || die "Cannot open the codeml output file $RQpdir.ka.ks.txt\n\n";
	while (my $codeml_line = <$codeml_out_fh>){
		chomp $codeml_line;
		if ($codeml_line =~ /^t=/){
			 my ($dnds,$dn,$ds) = ($1,$2,$3) if ($codeml_line =~ /dN\/dS\s*=\s*(\d+\.\d+)\s+dN\s*=\s*(\d+\.\d+)\s+dS\s*=\s*(\d+\.\d+)/);
			print $ksout_fh "$ref\t$query\t$dn\t$ds\t$dnds\t$ref_gene\t$query_gene\n";
		}
	}
    close $codeml_out_fh;
    
    #if keep files, don't remove, if not, knock stuff out
    if (defined $keep_files && $keep_files eq "true") {
    	print "Keeping files\n";
    }
    else {
    	unlink($aln_out);
    	system "rm -rf $codeml_dir";
    }
	print "Finished gene pair\n";
}

close $ksout_fh;
exit;

##################################################
sub getSeq {
	#loop through fasta file,
	#saves hash you specify where key is header before first space
	#value is sequence
	#hmmmm should do optional only the genes in this split....
	my ($file, $hash_gene_check) = @_;
	my %hash_gene_check = %$hash_gene_check if (defined $hash_gene_check);
	my $hgc = 0;
	
	#DEBUG
	#my $hgc_size = keys %hash_gene_check;
	#print "hgc size: $hgc_size\n";
	#foreach my $key (keys %hash_gene_check) {
	#	print "key: $key\n";
	#	print "value: $hash_gene_check{$key}\n";
	#}
	#die;
	
	if (keys %hash_gene_check) {
		#gene check hash provided
		$hgc = 1;
	}
	open (my $sf_fh, '<', $file) || die "Cannot open the sequence file $file\n\n";
	my ($header, %seq_hash);
	my $skip = 0;
	FASTA: while (my $line = <$sf_fh>) {
		#should be a fasta file, so load headers as key, sequence as value
		chomp $line;
		if ($line =~ /^>/) {
			#split file should only be whats before the space and after the ">"
			#handle spaces after carrot:
			$line =~ s/> />/g;
			my @tmp = split(" ",$line);
			my @seq = split(">",$tmp[0]);
			#check if this header in the list of things we want,
			if ($hgc && ! defined $hash_gene_check{$seq[1]}) {
				#print "Not in seq check; $seq[1]\n";
				$skip = 1;
				next FASTA;
			}
			#print "Found in seq_check: $seq[1]\n";
			#keep in $header variable to handle wrapped fastas
			$header = $seq[1];
			#initialize
			$seq_hash{$header} = "";
			$skip = 0;
		}
		#$hgc here not entirely necessary but leaving it
		elsif ($hgc && $skip) {
			#skip this gene, not in this split file
			next FASTA;
		}
		else {
			#load in sequence
			#adding lets it handle wrapped fastas, grab everything under header before next
			$seq_hash{$header} .= $line;
		}
	}
	return %seq_hash;
}

sub open_reading {
	my ($file) = @_;
	#check for directory existing
	use File::Basename;
	my $DIR = dirname($file);
	if (! -e $DIR) {
		die "Directory for file does not exist: " . "\n" .
			"$DIR\n\n";
	}
	#Since directory exists, the only way
	#to not be able to open this file is:
	#filename has characters not allowed by OS or
	#my reason for writing this, filesystem
	#clunk out when overloaded and can't
	#create a file, so just need to try again I guess
	#Try 100 times, arbitrary number, maybe change
	my $loop_var=1;
	my $fh_out;
	while ($loop_var <= 100) {
		open($fh_out, '>', $file) and last;
		#breaks if open successfully
		$loop_var+=1;
	}
	if ($loop_var == 100) {
		die "Failed to open file 100x: $file\n";
	}
	return $fh_out;
}
