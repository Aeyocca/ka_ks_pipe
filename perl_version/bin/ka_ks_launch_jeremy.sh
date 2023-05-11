#!/bin/sh
#Alan E Yocca
#11-12-18
#ka_ks_launch
#start ka_ks calling pipeline

set -e

print_usage() {
        echo "Usage:"
        echo "$0"
        echo "  --ref:"
        echo "          <basename of reference. REQ if --rq_list not specified>"
	echo "			<eg if reference cds file is TAIR10.cds, --ref TAIR10>"
	echo "  --query:"
	echo "		<basename of query. REQ if --rq_list not specified>"
        echo "  --rq_list:"
	echo "		<file with reference and query pairs tab separated, one pair per line>"
	echo "			<full path please>"
	echo "			<for running this pipeline many times of different ref/query pairs>"
	echo "	--trans:"
	echo "		<Specify your own translation file if you don't want me to make it for you>"
	echo "			<First column single reference gene, tab separated second column can be comma separated list of orthologs in query>"
	echo "			<its ok, my feelings are only hurt a little bit>"
	echo "	--flip:"
	echo "		<Flip trans columns if your translation file is in query tab ref form>"
	echo "	--vm:"
	echo "		<Specify name of virtual environment name on hpcc that has working version of jcvi mcscanx>"
	echo "			<mine is called Python2, so defaults to that because Im special>"
        echo "  --wkdir:"
        echo "          <full path of the working directory>"
	echo "  --force:"
	echo "		<overwrite all files. if not specified, using files that exist>"
	echo "	--lines:"
	echo "		<how many gene pairs to split up this pipeline by>"
	echo "		<estimated rate for arabidopsis ~600 gene pairs per hour [default]>"
	echo "		<therefore, running this pipe on 26k A. thaliana will submit ~44 separate arrays in the same job,>"
	echo "		<each of which runs on 500 genes and completes in ~1 hour>"
	echo "  --keep_files:"
	echo "		<will hold onto all intermediate files, otherwise, get just codeml output>"
	echo "	--script_dir:"
	echo "		<directory of submission scripts if different than directory this script is in>"        
	echo "			<remember, no trailing forward slash>"
	echo "  --eo_path:"
	echo "		<full path of error/output files>"
	echo "			<EO OF SCRIPTS, NOT FINAL RESULTS!>"
	echo "			<mostly for debugging, default: \$WKDIR/04_error_output/"
}

# goddamn this is annoying to have to put at the beginning, o whale
# credit to stack overflow mcoolive
# Transform long options to short ones
for arg in "$@"; do
  shift
  case "$arg" in
    "--ref") set -- "$@" "-r" ;;
    "--query") set -- "$@" "-q" ;;
    "--rq_list") set -- "$@" "-l" ;;
    "--trans") set -- "$@" "-t" ;;
    "--flip") set -- "$@" "-p" ;;
    "--vm") set -- "$@" "-v" ;;
    "--wkdir") set -- "$@" "-w" ;;
    "--force") set -- "$@" "-f" ;;
    "--lines") set -- "$@" "-n" ;;
    "--keep_files") set -- "$@" "-k" ;;
    "--script_dir") set -- "$@" "-s" ;;
    "--eo_path") set -- "$@" "-e" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Default behavior
rflag=false
qflag=false	#only mandatory if --step pbj specified
lflag=false
wflag=false
fflag=false
kflag=false
sflag=false
tflag=false
vflag=false
pflag=false
nflag=false
eflag=false

# Parse short options
OPTIND=1
while getopts ":r:e:n:v:q:l:t:w:pfks:" opt
do
  case "$opt" in
    "r") REF=$OPTARG; rflag=true ;;
    "q") QUERY=$OPTARG; qflag=true ;;
    "l") RQ_LIST=$OPTARG; lflag=true ;;
    "v") VM=$OPTARG; vflag = true ;;
    "w") WKDIR=$OPTARG; wflag=true ;;
    "f") FORCE=$OPTARG; fflag=true ;;
    "n") LINES=$OPTARG; nflag=true ;;
    "k") KEEP_FILES=$OPTARG; kflag=true ;;
    "s") SCRIPT_DIR=$OPTARG; sflag=true ;;
    "t") TRANS=${OPTARG}; tflag=true ;;
    "p") FLIP=${OPTARG}; pflag=true ;;
    "e") EO_DIR=${OPTARG}; eflag=true ;;
  esac
