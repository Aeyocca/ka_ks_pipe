#!/bin/bash
#ka_ks_pipe.sbatch
#11-12-18
#Alan E. Yocca

#SBATCH --job-name=ka_ks_pipe
#SBATCH --mem=88Gb
#SBATCH --ntasks=41
#SBATCH --time=04:00:00
#SBATCH --output=${WKDIR}/04_error_output/%x-%j.SLURMout

########CHECKING EVERYTHING EXPORTED SUCCESSFULLY
echo "REF=${REF}"
echo "QUERY=${QUERY}"
echo "TRANS=${TRANS}"
echo "VM=${VM}"
echo "FORCE=${fflag}"
echo "WKDIR=${WKDIR}"
echo "SCRIPT_DIR=${SCRIPT_DIR}"
echo "KEEP_FILES=${KEEP_FILES}"
echo ""
echo ""
########Keep, nice to check
#exit 1	


#create directory structure for the run
#in same code block in case I change my mind later
#changing to data directory here because need to be in there to run mcscan
mkdir -p ${WKDIR}/01_data/01_split && cd ${WKDIR}/01_data
mkdir -p ${WKDIR}/02_aln
mkdir -p ${WKDIR}/03_codeml/01_split


#first, run mcscan python on ref / query
#hmm there is some overhead in beginning a multiprocess
#would be more computationally efficient to send the whole loop through,,, lets do that

#listing orthologs
#Throw list orthologs and mcscan in same step so can skip if have own trans file

#long story short, check if we made the trans file or not
script_trans="false"

if [ -z "$TRANS" ]; then
	script_trans="true"
	#hmmm how to get source activate to work...
	#need python2 environment with this program installed, shit this won't be usable by other people
	#how hard was it for me to get it up and running? o whale

	#set virtual environment name if not set
	VM=${VM:-Python2}
	source activate ${VM}

	#To get ka_ks_pipe version of lastal to work
	export PATH=$PATH:${SCRIPT_DIR}

	#check for outputs first:
	#eh, should check for last too.. naw.. thats okay
	anchors_check=$(ls ${REF}.${QUERY}.lifted.anchors 2> /dev/null | wc -l)
	#check for cds and bed files, needed to run mcscan
	if [ -e ${WKDIR}/01_data/${QUERY}.cds ] || \
	[ -e ${WKDIR}/01_data/${REF}.cds ] || \
	[ -e ${WKDIR}/01_data/${QUERY}.bed ]	|| \
	[ -e ${WKDIR}/01_data/${REF}.bed ]; then\
		#good all files necessary exist
		:
	else
		echo "Not all cds / bed files exist or are in the right directory (wkdir/01_data)"
		echo "Cancelling"
		exit 1
	fi

	if [ ${anchors_check} == "0" ] || [ ${FORCE} == "true" ]; then
		python -m jcvi.compara.catalog ortholog ${REF} ${QUERY}
	else
		echo "${REF}.${QUERY}.lifted.anchors exists, not overwriting. moving on"
	fi

	trans_check=$(ls ${REF}.${QUERY}.trans.txt 2> /dev/null | wc -l)
	if [ ${trans_check} == "0" ] || [ ${FORCE} == "true" ]; then
		${SCRIPT_DIR}/list_orthologs.pl \
		--blast ${WKDIR}/01_data/${REF}.${QUERY}.last \
		--anchor ${WKDIR}/01_data/${REF}.${QUERY}.lifted.anchors \
		-o ${WKDIR}/01_data/${REF}.${QUERY}.trans.txt
	else
		echo "${REF}.${QUERY}.trans.txt exists, not overwriting"
	fi
else
	echo "Using trans file specified: ${TRANS}"
fi

#Set if empty
TRANS=${TRANS:-${REF}.${QUERY}.trans.txt}

#all the file checks
ref_peptide_check=$(ls ${REF}.pep 2> /dev/null | wc -l)
query_peptide_check=$(ls ${QUERY}.pep 2> /dev/null | wc -l)
#make these inside loop since gene specific
#aln_check
#codeml_check=

#If user defined TRANS file, could have comma separated second column,
#just split that into new rows
#will be quickest in perl
#even if nothing gets split, trans_split will be the same file
${SCRIPT_DIR}/split_pairwise_col.pl \
--in ${TRANS} \
--out ${TRANS}_split

