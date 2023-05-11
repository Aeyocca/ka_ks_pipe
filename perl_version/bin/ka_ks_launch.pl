#! /usr/bin/perl -w

# ka_ks_launch.pl
# bash doesn't work for jeremy
# 12-18-18
# Alan E. Yocca

use strict;
use warnings;
use Getopt::Long;


my $usage = "\n$0\n" .
			"\t--ref:\n" . 
				"\t\t<basename of reference. REQ if --rq_list not specified>\n" .
				"\t\t<eg if reference cds file is TAIR10.cds, --ref TAIR10>\n" .
			"\t--query:\n" . 
				"\t\t<basename of query. REQ if --rq_list not specified>\n" .
			"\t--rq_list:\n" .
				"\t\t<file with reference and query pairs tab separated, one pair per line>\n" . 
					"\t\t\t<full path please>\n" . 
					"\t\t\t<for running this pipeline many times of different ref/query pairs>\n" .
					"\t\t\t<UNTESTED 12-18-18>\n" .
			"\t--trans:\n" .
				"\t\t<Specify your own translation file if you don't want me to make it for you>\n" . 
					"\t\t\t<First column single reference gene, tab separated second column can be comma separated list of orthologs in query>\n" . 
					"\t\t\t<its ok, my feelings are only hurt a little bit>\n" . 
			"\t--flip:\n" . 
				"\t\t<Flip trans columns if your translation file is in query tab ref form>\n" . 
			"\t--vm:\n" . 
				"\t\t<Specify name of virtual environment name on hpcc that has working version of jcvi mcscanx>\n" . 
					"\t\t\t<mine is called Python2, so defaults to that because Im special>\n" .
			"\t--wkdir:\n" . 
				"\t\t<full path of the working directory>\n" .
			"\t--force:\n" .
				"\t\t<overwrite all files. if not specified, using files that exist>\n" .
			"\t--lines:\n" .
				"\t\t<how many gene pairs to split up this pipeline by>\n" .
				"\t\t<estimated rate for arabidopsis ~600 gene pairs per hour [default]>\n" .
				"\t\t<therefore, running this pipe on 26k A. thaliana will submit ~44 separate arrays in the same job,>\n" .
				"\t\t<each of which runs on 500 genes and completes in ~1 hour>\n" .
			"\t--keep_files:\n" .
				"\t\t<will hold onto all intermediate files, otherwise, get just codeml output>\n" .
			"\t--script_dir:\n" .
				"\t\t<directory of submission scripts if different than directory this script is in>\n" .
				"\t\t<remember, no trailing forward slash>\n" .
			"\t--eo_dir:\n" .
				"\t\t<full path of error/output files>\n" .
				"\t\t<EO OF SCRIPTS, NOT FINAL RESULTS!>\n" .
					"\t\t\t<mostly for debugging, default: \$WKDIR/04_error_output/\n" .
			"\t--self_comp:\n" .
				"\t\t<if specified, this is intraindividual comp, so throw out identical pairs>\n\n";

my $self_comp='';
my $resume;
my $query;
my $ref;
my $wkdir;
my $rq_list;
my $trans;
my $flip='';
my $vm;
my $force='';
my $lines;
my $keep_files='';
my $script_dir;
my $eo_dir;

GetOptions ( "query=s" => \$query,
  "self_comp" => \$self_comp,
  "ref=s" => \$ref,
  "wkdir=s"  => \$wkdir,
  "rq_list=s"  => \$rq_list,
  "trans=s"  => \$trans,
  "script_dir=s" => \$script_dir,
  "eo_dir=s" => \$eo_dir,
  "resume=s" => \$resume,
  "lines=s" => \$lines,
  "force" => \$force,
  "vm=s" => \$vm,
  "flip" => \$flip,
  "keep_files" => \$keep_files
) or die "$usage\n";

#check for some mandatory options:
if (! defined $rq_list && ( ! defined $ref || ! defined $query ) ) {
	print "$usage\n";
    print "MISSING SOME MANDATORY ARGUMENTS!!\n";
	die;
}
elsif ( defined $rq_list && ( defined $ref || $query ) ) {
	print "$usage\n";
	print "DEFINE EITHER --rq_list OR --ref --query, NOT BOTH\n";
}

#check for working directory
if (! defined $wkdir ) {
	print "Working directory not defined, using the one this was launched from:";
	print "`pwd`\n";
	$wkdir=`pwd`;
}

#check for script directory
if ( ! defined $script_dir ) {
	$script_dir=$0;
	print "Script directory not defined, assuming the path to the launch script:\n";
	print "$script_dir\n";
	if ( $script_dir != /^\// ) {
		print "Script dir not defined, and this was lauched from a relative path\n" .
		print "Define script dir (FULL PATH) or launch this using FULL PATH please\n" .
		die;
	}
}

