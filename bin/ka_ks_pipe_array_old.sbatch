#!/bin/sh -login
#ka_ks_pipe.sbatch
#11-12-18
#Alan E. Yocca
#11-28-18
#gene pair processing

#SBATCH --job-name=ka_ks_pipe_array
#SBATCH --mem=15Gb
#SBATCH --ntasks=1
#SBATCH --time=02:00:00
#SBATCH --output=/mnt/research/edgerpat_lab/AlanY/Error_files/%x-%A_%a.SLURMout

SPLIT_FILE=`/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${INFILE}`

echo "Starting on split file: ${SPLIT_FILE}"
SPLIT_FILE_BASE=$(basename ${SPLIT_FILE})

cd ${WKDIR}
echo "changin directories: `pwd`"

#for resume check, kill if ka.ks.meta doesn't exist
#if it doesn't exist, either hasn't gotten to this step yet or mispecified some
#cmd line parameters
ka_ks_check=$(ls ${WKDIR}/03_codeml/01_split/${SPLIT_FILE_BASE}.ka.ks.meta.txt 2> /dev/null | wc -l)
if [ ! -z ${RESUME} ] && [ ${ka_ks_check} != "1" ]; then
	echo "Found other than 1 ka.ks.meta,txt file for:"
	echo "${WKDIR}/03_codeml/01_split/${SPLIT_FILE_BASE}.ka.ks.meta.txt"
	echo "killing this array job"
	echo "It is likely you misspecified cmd line flags (doesn't match earlier run)"
	echo "Or possible just hadn't made it yet, if this is the case:"
	echo "	- Create empty file with this name, then rerun with --resume"
	echo "		(eg: \$ touch ${WKDIR}/03_codeml/01_split/${SPLIT_FILE_BASE}.ka.ks.meta.txt )"
	echo "	- just restart the whole thing"
fi


#comment out below, eh nevermind
while read pair; do
	#check for resume / if this has finished already
	if [ ! -z ${RESUME} ]; then
		#check
		output_check=$(grep "${REF}\t${QUERY}\t${dN}\t${dS}\t${dNdS}\t${pair[0]}\t${pair[1]}" \
			${WKDIR}/03_codeml/01_split/${SPLIT_FILE_BASE}.ka.ks.meta.txt 2> /dev/null | wc -l)
		if [ $output_check} == "0" ]; then
			#Output for this exists, next gene pair
			continue 2
		fi
		#otherwise, will keep on this loop iteration
		#and calculate ka/ks from scratch
	fi

	###################################;\
	#split into pairs;\
	IFS="	" read -r -a pair <<< "$pair"
	ref_extract=""
	if [ ${script_trans} == "true" ]; then
	ref_extract=$(echo ${pair[0]} | sed "s/_[0-9]*$//")
	else 
		ref_extract=${pair[0]}
	fi
	#echo "pair 1: ${pair[0]}"
	#echo "pair 2: ${pair[1]}"
	#exit 1
	EXTENSION=""
	if [ ${ref_peptide_check} != "0" ] && [ ${query_peptide_check} != "0" ]; then
		#peptide files exist, use those instead of cds
		EXTENSION="pep"
	else
		#either peptide file does not exist, use cds
		EXTENSION="cds"
	fi
	echo "Extension = ${EXTENSION}"

	#Ref-query pair	directory:
	RQpdir="${REF}.${QUERY}.${pair[0]}.${pair[1]}"
	mkdir ${WKDIR}/01_data/01_split/${RQpdir}/
	mkdir ${WKDIR}/02_aln/${RQpdir}/
