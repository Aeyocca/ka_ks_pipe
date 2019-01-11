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
	echo "	--rq_list_dir:"
	echo "		<directory where query sets are in>"
	echo "		<specific query directory will be set to rq_list_dir/query"
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
	echo "	--resume:"
	echo "		<if specified, will try to resume where it left off if it was killed by HPCC>"
	echo "		<USE AT YOUR OWN RISK, didn't really debug it fully, got it to work for me though>"
	echo "  --self_comp:"
	echo "		<if specified, this is self comparison, so ignore identical hits>"
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
    "--rq_list_dir") set -- "$@" "-d" ;;
    "--trans") set -- "$@" "-t" ;;
    "--flip") set -- "$@" "-p" ;;
    "--vm") set -- "$@" "-v" ;;
    "--wkdir") set -- "$@" "-w" ;;
    "--force") set -- "$@" "-f" ;;
    "--lines") set -- "$@" "-n" ;;
    "--keep_files") set -- "$@" "-k" ;;
    "--script_dir") set -- "$@" "-s" ;;
    "--scratch_array") set -- "$@" "-a" ;;
    "--eo_path") set -- "$@" "-e" ;;
    "--self_comp") set -- "$@" "-c" ;;
    "--resume") set -- "$@" "-z" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Default behavior
cflag=false
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
aflag=false
zflag=false
dflag=false

# Parse short options
OPTIND=1
while getopts ":a:r:d:e:n:v:q:l:t:w:pfkczs:" opt
do
  case "$opt" in
    "r") REF=$OPTARG; rflag=true ;;
    "c") SELF_COMP="true"; cflag=true ;;
    "q") QUERY=$OPTARG; qflag=true ;;
    "l") RQ_LIST=$OPTARG; lflag=true ;;
    "d") RQ_LIST_DIR=$OPTARG; dflag=true ;;
    "v") VM=$OPTARG; vflag = true ;;
    "w") WKDIR=$OPTARG; wflag=true ;;
    "f") FORCE="true"; fflag=true ;;
    "n") LINES=$OPTARG; nflag=true ;;
    "k") KEEP_FILES="true"; kflag=true ;;
    "s") SCRIPT_DIR=$OPTARG; sflag=true ;;
    "t") TRANS=${OPTARG}; tflag=true ;;
    "p") FLIP="true"; pflag=true ;;
    "a") SCRATCH_ARRAY=${OPTARG}; aflag=true ;;
    "e") EO_DIR=${OPTARG}; eflag=true ;;
    "z") RESUME="true"; zflag=true ;;
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

#check for working directory if rq_list not specified
if ! ${wflag} && ! ${lflag}
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

if ! ${cflag}
then
	SELF_COMP=false
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
		echo "Flipping translation file"
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

##keep files?
##do this in arg parsing now
#if ${kflag}
#then
#	KEEP_FILES="true"
#else
#	KEEP_FILES="false"
#fi

if ! ${eflag}
then
	#use default
	EO_DIR=${WKDIR}/04_error_output
fi

#resume flag, set to true whilst arg parsing if provided
#however, perl script requires arguement if not set
#so set to false if not provided
if ! ${zflag}
then
	RESUME="false"
fi


#this one is for me because I am lazy:
#SCRATCH_ARRAY will help me rolling submit jobs, check code in ka_ks_final_cat
#if you're curious

#load rq_list into hash if specified
if ${lflag}; then
	#check for wkdir
	if ! $dflag; then
		echo ""; echo "rq_list_dir not specified, exiting"; echo ""
		exit 1
	fi

#	declare -A ref_to_query=(); while read i; do tmp_array=($(echo ${i} | tr '	' '\n')); ref_to_query["${tmp_array[]}"]="${tmp_array[0]}"; done < ${RQ_LIST}
	#dont do a hash, can't repeat either ref or query pairs,
	#load into array, split in loop
	declare -a rq_pairs_array=()
	while read line; do
		rq_pairs_array+=("$line")
	done < ${RQ_LIST}

	#count rq_list submissions
	declare -i RQ_COUNT=0
	#loop through hash, submit each line
	for pair in "${rq_pairs_array[@]}"; do

		#Split to ref/query
		IFS="	" read -ra rq_split <<< "$pair"
		#be explicit
		reference=${rq_split[0]}
		query=${rq_split[1]}

		#Set wkdir based on query path
		WKDIR="${RQ_LIST_DIR}/${query}"
		echo "Set wkdir: ${RQ_LIST_DIR}/${query}"

		EO_DIR=${WKDIR}/04_error_output
		mkdir -p ${EO_DIR}

		EXPORT="REF=${reference},"
		EXPORT+="QUERY=${query},"
		EXPORT+="TRANS=${TRANS},"
		EXPORT+="VM=${VM},"
		EXPORT+="FORCE=${fflag},"
		EXPORT+="WKDIR=${WKDIR},"
		EXPORT+="LINES=${LINES},"
		EXPORT+="SCRIPT_DIR=${SCRIPT_DIR},"
		EXPORT+="KEEP_FILES=${KEEP_FILES},"
		EXPORT+="SCRATCH_ARRAY=${SCRATCH_ARRAY},"
		EXPORT+="RESUME=${RESUME},"
		EXPORT+="FLIP=${FLIP},"
		EXPORT+="SELF_COMP=${SELF_COMP},"
		EXPORT+="EO_DIR=${EO_DIR}"

		sbatch --export=${EXPORT} \
		--output=${EO_DIR}/%x-%j.SLURMout \
		--mem=${MEM} \
		--ntasks=${TASKS} \
		--time=${TIME} \
		${SCRIPT_DIR}/ka_ks_pipe.sbatch

		echo ""		
		RQ_COUNT+=1
	done
	echo "Pairs submitted for pipe: ${RQ_COUNT}"
else
	#submit ref query pair
	mkdir -p ${EO_DIR}

	EXPORT="REF=${REF},"
	EXPORT+="QUERY=${QUERY},"
	EXPORT+="TRANS=${TRANS},"
	EXPORT+="VM=${VM},"
	EXPORT+="FORCE=${fflag},"
	EXPORT+="WKDIR=${WKDIR},"
	EXPORT+="LINES=${LINES},"
	EXPORT+="SCRIPT_DIR=${SCRIPT_DIR},"
	EXPORT+="KEEP_FILES=${KEEP_FILES},"
	EXPORT+="SCRATCH_ARRAY=${SCRATCH_ARRAY},"
	EXPORT+="RESUME=${RESUME},"
	EXPORT+="SELF_COMP=${SELF_COMP},"
	EXPORT+="EO_DIR=${EO_DIR}"

	sbatch --export=${EXPORT} \
	--output=${EO_DIR}/%x-%j.SLURMout \
	--mem=${MEM} \
	--ntasks=${TASKS} \
	--time=${TIME} \
	${SCRIPT_DIR}/ka_ks_pipe.sbatch	

	echo "Submitted ref/query pair for pipe"
	echo "Reference (first column of translation file): ${REF}"
	echo "Query (second column of translation file): ${QUERY}"
fi