if ( ! defined $vm ) {
	$vm="false";
}

if ($self_comp) {
	$self_comp="true";
}
else {
	$self_comp="false";
}

#resource spec if need to make translation file
my $MEM="88Gb";
my $TASKS="41";
my $TIME="04:00:00";

if (defined $trans ) {
	#change resource request
	$MEM="8Gb";
	$TASKS="2";
	$TIME="00:30:00";
	#flip translation file??
	if ($flip) {
        open (my $trans_fh, '<', $trans) || die "Cannot open the trans file $trans\n\n";
		my @flipped;
        while (my $line = <$trans_fh>) {
        	chomp $line;
        	next if ($line =~ /^#/);
        	my @line = split("\t",$line);
        	my $flipped = $line[1] . "\t" . $line[0];
        	push @flipped, $flipped;
        }
        close $trans_fh;
        my $trans_flip = $trans . "_flip";
        open (my $flipped_fh, '>', $trans_flip) || die "Cannot open the flipped trans file $trans_flip\n\n";
        foreach my $out_line (@flipped) {
        	print $flipped_fh "$out_line\n";
        }
        close $flipped_fh;
        $trans = $trans_flip;
	}
}

#line number
if (! defined $lines ) {
	$lines=500;
}

#keep files?
if ($keep_files) {
	$keep_files="true";
}
else {
	$keep_files="false";
}

#force?
if ($force) {
	$force = "true";
}
else {
	$force = "false";
}

if ( ! defined $eo_dir ) {
	#use default
	print "error output not defined, using default:\n";
	$eo_dir=$wkdir . "/04_error_output";
	print "$eo_dir\n";
}

if ( ! defined $resume) {
	#print "Resume not set, setting to false\n";
	$resume = "false";
}

system ("mkdir -p $eo_dir 2> /dev/null") == 0 or die "failed to create $eo_dir. exiting...\n";


#load rq_list into hash if specified
if ( defined $rq_list ) {
	#open rq_list;
	load into array
	loop through array
	open (my $rq_list_fh, '<', $rq_list) || die "Cannot open the rq_list file $rq_list\n\n";
	my @rq_pairs;
	while (my $line = <$rq_list_fh>) {
    	chomp $line;
        next if ($line =~ /^#/);
        my $rq_pair = $line;
        push @rq_pairs, $rq_pair;
    }
    close $rq_list_fh;
	foreach my $rq_pairs (@rq_pairs) {
		my @rqp = split("\t",$rq_pairs);
		my $ref = $rqp[0];
		my $query = $rqp[1];
		my $EXPORT="REF=$ref,";
			$EXPORT.="QUERY=$query,";
			$EXPORT.="TRANS=$trans,";
			$EXPORT.="VM=$vm," if (defined $vm);
			$EXPORT.="FORCE=$force,";
			$EXPORT.="WKDIR=$wkdir,";
			$EXPORT.="LINES=$lines,";
			$EXPORT.="SCRIPT_DIR=$script_dir,";
			$EXPORT.="KEEP_FILES=$keep_files,";
			$EXPORT.="EO_DIR=$eo_dir,";
			$EXPORT.="SELF_COMP=$self_comp,";
			$EXPORT.="RESUME=$resume";

		my $sbatch = "sbatch --export=$EXPORT " .
			"--output=$eo_dir/%x-%j.SLURMout " .
			"--mem=$MEM " .
			"--ntasks=$TASKS " .
			"--time=$TIME " .
			"$script_dir/ka_ks_pipe.sbatch";
        
    	system("$sbatch");
	}
	my $rq_count = scalar(@rq_pairs);
	print "Submitted for pipe: $rq_count\n";
}
else {
	#submit ref query pair
	my $EXPORT="REF=$ref,";
		$EXPORT.="QUERY=$query,";
		$EXPORT.="TRANS=$trans,";
		$EXPORT.="VM=$vm," if (defined $vm);
		$EXPORT.="FORCE=$force,";
		$EXPORT.="WKDIR=$wkdir,";
		$EXPORT.="LINES=$lines,";
		$EXPORT.="SCRIPT_DIR=$script_dir,";
		$EXPORT.="KEEP_FILES=$keep_files,";
		$EXPORT.="EO_DIR=$eo_dir,";
		$EXPORT.="SELF_COMP=$self_comp,";
		$EXPORT.="RESUME=$resume";

	my $sbatch = "sbatch --export=$EXPORT " .
        "--output=$eo_dir/%x-%j.SLURMout " .
        "--mem=$MEM " .
        "--ntasks=$TASKS " .
        "--time=$TIME " .
		"$script_dir/ka_ks_pipe.sbatch";
        
    system("$sbatch");
	print "Submitted ref query pair: $ref\t$query\n";
}