#	This one is done later:
#	mkdir ${WKDIR}/03_codeml/01_split/${RQpdir}/
	
	###################################;
	echo "Splitting fasta files"
	${SCRIPT_DIR}/fasta_pairs.pl \
	--one ${ref_extract} \
	--two ${pair[1]} \
	--first_fasta ${WKDIR}/01_data/${REF}.${EXTENSION} \
	--second_fasta ${WKDIR}/01_data/${QUERY}.${EXTENSION} \
	-o ${WKDIR}/01_data/01_split/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.${EXTENSION}

	#checking if that worked
	extract_count=$(grep -c ">" ${WKDIR}/01_data/01_split/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.${EXTENSION})
	if [ ${extract_count} != "2" ]; then
		echo "Other than 2 genes extracted, Not running this gene pair:"
		echo "Ref gene: ${pair[0]}"
		echo "Query gene: ${pair[1]}"
		echo "Output file: ${WKDIR}/01_data/01_split/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.${EXTENSION}"
		echo "Failed"
		continue 1
	fi	
	###################################
	echo "Alignment"
	date
	${SCRIPT_DIR}/muscle3.8.31_i86linux64 \
	-in ${WKDIR}/01_data/01_split/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.${EXTENSION} \
	-out ${WKDIR}/02_aln/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.${EXTENSION}
	
	###################################;\
	if [ ${EXTENSION} == "pep" ]; then
		echo "executing pal2nal since peps exist"
		#split cds
		${SCRIPT_DIR}/fasta_pairs.pl \
		--one ${pair[0]} \
		--two ${pair[1]} \
		--first_fasta ${WKDIR}/01_data/${REF}.cds \
		--second_fasta ${WKDIR}/01_data/${QUERY}.cds \
		-o ${WKDIR}/01_data/01_split/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.cds
	
	#pal2nal
		rm -f ${WKDIR}/02_aln/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.cds
		${SCRIPT_DIR}/pal2nal.pl \
		${WKDIR}/02_aln/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.${EXTENSION} \
		${WKDIR}/01_data/01_split/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.cds \
		-output paml \
		> ${WKDIR}/02_aln/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.cds
	fi
	date

	###################################
	#Codeml, what a pain.. max ctl file length 95 characters
	###################################
	#Also, creates files in output directory 
	#for intermediate processes, 
	#but don't have unique names
	#So give each output a unique output directory
	CTL_FILE="${REF}.${QUERY}.${pair[0]}.${pair[1]}.codeml.ctl"
	rm -rf ${WKDIR}/03_codeml/01_split/${RQpdir}/
	mkdir ${WKDIR}/03_codeml/01_split/${RQpdir}/
	cd ${WKDIR}/03_codeml/01_split/${RQpdir}/
	if [ ${#CTL_FILE} -gt 95 ]; then
		#Too long, new tmp name based on date
		#keep actual name of directory though
		tmp_date=$(date | sed "s/ /_/g")
		CTL_FILE="${tmp_date}.codeml.ctl"
	fi
	rm -f ${WKDIR}/03_codeml/01_split/${RQpdir}//${CTL_FILE}

	###################################
	echo "Adding files"
	date
	#Hot diggidy damn, even the seq/output file have character limits (160 is my best guess, set limit at 155)
	#Should be in 03_codeml/01_split/ref_query directory
	outfile="${REF}.${QUERY}.${pair[0]}.${pair[1]}.ka.ks.txt"
	seqfile="../../../02_aln/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.cds"
	if [ ${#outfile} -gt 155 ]; then
		echo ""; echo "outfile longer than 155 characters, "
		echo "Now making temporary file"
		tmp_date=$(date | sed "s/ /_/g")
		outfile="${tmp_date}.ka.ks.txt"
		echo "New outfile: ${outfile}"; echo ""
	fi	
	if [ ${#seqfile} -gt 155 ]; then
		echo ""; echo "seqfile longer than 155 characters, "
		echo "Now making temporary file"; echo ""
		tmp_date=$(date | sed "s/ /_/g")
		tmp_seqfile="./${tmp_date}.aln.cds"
		mv ${seqfile} ${tmp_seqfile}
		seqfile="${tmp_seqfile}"
		echo "New seqfile: ${seqfile}"; pwd; echo ""
	fi
	CODEML_CTL_TAG=$(echo -e "\tseqfile = ${seqfile}\n\
	outfile = ${outfile}")
	echo "${CODEML_CTL_TAG}" | \
	cat - ${SCRIPT_DIR}/codeml.ctl.static \
	> ${WKDIR}/03_codeml/01_split/${RQpdir}/${CTL_FILE}
	###################################
	echo "Running codeml"
	date
	#This is the obnoxious part, 
	#can't give full path, moved into this dir so hopfully works
	${SCRIPT_DIR}/codeml ${CTL_FILE}
##	Collect information in the format we want it to be in
	dN=$(grep "^t=" ${outfile} | \
	cut -f6 -d"=" | sed -e "s/[[:space:]]\+//g" | sed "s/[a-zA-Z]//g")
	dS=$(grep "^t=" ${outfile} | \
	cut -f7 -d"=" | sed "s/[[:space:]]\+//g" | sed "s/[a-zA-Z]//g")
	dNdS=$(grep "^t=" ${outfile} | \
	cut -f5 -d"=" | sed "s/[[:space:]]\+//g" | sed "s/[a-zA-Z]//g")
	echo "dN: ${dN}"
	echo "dS: ${dS}"
	echo "ratio: ${dNdS}"
#	echo -e "${REF}\t${QUERY}\t${dN}\t${dS}\t${dNdS}\t${pair[0]}\t${pair[1]}" | \
#	cat - > ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.${pair[0]}.${pair[1]}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.ka.ks.meta.txt
	#concatenating everything at the end is a bit of a pain
	#so do here so takes less time later
	echo -e "${REF}\t${QUERY}\t${dN}\t${dS}\t${dNdS}\t${pair[0]}\t${pair[1]}" | \
	cat - >> ${WKDIR}/03_codeml/01_split/${SPLIT_FILE_BASE}.ka.ks.meta.txt
	echo "Finished pair:	${pair[0]}	${pair[1]}"
	date
	##remove as you go
	if ${KEEP_FILES}
	then
		#keeping, should be set to "true" if launch script worked correctly
		:
	else
		#Take out cds/pep split, pep alignment, codeml ctl file, and codeml output
		echo "Keep files not specified, removing things"
		date
		rm -f ${WKDIR}/01_data/01_split/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.cds
		rm -f ${WKDIR}/01_data/01_split/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.split.${EXTENSION}
		rm -f ${WKDIR}/02_aln/${RQpdir}/${REF}.${QUERY}.${pair[0]}.${pair[1]}.aln.${EXTENSION}
		rm -f ${seqfile}
		rm -f ${WKDIR}/03_codeml/01_split/${RQpdir}//${CTL_FILE}
		rm -f ${outfile}
		echo "finished removing things"
		date
	fi
#	echo "BREAKING FOR DEBUGGING"
#	break
done < ${SPLIT_FILE}