done
shift $(expr $OPTIND - 1) # remove options from positional parameter

#check for some mandatory options:
if ! ${lflag} && ( ! ${rflag} || ! ${qflag} )
then
	print_usage
	echo "MISSING SOME MANDATORY ARGUMENTS!!"
	exit 1
elif ${lflag} && ( ${rflag} || ${qflag} )
then
	print_usage
	echo "DEFINE EITHER --rq_list OR --ref --query, NOT BOTH"
	exit 1
fi

#check for working directory
if ! ${wflag}
then
	echo "Working directory not defined, using the one this was launched from:"
	echo `pwd`
	WKDIR=$(pwd)
#	print_usage
#	echo "MISSING SOME MANDATORY ARGUMENTS!!"
#	exit 1
fi

#check for script directory
if ! ${sflag}
then
	SCRIPT_DIR=$(dirname $0)
	if [[ ${SCRIPT_DIR} =~ ^/ ]]; then
		#good
		:
	else
		echo "Script dir not defined, and this was lauched from a relative path"
		echo "Define script dir (FULL PATH) or launch this using FULL PATH please"
		exit 1
	fi
fi

#resource spec if need to make translation file
MEM="88Gb"
TASKS="41"
TIME="04:00:00"

if ${tflag}
then
	#change resource request
	MEM="8Gb"
	TASKS="2"
	TIME="00:30:00"
	#flip translation file??
	if ${pflag}
	then
		#This is probably dangerous.... oh whale
		rm -f ${TRANS}_flip.txt
		awk -v OFS="	" -F"\t" '{print $2,$1}' ${TRANS} > ${TRANS}_flip.txt
		TRANS="${TRANS}_flip.txt"
	fi
fi

#line number
if ! ${nflag}
then
	LINES=500
fi

#keep files?
if ${kflag}
then
	KEEP_FILES="true"
else
	KEEP_FILES="false"
fi

if ! ${eflag}
then
	#use default
	EO_DIR=${WKDIR}/04_error_output
fi
mkdir -p ${EO_DIR}


#load rq_list into hash if specified
if ${lflag}; then
	declare -A ref_to_query=(); while read i; do tmp_array=($(echo ${i} | tr '	' '\n')); ref_to_query["${tmp_array[0]}"]="${tmp_array[1]}"; done < ${RQ_LIST}
	#count rq_list submissions
	RQ_COUNT=0
	#loop through hash, submit each line
	for reference in "${!ref_to_query[@]}"; do

		EXPORT="REF=${reference},"
		EXPORT+="QUERY=${ref_to_query[$reference]},"
		EXPORT+="TRANS=${TRANS},"
		EXPORT+="VM=${VM},"
		EXPORT+="FORCE=${fflag},"
		EXPORT+="WKDIR=${WKDIR},"
		EXPORT+="LINES=${LINES},"
		EXPORT+="SCRIPT_DIR=${SCRIPT_DIR},"
		EXPORT+="KEEP_FILES=${KEEP_FILES},"
		EXPORT+="EO_DIR=${EO_DIR}"

		sbatch --export=${EXPORT} \
		--mem=${MEM} \
		--ntasks=${TASKS} \
		--time=${TIME} \
		${SCRIPT_DIR}/ka_ks_pipe.sbatch
	done
	echo "Submitted for pipe: ${RQ_COUNT}"
else
	#submit ref query pair

	EXPORT="REF=${REF},"
	EXPORT+="QUERY=${QUERY},"
	EXPORT+="TRANS=${TRANS},"
	EXPORT+="VM=${VM},"
	EXPORT+="FORCE=${fflag},"
	EXPORT+="WKDIR=${WKDIR},"
	EXPORT+="LINES=${LINES},"
	EXPORT+="SCRIPT_DIR=${SCRIPT_DIR},"
	EXPORT+="KEEP_FILES=${KEEP_FILES},"
	EXPORT+="EO_DIR=${EO_DIR}"

	sbatch --export=${EXPORT} \
	--mem=${MEM} \
	--ntasks=${TASKS} \
	--time=${TIME} \
	${SCRIPT_DIR}/ka_ks_pipe.sbatch	

	echo "Submitted ref/query pair for pipe"
fi







