#README for ka_ks_pipe
#first shared 12-03-18
#Alan E. Yocca

#example found in ka_ks_pipe/test_2/

#####Binaries compiled on University server, will likely not work when downloaded through here
#####Find binaries for these, compile locally and keep binary in bin/:
#####	- MUSCLE v3.8.31 (Edgar 2004)
#####	- PAL2NAL (v14) (Suyama and Torrents 2006)
#####	- codeml binary within PAML Version 4.9h (Yang 2007)

#ka_ks pipeline to call ka/ks on lists of gene pairs

#all input files need to be in a directory called:
01_data/
#within a specified working directory

#inputs required:
- cds file for reference
- cds file for query

#if that is all you provide, need;
- msu hpcc virtual environment capable of running jcvi mcscan

#optional input files
- pep file for reference
- pep file for query
	- this speeds things up because it aligns the proteins rather than nucleotides
- translation file
	- skips the in script ortholog caller
	- provide your own ortholog translations, 
	- reference in first column
	- tab separated
	- query in second column
	- can be on to many relationship if column separated by a comma

#creates the following directory structure within the working directory
01_data/
	01_split/
	#inside has various files used for parallelization
	#also all the pairs extracted to their own files
02_aln/
	#pep and cds alignments of each pair
03_codeml/
	#final output:
	ref.query.ka.ks.txt
	01_split/
	#contains directories,
		ref_query_pair/
		#each ref_query pair directory has:
		#codeml ctl file
		#codeml output
		#parsed codeml output? maybe depreciated at this point

#a few other notes:
- cds and pep files need to have the same name except for the ".cds" and ".pep" part

#example to rerun test_2
#recommend making another directory to test and moving over to 01_data:
- all.cds
- all.pep
- TAIR10_cds.cds
- TAIR10_cds.pep
- all.TAIR10_cds.trans.txt

#and run the command:
$/path_to/ka_ks_pipe/bin/ka_ks_launch.sh \
--ref TAIR10_cds \
--query all \
--trans /path_to/ka_ks_pipe/test_2/01_data/all.TAIR10.trans.txt \
--wkdir /path_to/ka_ks_pipe/test_2/ \
--script_dir /path_to/ka_ks_pipe/bin \
--keep_files \
--lines 6

#references:
Yang, Z. 2007. PAML 4: a program package for phylogenetic analysis by maximum likelihood. Molecular Biology and Evolution 24: 1586-1591 (http://abacus.gene.ucl.ac.uk/software/paml.html).

Suyama M, Torrents D, Bork P. PAL2NAL: robust conversion of protein sequence alignments into the corresponding codon alignments. Nucleic Acids Res. 2006; 34(2):609–12.

Edgar, R.C. (2004) MUSCLE: multiple sequence alignment with high accuracy and high throughput
  Nucleic Acids Res. 32(5):1792-1797
