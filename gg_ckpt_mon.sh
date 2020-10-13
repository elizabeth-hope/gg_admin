#!/bin/bash
#set -xv

###############################################
# Name : gg_ckpt_mon.sh
# Desc : Monitor the replicat checkpoints of OGG MSA Replicats and optionally kill the replicat if the checkpoint is old, indicating a hung process
#
# Usage: $SCRIPT_NAME [-k]
#		The -k option will run the script in kill mode and any replicats that appear to be hanging will be killed.
#		If -k is not used the script will be run in monitor mode and will only output the checkpoint details to a log file
# Funct: None
#
# Change History
# Date    Who Decription
# ======= === ==============================
# 12/10/2020	EHO057	Script Created
#
##############################################
#$Header: $
##############################################

#------------------------
# Setup Global Variables
#------------------------

if [ $USER == "ogg" ]; then
   export ADMDIR=/home/ogg
elif  $USER == "oracle" ]; then
   export ADMDIR=/u01/app/oracle/admin
elif  $USER == "grid" ]; then
   export ADMDIR=/u01/app/grid/admin
fi

LOGDIR=$ADMDIR/log

HOST=`hostname`
DATE=`date +%d%m%y`
EMAILERS="elizabeth.hope@maersk.com"

F_SCRIPT=`basename ${0}`
SCRIPT=`basename ${0%.*}`
LOGFILE=${LOGDIR}/${SCRIPT}-${DATE}.log
CKPT_TRACE_FILE=${LOGDIR}/${SCRIPT}-ckpt-${DATE}.lst

exec >> $LOGFILE 2>&1
echo
echo "------------------------------------------------------"
echo "Starting $F_SCRIPT at `date`"
echo "------------------------------------------------------"

##########################################################################
###################################################################H######

# set up WARNING and ERROR thresholds
WARN_MINS=5
ERR_MINS=15
((WARN_AGE_THRESHOLD=($WARN_MINS*60)))
((ERR_AGE_THRESHOLD=($ERR_MINS*60)))
KILL_ERR_REPLICAT=FALSE


# process script flag to decide of the script operates in monitor or kill mode
while getopts k OPTION
do
   case $OPTION in
      k) KILL_ERR_REPLICAT=TRUE ;;
   esac
done
shift $(($OPTIND - 1))


if [ "$KILL_ERR_REPLICAT" = "TRUE" ]
then
	echo
	echo "Script is being run in KILL mode.  Replicats with checkpoint greater than $ERR_MINS mins will be killed"
else
	echo
	echo "Script is being run in MONITOR ONLY mode"
fi
echo "Checkpoint statistics file is $CKPT_TRACE_FILE"
echo

# output a header to the file storing the checkpoint stats if it does not already exist
if [ ! -f $CKPT_TRACE_FILE ]
then
	echo "SEVERITY,REPLICAT,REPLICAT_PID,RUNTIME_DATE,CKPT_DATE,CKPT_AGE_IN_SECS" >>$CKPT_TRACE_FILE
fi

# find out deployment names with running replicats
for deployment in `ps -ef | grep replicat | grep deployments | awk '{ print $(NF-2) }' | cut -d/ -f1-4 | sort -u`
do
	echo "Current deployment is $deployment ..."
	echo
		#find running replicats and compare the modify time of the replicat's checkpoint file against the script thresholds
		for running_replicat in `ps -ef | grep replicat | grep $deployment | awk '{ print $(NF) }'`
		do
			echo " ===================="
			echo "Checking CKPT file for running replicat $running_replicat ..."

			CURRENT_DATETIME=`date +%F_%T`
			CKPT_FILE=${deployment}/var/lib/checkpt/${running_replicat}.cpr
			CKPT_DATE=`date -r $CKPT_FILE +%F_%T`
			CKPT_FILE_AGE_S=`echo $(( $echo $(date +%s) - $echo $(stat -L --format %Y $CKPT_FILE) ))`
			REPLICAT_PID=`ps -ef | grep $running_replicat | grep $deployment | grep replicat | awk '{ print $(2) }'`

			if [ "$CKPT_FILE_AGE_S" -gt "$ERR_AGE_THRESHOLD" ]
			then
                                echo "ERROR,$running_replicat,$REPLICAT_PID,$CURRENT_DATETIME,$CKPT_DATE,$CKPT_FILE_AGE_S"  >>$CKPT_TRACE_FILE

				# if the script is running in kill mode then kill the 'hanging' replicat
				if [ "$KILL_ERR_REPLICAT" = "TRUE" ]
				then
					echo "Replicat $running_replicat appears to have hung. Killing pid $REPLICAT_PID"
					echo "Process details before being killed (based on PID):"
					ps -ef | grep $REPLICAT_PID | grep -v grep
					echo
					kill $REPLICAT_PID
					sleep 5
					echo "Process details after being killed (based on Replicat name):"
					ps -ef | grep $running_replicat | grep -v grep
					echo
					tail -20 $LOGFILE | iconv -f ISO-8859-1 -t ASCII//TRANSLIT | mail -s "$HOST : $USER : $F_SCRIPT : Replicat $running_replicat killed" $EMAILERS
				fi

			elif [ "$CKPT_FILE_AGE_S" -gt "$WARN_AGE_THRESHOLD" ]
			then
				echo "WARNING,$running_replicat,$REPLICAT_PID,$CURRENT_DATETIME,$CKPT_DATE,$CKPT_FILE_AGE_S"  >>$CKPT_TRACE_FILE
			else
				echo "INFO,$running_replicat,$REPLICAT_PID,$CURRENT_DATETIME,$CKPT_DATE,$CKPT_FILE_AGE_S" >>$CKPT_TRACE_FILE
			fi

                        CURRENT_DATETIME=
                        CKPT_FILE=
                        CKPT_DATE=
                        CKPT_FILE_AGE_S=
		done
	echo
	echo "==========================================="
done

echo "Ending $F_SCRIPT at `date`"
echo "------------------------------------------------------"
exit