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

#Add perl module to path:
export PERL5LIB=${SCRIPT_DIR}

SPLIT_FILE=`/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${INFILE}`

echo "Starting on split file: ${SPLIT_FILE}"
SPLIT_FILE_BASE=$(basename ${SPLIT_FILE})

cd ${WKDIR}
echo "changin directories: `pwd`"

#for resume check, kill if ka.ks.meta doesn't exist
#if it doesn't exist, either hasn't gotten to this step yet or mispecified some
#cmd line parameters
ka_ks_check=$(ls ${WKDIR}/03_codeml/01_split/${SPLIT_FILE_BASE}.ka.ks.meta.txt 2> /dev/null | wc -l | sed "s/ .*//")
#if [ ${RESUME} == "true" ] && [ ${ka_ks_check} != "1" ]; then
#	echo "Found other than 1 ka.ks.meta,txt file for:"
#	echo "${WKDIR}/03_codeml/01_split/${SPLIT_FILE_BASE}.ka.ks.meta.txt"
#	echo "killing this array job"
#	echo "It is likely you misspecified cmd line flags (doesn't match earlier run)"
#	echo "Or possible just hadn't made it yet, if this is the case:"
#	echo "	- Create empty file with this name, then rerun with --resume"
#	echo "		(eg: \$ touch ${WKDIR}/03_codeml/01_split/${SPLIT_FILE_BASE}.ka.ks.meta.txt )"
#	echo "	- just restart the whole thing"
#fi

#made a perl script to do it all, just need to feed it the right things and hopefully will run much faster than bash

echo "resume set to: ${RESUME}"

#echo "creating own copy of ka_ks_pipe_array.pl because hpcc file system sucks"
#maybe its because I am not using some fancy software, maybe im reinventing the wheel here..
#need to make this version array specific
#hmmm wont copying the same file that many times be just as bad as executing?
#maybe I can make a "failed" signal and just not output so keeps retrying, that sounds better

${SCRIPT_DIR}/ka_ks_pipe_array.pl --query ${QUERY} \
--ref ${REF} \
--wkdir ${WKDIR} \
--ref_peptide_check ${ref_peptide_check} \
--query_peptide_check ${query_peptide_check} \
--script_dir ${SCRIPT_DIR} \
--split_file ${SPLIT_FILE} \
--keep_files ${KEEP_FILES} \
--resume ${RESUME}

if [ $? -ne "0" ]; then
	echo "ka_ks_pipe_array.pl returned non-zero exit status, not creating finished output file"
	exit 1
	#should make it not finish running array
fi

#wait

#If we get to this line, everything finished fine:
echo "Finished running array: ${SLURM_ARRAY_TASK_ID}"
touch ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.complete.${SLURM_ARRAY_TASK_ID}.txt
