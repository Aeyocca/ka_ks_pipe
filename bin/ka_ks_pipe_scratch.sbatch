#!/bin/bash
#ka_ks_pipe_scratch
#12-05-18
#Alan E. Yocca

#SBATCH --job-name=ka_ks_pipe_scratch
#SBATCH --mem=1Gb
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=/mnt/research/edgerpat_lab/AlanY/Error_files/%x-%j.SLURMout
#SBATCH --export="INFILE=/mnt/gs18/scratch/users/yoccaala/05_ka_ks/tmp_ka_ks_dir_list.txt"
#SBATCH --array=1-33


#hello there

#loop through all directories, should be 30 of them? eh maybe 33?

LINE=`/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${INFILE}`

cd ${LINE}

base=$(basename ${LINE})

#echo "trying to submit:"
#echo ""
/mnt/research/edgerpat_lab/AlanY/01_athal_cns/slurm/ka_ks_pipe/bin/ka_ks_launch.sh \
--ref TAIR10_cds \
--query ${base}_maker \
--trans ${LINE}/01_data/${base}_maker.TAIR10_cds.trans.txt \
--wkdir ${LINE} \
--flip \
--scratch_array ${SLURM_ARRAY_TASK_ID} \
--script_dir /mnt/research/edgerpat_lab/AlanY/01_athal_cns/slurm/ka_ks_pipe/bin

touch ${WKDIR}/03_codeml/01_split/${REF}.${QUERY}.complete.${SLURM_ARRAY_TASK_ID}.txt