################Split translation file, run array job
##### My multitasking method didn't work, o whale
##### Outline:
#####	- split translation file into files with 500 genes per file
#####		- rough estimation 500 gene pairs per hour here
#####	- load list of split files
#####	- run array job where each job is single threaded version each of these
##### Maybe multitasking didn't work because was trying ~26k procs, 
##### might try to multi proc these arrays later, not now though

TRANS_BASE=$(basename ${TRANS})

#Remove outputs if they exist
rm -f ${WKDIR}/01_data/01_split/${TRANS_BASE}_split_*

########debug
#LINES=600
########

split --lines=${LINES} \
--suffix-length=4 \
--additional-suffix=.txt \
--numeric-suffixes=1 \
${TRANS}_split \
${WKDIR}/01_data/01_split/${TRANS_BASE}_split_

#load into file
rm -f ${WKDIR}/01_data/01_split/${TRANS_BASE}_list.txt
ls ${WKDIR}/01_data/01_split/${TRANS_BASE}_split_* > ${WKDIR}/01_data/01_split/${TRANS_BASE}_list.txt

#removed leading zeros
while read split; do
	mv ${split} $(echo ${split} | sed "s/_0*/_/g")
done < ${WKDIR}/01_data/01_split/${TRANS_BASE}_list.txt

#remove leading zeros in file itself
sed -i "s/_0*/_/g" ${WKDIR}/01_data/01_split/${TRANS_BASE}_list.txt

#Batch submit

EXPORT="REF=${REF},"
EXPORT+="QUERY=${QUERY},"
EXPORT+="TRANS=${TRANS},"
EXPORT+="VM=${VM},"
EXPORT+="FORCE=${fflag},"
EXPORT+="WKDIR=${WKDIR},"
EXPORT+="SCRIPT_DIR=${SCRIPT_DIR},"
EXPORT+="ref_peptide_check=${ref_peptide_check},"
EXPORT+="query_peptide_check=${query_peptide_check},"
EXPORT+="INFILE=${WKDIR}/01_data/01_split/${TRANS_BASE}_list.txt,"
EXPORT+="script_trans=${script_trans},"
EXPORT+="KEEP_FILES=${KEEP_FILES}"


###DEBUG SET ARRAY TO 1 instead of 1-${SPLITS}
SPLITS=$(wc -l ${WKDIR}/01_data/01_split/${TRANS_BASE}_list.txt | sed "s/ .*//g")

dependency=$(sbatch --export=${EXPORT} \
	--array=1-${SPLITS} \
	${SCRIPT_DIR}/ka_ks_pipe_array.sbatch)

#Get just jobid
dependency=$(echo "${dependency}" | grep -o "[0-9]*" )

#Final concatenation, dependent upon array jobs finishing
sbatch --dependency=afterany:${dependency} \
	--export=${EXPORT} \
	${SCRIPT_DIR}/ka_ks_final_cat.sbatch

#echo "was going to submit with export:"
#echo ${EXPORT}
#echo "to splits: ${SPLITS}"

########################################################
##### The rest is found in ka_ks_pipe_array.sbatch #####
##### Didn't remove in case I change my mind later #####
########################################################

#loop variable to keep output files
#declare -i i
#nevermind, using regex to stitch together

