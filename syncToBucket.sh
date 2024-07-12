
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

if [[ $( aws s3 ls | grep "moifek" | wc -c) -lt 1 ]]; then
	#shellcheck disable=SC2154
	if aws s3 mb "s3://${s3Buckets_rootFolder}" --region eu-west-2; then
		aws s3 sync . "s3://${s3Buckets_rootFolder}" --exclude='*' --include='variables.ini' >> "logs/sync.log" 2>&1
		echo "[INFO][$(date +"%Y-%m-%d %T")] created s3 bucket ${s3Buckets_rootFolder}" | tee -a "logs/sync.log"
	else
		echo "[ERROR][$(date +"%Y-%m-%d %T")] Failed to create the s3 bucket, stopping logs sync" | tee -a "logs/sync.log"
		exit 1
	fi
else
	echo "[INFO][$(date +"%Y-%m-%d %T")] ${s3Buckets_rootFolder} s3 bucket already created" | tee -a "logs/sync.log"
fi

if [[ $( aws s3 ls "s3://""${s3Buckets_rootFolder}" | grep logs | wc -c) -lt 1 ]]; then
	if [[ $( aws s3 ls "s3://${s3Buckets_rootFolder}" | grep variables.ini | wc -c) -lt 1 ]]; then
		echo -e "[WARNING][$(date +"%Y-%m-%d %T")]\n --------------------------------------------------------- \n VARIABLES FILE DOES NOT EXIST \n ---------------------------------------------------------" | tee -a "logs/sync.log"
		exit 1
	else
		echo -e "[INFO][$(date +"%Y-%m-%d %T")] Syncing variables file" | tee -a "logs/sync.log"
		if aws s3 sync . "s3://${s3Buckets_rootFolder}" --exclude='*' --include='variables.ini' --dryrun; then
			echo "[INFO][$(date +"%Y-%m-%d %T")] Successfully synced variables file to s3" | tee -a "logs/sync.log"
		else
			echo "[WARNING][$(date +"%Y-%m-%d %T")] FAILED TO SYNC VARIABLES FILE TO S3 SHUTTING DOWN" | tee -a "logs/sync.log"
			exit 1
		fi
	fi
	echo "[INFO][$(date +"%Y-%m-%d %T")] syncing logs to s3 bucket : ${s3Buckets_rootFolder}" | tee -a "logs/sync.log"
	aws s3 sync "logs/" "s3://""${s3Buckets_rootFolder}" --dryrun
fi
