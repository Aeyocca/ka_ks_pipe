#!/bin/sh -login
#12-03-18
#final_cat.sbatch
#Alan E. Yocca

#SBATCH --job-name=final_cat.sbatch
#SBATCH --mem=15Gb
#SBATCH --ntasks=1
#SBATCH --time=04:00:00
#SBATCH --output=/mnt/research/edgerpat_lab/AlanY/Error_files/%x-%j.SLURMout

echo "Final concatenation started"; date

#defined variable for array resubmission if needed, ugh this is getting ugly
failed_arrays=""

echo "Checking for final output"; date
if [ ! -e ${WKDIR}/03_codeml/${REF}.${QUERY}.ka.ks.txt ]; then
	echo "Final output does not exists, creating"
	echo -e "Reference_Species\tQuery_Species\tdN\tdS\tdNdS\tReference_Gene\tQuery_gene" > ${WKDIR}/03_codeml/${REF}.${QUERY}.ka.ks.txt
fi
echo "Finished final output check"; date

#meta_check=$(ls -U ${WKDIR}/03_codeml/01_split/*meta.txt 2> /dev/null | wc -l )
#dont want to use ls, too slow since so many files in that directory
meta_check="false"
for f in ${WKDIR}/03_codeml/01_split/*meta.txt; do
	if [ -e "$f" ]; then
		meta_check="true"
	fi
	break
done

if [[ ${meta_check} == "false" ]]; then
	echo "Meta files not found, "
	echo "Check array outputs for error messages"
else
	#load arrays into array
	echo "loading arrays"; date
	IFS='.' read -ra array_jobs <<< "${ARRAYS}"
	echo "loading into array: ${ARRAYS}"
	echo "populated array:"
	printf '%s\n' "${array_jobs[@]}"
	for aid in "${array_jobs[@]}"; do
		echo "Starting on $aid"; date
		#check for final
		if [ -e ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.complete.${aid}.txt ]; then
			#add to final output
			echo "array: $aid complete, adding to final output"
			cat ${WKDIR}/03_codeml/01_split/*split_${aid}.txt.ka.ks.meta.txt >> ${WKDIR}/03_codeml/${REF}.${QUERY}.ka.ks.txt
                        #remove this meta file so don't add again later
                        if [[ ${KEEP_FILES} == "true" ]]; then
                                #keep files
                                :
                        else
                            	rm -f ${WKDIR}/03_codeml/01_split/*split_${aid}.txt.ka.ks.meta.txt
                        fi
		else
			#add to failed array list
			failed_arrays+="${aid}."
		fi
	done
fi


#	for meta_file in ${WKDIR}/03_codeml/01_split/*meta.txt; do
#		#check for alignment with split file
#		echo "Checking meta file: ${meta_file}"
#		meta_length=$(wc -l ${meta_file} | sed "s/ .*//")
#		SPLIT_FILE_BASE=$(basename ${meta_file} | sed "s/\.ka\.ks\.meta\.txt//")
#		split_file="${WKDIR}/01_data/01_split/${SPLIT_FILE_BASE}"
#		split_length=$(wc -l ${split_file} | sed "s/ .*//")
#		if [ ${meta_length} == ${split_length} ]; then
#			#good
#			cat ${meta_file} >> ${WKDIR}/03_codeml/${REF}.${QUERY}.ka.ks.txt
#			#remove this meta file so don't add again later
#			if [[ ${KEEP_FILES} == "true" ]]; then
#				#keep files
#				:
#			else
#				rm -f ${meta_file}
#			fi
#		else
#			#resume
#			#uhh instead of submitting a bunch of different jobs, just collect the arrays that need rerun and batch set them off in a little
#			loop_failed_array=$(echo ${meta_file} | sed "s/.*split_//" | sed "s/\.txt\.ka\.ks\.meta\.txt//")
#			echo "meta file: ${meta_file}"
#			echo "Did not finish, resubmitting"
#			failed_arrays+="${loop_failed_array}.";
#		fi
#	done
#fi


#relaunch shit if it failed
if [ ! -z ${failed_arrays} ]; then
	#remove trailing comma
	failed_arrays=$(sed "s/.$//" <<< ${failed_arrays})
	#sub with periods for loading into export

	#create export list in case need to resubmit things:
	TRANS_BASE=$(basename ${TRANS})
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
	EXPORT+="ARRAYS=${failed_arrays},"

	#setting to true even if already set to true
	EXPORT+="RESUME=true"

	#change to commas for array specification
	failed_arrays=$(sed "s/\./,/g" <<< ${failed_arrays})

	dependency=$(sbatch --export=${EXPORT} \
		--output=${EO_DIR}/%x-%A_%a.SLURMout \
		--array=${failed_arrays} \
		${SCRIPT_DIR}/ka_ks_pipe_array.sbatch)

	echo "Resubmitted arrays: ${failed_arrays}"
	echo "${dependency}"

	dependency=$(echo "${dependency}" | grep -o "[0-9]*" )

	sbatch --dependency=afterany:${dependency} \
	        --output=${EO_DIR}/%x-%j.SLURMout \
	        --export=${EXPORT} \
	        ${SCRIPT_DIR}/ka_ks_final_cat.sbatch
else
	echo "Final concatenation finished"
	date
	#####
	echo "scratch array: $SCRATCH_ARRAY"

	if [ "$SCRATCH_ARRAY" -ge 0 ] 2> /dev/null; then
		#looping through an rq list, hardcoding
		((SCRATCH_ARRAY++))
		if [ ${SCRATCH_ARRAY} -le 33 ]; then
			pairs=`/bin/sed -n ${SCRATCH_ARRAY}p /mnt/gs18/scratch/users/yoccaala/05_ka_ks/rq_list_ks_pipe_33_eco.txt`
	
			IFS="	" read -ra rq_split <<< "$pairs"
			query="${rq_split[1]}"
	
			/mnt/research/edgerpat_lab/AlanY/01_athal_cns/slurm/ka_ks_pipe/bin/ka_ks_launch.sh \
			--ref TAIR10_cds \
			--query ${query}\
			--trans /mnt/gs18/scratch/users/yoccaala/05_ka_ks/${query}/01_data/${query}.TAIR10_cds.trans.txt \
			--flip \
			--wkdir /mnt/gs18/scratch/users/yoccaala/05_ka_ks/${query} \
			--lines 600 \
			--script_dir /mnt/research/edgerpat_lab/AlanY/01_athal_cns/slurm/ka_ks_pipe/bin/ \
			--scratch_array ${SCRATCH_ARRAY}
	
	#		#sbatch --array=${SCRATCH_ARRAY} ${SCRIPT_DIR}/ka_ks_pipe_scratch.sbatch

			#Another keep files check, should still need to remove the gene pair dir in 
			#03_codeml/01_split/ folder.... would be nice to do this in the arrays... ahhhh doing it there instead
			#hmm do in perl script??? need to think whether might duplicate final gene pair...

		else
			#out of bounds
			:
		fi
	fi
fi
