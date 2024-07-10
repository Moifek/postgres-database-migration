# Function to read variables from the ini file
read_ini_file() {
    local ini_file=$1
    while IFS=' = ' read -r key value
    do
        if [[ $key =~ ^\[.*\]$ ]]; then
            section=${key:1:${#key}-2}
        elif [[ -n $key && -n $value ]]; then
            key=$(echo "${section}_${key}" | tr '.' '_')
            eval "${key}='${value}'"
        fi
    done < "$ini_file"
}

update_ini_file() {
    local ini_file=$1
    local new_page_number=$2
    sed -i "s/^pageNumber=.*/pageNumber=${new_page_number}/" "$ini_file"
}

# Read variables from the ini file
INI_FILE="variables.ini"
read_ini_file "$INI_FILE"

# Check if the necessary variables are set
if [ -z "$postgresDatabase_host" ] || [ -z "$postgresDatabase_port" ] || \
   [ -z "$postgresDatabase_name" ] || [ -z "$postgresDatabase_schema" ] || \
   [ -z "$postgresDatabase_username" ] || \
   [ -z "$MongoDatabase_username" ] || [ -z "$MongoDatabase_port" ] || \
   [ -z "$MongoDatabase_host" ] || [ -z "$MongoDatabase_name" ] || \
   [ -z "$MongoDatabase_password" ] || [ -z "$MongoDatabase_collection" ]; then
    echo "[ERROR][$(date +"%Y-%m-%d %T")] Required database variables are not set in $INI_FILE" | tee -a "logs/execution.log"
    exit 1
fi
# Check if the pagination variables are set
if [ -z "$pagination_pageSize" ] || [ -z "$pagination_pageNumber" ]; then
        echo "[ERROR][$(date +"%Y-%m-%d %T")] Required pagination variables are not set in $INI_FILE" | tee -a "logs/execution.log"
        exit 1
fi

#fetch aws secrets
awsSecrets=$(python3 fetchPassword.py)
databasePassword=$(echo "$awsSecrets" | jq -r '.DATABASE_PASSWORD')
if [ -z "$databasePassword" ]; then
        echo "[ERROR][$(date +"%Y-%m-%d %T")] database secrets not fetched correctly" | tee -a "logs/execution.log"
        exit 1
else
        echo "[INFO][$(date +"%Y-%m-%d %T")] database secrets fetched correctly" | tee -a "logs/execution.log"
fi

# Define variables
PAGE_SIZE=${pagination_pageSize}
PAGE_NUMBER=${pagination_pageNumber}
LAST_SUCCESSFUL_ITERATION=${pagination_pageNumber}
DATABASE_HOST=${postgresDatabase_host}
DATABASE_PORT=${postgresDatabase_port}
DATABASE_NAME=${postgresDatabase_name}
DATABASE_SCHEMA=${postgresDatabase_schema}
DATABASE_USERNAME=${postgresDatabase_username}
Iterator=${pagination_pageNumber}
MONGO_DB_NAME=${MongoDatabase_name}
#MONGO_DB_USER=${MongoDatabase_username}
MONGO_DB_PORT=${MongoDatabase_port}
MONGO_DB_HOST=${MongoDatabase_host}
#MONGO_DB_PASSWORD=${MongoDatabase_password}
MONGO_DB_COLLECTION=${MongoDatabase_collection}

# Function to execute the SQL and check the result
execute_sql() {
    local page_number=$1
    local sql="SELECT get_paginated_results(${page_number}, ${PAGE_SIZE}) AS result"
    local output_file="exported-images-page${page_number}.json"
    local error_file="error-page${page_number}.log"
    local temp_error_file="temp_error.log"

# SQL to call the function
local sql="BEGIN;SELECT get_paginated_results(${PAGE_NUMBER}, ${PAGE_SIZE}) AS result;COMMIT;"


#execute the psql procedure
    psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c "$sql" -t -A -F"," --no-align -o "$output_file" 2> "logs/postgres/$temp_error_file";

    local psql_exit_status=$?
    if [[ $psql_exit_status -ne 0 ]]; then
        mv "logs/postgres/$temp_error_file" "logs/postgres/$error_file"
        echo "[ERROR][$(date +"%Y-%m-%d %T")] Failed to execute SQL for page number $page_number. Check $error_file for details." | tee -a "logs/execution.log"
        return 1
    fi

    if [[ $psql_exit_status -eq 0 ]]; then
        echo "[INFO][$(date +"%Y-%m-%d %T")] Data exported to $output_file" | tee -a "logs/execution.log"
        return 0
    else
        echo "[INFO][$(date +"%Y-%m-%d %T")] No more data to export" | tee -a "logs/execution.log"
        rm "logs/postgres/$output_file"
	rm "logs/postgres/$temp_error_file"
        return 2
    fi
}

import_to_mongo() {
    local page_number=$1
    local error_file="error-on-Iteration${page_number}.log"
    local temp_error_file="temp_error.log"
	#Iterator doesn't really have a special functionality here
        echo "[INFO][$(date +"%Y-%m-%d %T")] using file exported-images-page$Iterator.json" | tee -a "logs/execution.log"
        mongoimport --host "$MONGO_DB_HOST":"$MONGO_DB_PORT" --db "$MONGO_DB_NAME" --collection "$MONGO_DB_COLLECTION" \
	--mode upsert --upsertFields uuid --type json --file exported-images-page"$Iterator".json --jsonArray -vvv \
	2> "logs/mongo/$temp_error_file" | tee -a "logs/mongo/execution.log"
	local mongo_exit_code=$?
	if [[ $mongo_exit_code -ne 0 ]]; then
		mv "logs/mongo/$temp_error_file" "logs/mongo/$error_file"
		echo "[ERROR][$(date +"%Y-%m-%d %T")] failed to import to mongoDB, consult /logs/mongo/$error_file" | tee -a "logs/execution.log"
		return 1
	fi
	Iterator=$((Iterator + 1))
	LAST_SUCCESSFUL_ITERATION=$PAGE_NUMBER
	return 0
}

############# MAIN ##############

#exporting database password to use for connection
export PGPASSWORD="$databasePassword"

#executing the initial script to generate the SQL procedure
psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c "SET schema '${DATABASE_SCHEMA}'"

echo "[INFO][$(date +"%Y-%m-%d %T")] Schema set to $DATABASE_SCHEMA" | tee -a "logs/execution.log"

if [[ $( < "logs/init_errors.log" tr ' ' _ | nl) -ne 0 ]]; then
	echo "[WARNING] logs/init_errors.log EXISTS; THE SCRIPT WONT WORK, MANUAL INSPECTION AND DELETING THE FILE IS NEEDED"
fi

psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -f export.sql 2> "logs/init_errors.log"

if [[ $? -ne 0  || $( < "logs/init_errors.log" tr ' ' _ | nl ) -ne 0 ]]; then
    echo "[ERROR][$(date +"%Y-%m-%d %T")] Failed to execute the initial SQL script. consult logs/init_erros.log" | tee -a "logs/execution.log"
    exit 1
fi

echo "[INFO][$(date +"%Y-%m-%d %T")] Procedure created on $DATABASE_NAME - ready to extract" | tee -a "logs/execution.log"

# Loop to handle pagination
while true; do
        echo -e "[INFO][$(date +"%Y-%m-%d %T")] executing extraction \n - iteration : $PAGE_NUMBER \n - batch size : $PAGE_SIZE " | tee -a "logs/execution.log"
    execute_sql "$PAGE_NUMBER"
    exit_code=$?
    if [[ $exit_code -eq 1 ]]; then
        update_ini_file "$INI_FILE" "$LAST_SUCCESSFUL_ITERATION"
	echo "[ERROR][$(date +"%Y-%m-%d %T")] Script ended with error and Variables reset to starting iteration number $LAST_SUCCESSFUL_ITERATION." | tee -a "logs/execution.log"
        exit 1
    fi
    if [[ $exit_code -eq 2 ]]; then
        echo "[INFO][$(date +"%Y-%m-%d %T")] Script ended and data exported with $((PAGE_NUMBER - 1)) total pages, starting with $LAST_SUCCESSFUL_ITERATION" | tee -a "logs/execution.log"
        break
    fi
    if [[ $exit_code -eq 0 ]]; then
       import_to_mongo "$PAGE_NUMBER"
       mongo_exit_code=$?
	if [[ $mongo_exit_code -eq 1 ]]; then
		echo "[ERROR][$(date +"%Y-%m-%d %T")] an error occured during data import on mongo database" | tee -a "logs/execution.log"
		echo "[ERROR][$(date +"%Y-%m-%d %T")] Script ended with error and Variables reset to starting page number $LAST_SUCCESSFUL_ITERATION ." | tee -a "logs/execution.log"
		exit 1
	fi
	if [[ $mongo_exit_code -eq 0 ]]; then
		echo "[INFO][$(date +"%Y-%m-%d %T")] imported successfully" | tee -a "logs/execution.log"
		rm "exported-images-page$PAGE_NUMBER.json"
		PAGE_NUMBER=$((PAGE_NUMBER + 1))
		update_ini_file "$INI_FILE" "$PAGE_NUMBER"
	fi
   fi
done