##while read pair; do
#	###################################
#	#i+=1
#	#multiprocessing
#	#try in a file instead of here:
##	(srun -n1 --exclusive \
##	source ${SCRIPT_DIR}/ka_ks_pipe.sh) &
##	break
#
##	srun -n1 --exclusive \
#	cd ${WKDIR};\
#	echo "changin directories: `pwd`";\
#	###################################;\
#	#split into pairs;\
#	IFS="	" read -r -a pair <<< "$pair";\
#	ref_extract="";\
#	if [ ${script_trans} == "true" ]; then \
#		ref_extract=$(echo ${pair[0]} | sed "s/_[0-9]*$//");\
#	else \
#		ref_extract=${pair[0]};\
#	fi;\
#	#echo "pair 1: ${pair[0]}"
#	#echo "pair 2: ${pair[1]}"
#	#exit 1;
#	EXTENSION="";\
#	if [ ${ref_peptide_check} != "0" ] && [ ${query_peptide_check} != "0" ]; then \
#		#peptide files exist, use those instead of cds;\
#		EXTENSION="pep";\
#	else \
#		#either peptide file does not exist, use cds;\
#		EXTENSION="cds";\
#	fi;\
#	echo "Extension = ${EXTENSION}";\
#	###################################;\
#	echo "Splitting fasta files";\
#	${SCRIPT_DIR}/fasta_pairs.pl \
#	--one ${ref_extract} \
#	--two ${pair[1]} \
#	--first_fasta ${WKDIR}/01_data/${REF}.${EXTENSION} \
#	--second_fasta ${WKDIR}/01_data/${QUERY}.${EXTENSION} \
#	-o ${WKDIR}/01_data/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.${EXTENSION};\
#	###################################;\
#	echo "Alignment";\
#	${SCRIPT_DIR}/muscle3.8.31_i86linux64 \
#	-in ${WKDIR}/01_data/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.${EXTENSION} \
#	-out ${WKDIR}/02_aln/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.${EXTENSION};\
#	###################################;\
#	if [ ${EXTENSION} == "pep" ]; then \
#		echo "executing pal2nal since peps exist";\
#		#split cds;\
#		${SCRIPT_DIR}/fasta_pairs.pl \
#		--one ${pair[0]} \
#		--two ${pair[1]} \
#		--first_fasta ${WKDIR}/01_data/${REF}.cds \
#		--second_fasta ${WKDIR}/01_data/${QUERY}.cds \
#		-o ${WKDIR}/01_data/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.cds;\
#		#pal2nal;\
#		rm -f ${WKDIR}/02_aln/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.cds;\
#		${SCRIPT_DIR}/pal2nal.pl \
#		${WKDIR}/02_aln/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.${EXTENSION} \
#		${WKDIR}/01_data/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.cds \
#		-output paml \
#		> ${WKDIR}/02_aln/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.cds;\
#	fi;\
#	###################################;\
#	echo "Running codeml";\
#	rm -f ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.codeml.ctl;\
#	CODEML_CTL_TAG=$(echo -e "\tseqfile = ${WKDIR}/02_aln/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.cds\n\
#	outfile = ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.ka.ks.txt");\
#	echo "${CODEML_CTL_TAG}" | \
#	cat - ${SCRIPT_DIR}/codeml.ctl.static \
#	> ${WKDIR}/${REF}.${QUERY}.tmp.ctl;\
##	> ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.codeml.ctl;\
##	${SCRIPT_DIR}/codeml ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.codeml.ctl;\
#	${SCRIPT_DIR}/codeml ${WKDIR}/${REF}.${QUERY}.tmp.ctl;\
#	rm -f ${WKDIR}/${REF}.${QUERY}.tmp.ctl;\
##	Collect information in the format we want it to be in
#	dN=$(grep "^t=" ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.ka.ks.txt | \
#	cut -f6 -d"=" | sed -e "s/[[:space:]]\+//g" | sed "s/[a-zA-Z]//g");\
#	dS=$(grep "^t="	${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.ka.ks.txt | \
#	cut -f7	-d"=" |	sed "s/[[:space:]]\+//g" | sed "s/[a-zA-Z]//g");\
#	dNdS=$(grep "^t=" ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.ka.ks.txt | \
#	cut -f5	-d"=" |	sed "s/[[:space:]]\+//g" | sed "s/[a-zA-Z]//g");\
#	echo "dN: ${dN}";\
#	echo "dS: ${dS}";\
#	echo "ratio: ${dNdS}";\
#	echo -e "${REF}\t${QUERY}\t${dN}\t${dS}\t${dNdS}\t${pair[0]}\t${pair[1]}" | \
#	cat - > ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}.ka.ks.meta.txt;\
#	echo "Finished"
#
##	echo "Finished") &
##	if [ ${i} == "2" ]; then
##		break 2
##	fi
#done < ${TRANS}_split
#wait

##paste it together
##just to be sure
#cd ${WKDIR}
#rm -f ${WKDIR}/03_codeml/${REF}.${QUERY}.ka.ks.txt
#echo -e "Reference_Species\tQuery_Species\tdN\tdS\tdNdS\tReference_Gene\tQuery_gene" | \
#cat - ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.*meta.txt > ${WKDIR}/03_codeml/${REF}.${QUERY}.ka.ks.txt

##echo line gets the header in there, then we add the contents of every file
