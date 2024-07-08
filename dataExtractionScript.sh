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
   [ -z "$postgresDatabase_username" ]; then
    echo "[ERROR] Required database variables are not set in $INI_FILE"
    exit 1
fi
# Check if the pagination variables are set
if [ -z "$pagination_pageSize" ] || [ -z "$pagination_pageNumber" ]; then
	echo "[ERROR] Required pagination variables are not set in $INI_FILE"
	exit 1
fi

#fetch aws secrets
awsSecrets=$(python3 fetchPassword.py)
databasePassword=$(echo "$awsSecrets" | jq -r '.DATABASE_PASSWORD')
if [ -z "$databasePassword" ]; then
        echo "[ERROR] database secrets not fetched correctly"
        exit 1
else
        echo "[INFO] database secrets fetched correctly"
fi

# Define variables
PAGE_SIZE=${pagination_pageSize}
PAGE_NUMBER=${pagination_pageNumber}
STARTING_PAGE_NUMBER=${pagination_pageNumber}
DATABASE_HOST=${postgresDatabase_host}
DATABASE_PORT=${postgresDatabase_port}
DATABASE_NAME=${postgresDatabase_name}
DATABASE_SCHEMA=${postgresDatabase_schema}
DATABASE_USERNAME=${postgresDatabase_username}

# SQL to call the function
SQL="BEGIN;SELECT get_paginated_results(${PAGE_NUMBER}, ${PAGE_SIZE}) AS result;COMMIT;"

echo "$databasePassword"
# Function to execute the SQL and check the result
execute_sql() {
    local page_number=$1
    local sql="SELECT get_paginated_results(${page_number}, ${PAGE_SIZE}) AS result"
    local output_file="exported-images-page${page_number}.json"
    local error_file="error-page${page_number}.log"
    local temp_error_file="temp_error.log"

#execute the psql procedure
psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c "$sql" -t -A -F"," --no-align -o "$output_file" 2> "$temp_error_file";

#psql postgresql://$DATABASE_USERNAME:$databasePassword@$DATABASE_HOST:$DATABASE_PORT/$DATABASE_NAME?sslmode=require -c "$sql" -t -A -F"," --no-align -o "$output_file" 2> "$temp_error_file";

    local psql_exit_status=$?
	echo "psql exit code : $psql_exit_status"
    if [[ $psql_exit_status -ne 0 ]]; then
	mv "$temp_error_file" "$error_file"
        echo "[ERROR] Failed to execute SQL for page number $page_number. Check $error_file for details."
        return 1
    fi

    if [[ $(cat "$output_file" | tr -d '[:space:]' | wc -c) -gt 0 ]]; then
        echo "[INFO] Data exported to $output_file"
        return 0
    else
        echo "[INFO] No more data to export"
        rm "$output_file"
        return 2
    fi
}

############# MAIN ##############

#exporting database password to use for connection
export PGPASSWORD="$databasePassword"
#executing the initial script to generate the SQL procedure
psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c "SET schema '${DATABASE_SCHEMA}'"
echo "[INFO] Schema set to $DATABASE_SCHEMA"
psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -f export.sql 2> "init_errors.log"
if [[ $? -ne 0 || $(cat "init_errors.log" | tr -d '[:space:]' | wc -c) -ne 0 ]]; then
    echo "[ERROR] Failed to execute the initial SQL script."
    exit 1
fi

# Loop to handle pagination
while true; do
	echo "[INFO] executing select query with page number : $PAGE_NUMBER"
    execute_sql "$PAGE_NUMBER"
    exit_code=$?
    if [[ $exit_code -eq 1 ]]; then
	echo "[ERROR] Script ended with error and Variables reset to starting page number $STARTING_PAGE_NUMBER."
	update_ini_file "$INI_FILE" "$STARTING_PAGE_NUMBER"
	break
    fi
    if [[ $exit_code -eq 2 ]]; then
	echo "[INFO] Script ended and data exported with $((PAGE_NUMBER - 1)) total pages, starting with $STARTING_PAGE_NUMBER"
	break
    fi
    if [[ $exit_code -eq 0 ]]; then
       PAGE_NUMBER=$((PAGE_NUMBER + 1))
       update_ini_file "$INI_FILE" "$PAGE_NUMBER"
   fi
done
