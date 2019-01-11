#! /usr/bin/perl -w

# unlink.pl
# bash was too slow with removing files so hopefully this will go much faster
# 12-27-18
# Alan E. Yocca

use strict;
use warnings;
use Getopt::Long;


my $usage = "\n$0\n" .
			"\t--file <remove single file, or comma separated list>\n" .
			"\t--file_list <remove list of files, one file per line>\n" .
			"\t--dir <remove entire directory>\n" .
			"\t--force <do not ask, even when asking, only asks ONCE!!>\n" .
			"\t--verbose <spit the name of every file being deleted>\n" .
			"\t--help <listen to me ramble>\n";

my @file;
my $file_list;
my $dir;
my $force=0;
my $verbose=0;
my $help=0;


GetOptions ( "file=s" => \@file,
  "file_list=s" => \$file_list,
  "dir=s"  => \$dir,
  "help" => \$help,
  "verbose" => \$verbose,
  "force" => \$force
) or die "$usage\n";

#dereference the array indirectly I believe
@file = split(/,/,join(',',@file));

if (! defined $file[0] && ! defined $file_list && ! defined $dir) {
	die "\nYou have given me nothing to delete\n\n";
}

if ($help) {
	print "\nMade this since bash is so stupidly slow at deleting files\n" .
	"according to a few online sources, seems perl's unlink() function is one of the fastest performers\n" .
	"I am no computer whiz, so USE AT YOUR OWN RISK\n" .
	"if this breaks your computer or removes some important files,\n" .
	"Too bad, too sad I warned you\n\n" .
	"Seriously though I hope this helps, feed in either a comma separated list of files,\n" .
	"or with --file_list remove every file in that file (woah), where there is one file per line\n" .
	"will not remove the file specified by --file_list so you can see what you deleted\n" .
	"If anything in file comma separated list or in file_list are a directory, think will throw an error\n";
	die "$usage\n";
}

if (! $force ) {
print "Are you sure you want to overwrite the files specified on the command line?\n" .
		"Seriously, you should double check\n"; 
my $answer = <STDIN>;
	if ($answer =~ /^y(?:es)?$/i) {
		print "Alrighty, deleting like a mad man then!\n";
	}
	else {
		die "Alrighty, I will not delete your files\n";
	}
}

if (defined $file[0]) {
	foreach my $delete (@file) {
		if ( ! -f $delete ) {
			print "$delete is not a regular file, continuing to delete the rest though\n";
		}
		unlink($delete);
		print "Deleting $delete\n" if $verbose;
	}
}

if (defined $file_list) {
	open (my $fl_fh, '<', $file_list) || die "Cannot open the file list $file_list\n\n";
	while (my $line = <$fl_fh>) {
		chomp $line;
		unlink($line);
		print "Deleting $line\n" if $verbose;
	}
	close $fl_fh;
}

if (defined $dir) {
	if (! -d $dir) {
		die "\n$dir is not a directory\n\n";
	}
	my @files_in_dir = <$dir/*>;
	foreach my $delete (@files_in_dir) {
		unlink($delete);
		print "Deleting $delete\n" if $verbose;
	}
	#finish off the dir too
	rmdir($dir) or warn "Can't delete $dir\n";
	print "Deleted $dir (unless warning)\n" if $verbose;
}

print "Done deleting all files\n" if $verbose;

exit;












