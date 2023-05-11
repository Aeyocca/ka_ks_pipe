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
echo "RESUME=${RESUME}"
echo "LINES=${LINES}"
echo "SCRATCH_ARRAY=${SCRATCH_ARRAY}"
echo "EO_DIR=${EO_DIR}"
echo "SELF_COMP=${SELF_COMP}"
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

if [ -z "$TRANS" ] && [ -e ${WKDIR}/01_data/${QUERY}.${REF}.trans.txt ]; then
	echo "Trans not provided, trans exists based on regex: \$WKDIR/01_data/\$QUERY.\$REF.trans.txt"; echo ""
	echo "${WKDIR}/01_data/${QUERY}.${REF}.trans.txt"
	echo "NOT recreating. If you want to recreate trans file, delete the one listed above"; echo ""
	TRANS="${WKDIR}/01_data/${QUERY}.${REF}.trans.txt"

	#flip trans??
	if [ ${FLIP} == "true" ]; then
		#This is probably dangerous.... oh whale
		echo "Flipping translation file"
		rm -f ${TRANS}_flip.txt
		awk -v OFS="	" -F"\t" '{print $2,$1}' ${TRANS} > ${TRANS}_flip.txt
		TRANS="${TRANS}_flip.txt"
        fi

elif [ -z "$TRANS" ]; then
	script_trans="true"
	#hmmm how to get source activate to work...
	#need python2 environment with this program installed, shit this won't be usable by other people
	#how hard was it for me to get it up and running? o whale

	BASH_PATH=$PATH

	#set virtual environment name if not set
	VM=${VM:-Python2}
	source /mnt/home/yoccaala/miniconda3/bin/activate Python2

	echo "new env, python version:"
	python --version

	echo "Old path: ${PATH}"
	#To get ka_ks_pipe version of lastal to work
	export PATH=${PATH}:${BASH_PATH}:${SCRIPT_DIR}

	echo "New path:"; echo "${PATH}"
	

	#check for outputs first:
	#eh, should check for last too.. naw.. thats okay
	anchors_check=$(ls -U ${REF}.${QUERY}.lifted.anchors 2> /dev/null | wc -l)
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

	trans_check=$(ls -U ${REF}.${QUERY}.trans.txt 2> /dev/null | wc -l)
	if [ ${trans_check} == "0" ] || [ ${FORCE} == "true" ]; then
		${SCRIPT_DIR}/list_orthologs.pl \
		--blast ${WKDIR}/01_data/${REF}.${QUERY}.last \
		--anchor ${WKDIR}/01_data/${REF}.${QUERY}.lifted.anchors \
		--force \
		--no_tag \
		--self_comp ${SELF_COMP} \
		-o ${WKDIR}/01_data/${REF}.${QUERY}.trans.txt
	else
		echo "${REF}.${QUERY}.trans.txt exists, not overwriting"
	fi
else
	echo "Using trans file specified: ${TRANS}"
fi

#Set if empty
TRANS=${TRANS:-${REF}.${QUERY}.trans.txt}
#dos2unix
dos2unix ${TRANS}

#all the file checks
ref_peptide_check=$(ls -U ${REF}.pep 2> /dev/null | wc -l)
query_peptide_check=$(ls -U ${QUERY}.pep 2> /dev/null | wc -l)
ref_cds_check=$(ls -U ${WKDIR}/01_data/${REF}.cds 2> /dev/null | wc -l)
query_cds_check=$(ls -U ${WKDIR}/01_data/${QUERY}.cds 2> /dev/null | wc -l)
if [ ${ref_cds_check} != "1" ]; then
	echo ""; echo "Other than a single ref cds file found where it should be:"
	echo "${WKDIR}/01_data/"
	echo "Checking wkdir for it"
	ref_wkdir_check=$(ls ${WKDIR}/${REF}.cds 2> /dev/null | wc -l)
	if [ ${ref_wkdir_check} == "1" ]; then
		echo ""; echo "Okay I found it there, symlinking"
		ln -s ${WKDIR}/${REF}.cds ${WKDIR}/01_data/${REF}.cds
	fi
fi

if [ ${query_cds_check} != "1" ];	then
	echo ""; echo "Other than a single query cds file found where it should be:"
	echo "${WKDIR}/01_data/"
	echo "Checking wkdir for it"
	query_wkdir_check=$(ls -U ${WKDIR}/${QUERY}.cds 2> /dev/null | wc -l)
	if [ ${query_wkdir_check} == "1" ]; then
		echo ""; echo "Okay I found it there, symlinking"
		ln -s ${WKDIR}/${QUERY}.cds ${WKDIR}/01_data/${QUERY}.cds
	fi
fi




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

#if resume, check for splits
split_check="true"
if [[ ${RESUME} == "true" ]]; then
	echo "Still under development 12-14-18"
	#split check
	#just check for max split?
	trans_split_length=$(wc -l ${TRANS}_split 2> /dev/null | sed "s/ .*//")
	echo "tsplitlength: ${trans_split_length}"
	max_splits=$(((${trans_split_length}+(${LINES}-1))/(${LINES})))
	echo "max splits: ${max_splits}"
	max_check=$(ls -U ${WKDIR}/01_data/01_split/${TRANS_BASE}_split_${max_splits}.txt 2> /dev/null | wc -l)
	echo "max_check: ${max_check}"
	split_list_check=$(ls -U ${WKDIR}/01_data/01_split/${TRANS_BASE}_list.txt 2> /dev/null | wc -l)
	if [ ${max_check} != "1" ] || [ ${split_list_check} != "1" ]; then
		echo "max split other than single file, remaking splits"
		echo "or split list doesn't exist"
		echo "WARNING!!!!!!!!!!!!!!"
		echo "Should have found just one of max split, keep a close eye out, things might not work"
	else
		echo "single max split and split list found, not remaking splits"
		split_check="false"
	fi
fi

if [ ${split_check} ]; then
	echo "making split files"

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
fi

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
EXPORT+="SCRATCH_ARRAY=${SCRATCH_ARRAY},"
EXPORT+="KEEP_FILES=${KEEP_FILES},"
EXPORT+="EO_DIR=${EO_DIR},"
EXPORT+="RESUME=${RESUME}"


###DEBUG SET ARRAY TO 1 instead of 1-${SPLITS}
SPLITS=$(wc -l ${WKDIR}/01_data/01_split/${TRANS_BASE}_list.txt | sed "s/ .*//g")

ARRAYS=""
for i in $(seq 1 ${SPLITS}); do
	#dot separate since commas delimit variable designation in slurm
	ARRAYS+="$i."
	echo "adding to arrays: $i"
done
ARRAYS=$(sed "s/.$//" <<< ${ARRAYS})
EXPORT="ARRAYS=${ARRAYS},${EXPORT}"

#echo "arrays: $ARRAYS"
#echo "splits: $SPLITS"
#echo "export: ${EXPORT}"

dependency=$(sbatch --export=${EXPORT} \
	--output=${EO_DIR}/%x-%A_%a.SLURMout \
	--array=1-${SPLITS} \
	${SCRIPT_DIR}/ka_ks_pipe_array.sbatch)

echo "Array jobID: ${dependency}"

#Get just jobid
dependency=$(echo "${dependency}" | grep -o "[0-9]*" )

#Final concatenation, dependent upon array jobs finishing
sbatch --dependency=afterany:${dependency} \
	--output=${EO_DIR}/%x-%j.SLURMout \
	--export=${EXPORT} \
	${SCRIPT_DIR}/ka_ks_final_cat.sbatch

#echo "DEBUG END OF SCRIPT"

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
