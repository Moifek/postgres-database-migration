ini_file="variables.ini"
while IFS=' = ' read -r key value
        do
                if [[ $key =~ ^\[.*\]$ ]]; then
                        section=${key:1:${#key}-2}
                elif [[ -n $key && -n $value ]]; then
                        key=$(echo "${section}_${key}" | tr '.' '_')
                        eval "${key}='${value}'"
                fi
        done < "$ini_file"

echo -e "#######\n[INFO][$(date +"%Y-%m-%d %T")] Starting data migration script \n#######\n" | tee -a "logs/orchestration.log"

if aws s3 sync "s3://${s3Buckets_rootFolder}" . --exclude='*' --include='variables.ini' --dryrun; then
	echo -e "[INFO][$(date +"$Y-%m-%d %T")] Fetched variables from s3 bucket\n"
else
	echo -e "[ERROR][$(date +"$Y-%m-%d %T")] Could not fetch variables from s3 bucket Exiting\n"
	exit 1
fi


./testMigrationScript.sh
migration_exit_code=$?

if [[ $migration_exit_code -eq 1 ]]; then
	echo -e "[WARNING][$(date +"%Y-%m-%d %T")] Script exited with status Code 1 indicating an error or user cancel request \n consult the logs" | tee -a "logs/orchestration.log"
else
	echo -e "[INFO][$(date +"$Y-%m-%d %T")] Script exited with status code : $migration_exit_code \n indicating correct execution" | tee -a "logs/orchestration.log"
fi

./testHealthCheck.sh >> "logs/health/execution.log" 2>&1

#Executing sync
./syncToBucket.sh
sync_exit_code=$?
if [[ $sync_exit_code -eq 1 ]]; then
	echo -e "\n[ERROR][$(date +"%Y-%m-%d %T")] Failed to sync logs to s3" | tee -a "logs/orchestration.log"
else
	echo -e "[INFO][$(date +"%Y-%m-%d %T")] Logs synchronised successfully to s3 bucket\n [NOTE] this line won't exist in the s3 logs" | tee -a "logs/orchestration.log"
fi

 # shellcheck disable=SC2010
if [[ $(ls "logs/" | grep "sync.log" | wc -c) -lt 1 ]]; then
	echo -e "[WARNING][$(date +"%Y-%m-%d %T")] Logs NOT SYNC SUCCESSFULLY" | tee -a "logs/orchestration.log"
fi
