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

update_lastImportedRow() {
     local ini_file=$1
     local new_last_imported_row_uuid=$2
     sed -i "s/^lastMigratedRow=.*$/lastMigratedRow=${new_last_imported_row_uuid}/" "$ini_file"
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
    echo "[ERROR][$(date +"%Y-%m-%d %T")] Required database variables are not set in $INI_FILE"
    exit 1
fi

#fetch aws secrets
awsSecrets=$(python3 fetchPassword.py)
databasePassword=$(echo "$awsSecrets" | jq -r '.DATABASE_PASSWORD')
if [ -z "$databasePassword" ]; then
        echo "[ERROR][$(date +"%Y-%m-%d %T")] database secrets not fetched correctly"
        exit 1
else
        echo "[INFO][$(date +"%Y-%m-%d %T")] database secrets fetched correctly"
fi

# Define variables
DATABASE_HOST=${postgresDatabase_host}
DATABASE_PORT=${postgresDatabase_port}
DATABASE_NAME=${postgresDatabase_name}
#DATABASE_SCHEMA=${postgresDatabase_schema}
DATABASE_USERNAME=${postgresDatabase_username}
MONGO_DB_NAME=${MongoDatabase_name}
#MONGO_DB_USER=${MongoDatabase_username}
MONGO_DB_PORT=${MongoDatabase_port}
MONGO_DB_HOST=${MongoDatabase_host}
#MONGO_DB_PASSWORD=${MongoDatabase_password}
MONGO_DB_COLLECTION=${MongoDatabase_collection}

export PGPASSWORD="$databasePassword"
#shellcheck disable=SC2016
if mongosh  --host "$MONGO_DB_HOST" --port "$MONGO_DB_PORT"  --eval 'db.'"$MONGO_DB_COLLECTION"'.find({}, {uuid: 1, createdAt: 1, _id: 0}).sort({$natural:-1}).limit(1).pretty()' "$MONGO_DB_NAME" > mongoFind.json; then
	uuid=$(grep -oP "(?<=uuid: ')[^']+" mongoFind.json)
	createdAt=$(grep -oP "(?<=createdAt: ISODate\(')[^']+" mongoFind.json)
	echo "[INFO][$(date +"%Y-%m-%d %T")] Extracted UUID: $uuid"
	echo "[INFO][$(date +"%Y-%m-%d %T")] Extracted DATE: $createdAt"
	sql="select uuid from images where uuid='$uuid';"
	if psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c --quiet output="$(psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -t -A -c "$sql" 2> "logs/health/temp-error.log")" "$sql" 2> "logs/health/temp-error.log"; then
		echo "[INFO][$(date +"%Y-%m-%d %T")] Found row $uuid"
	else
		echo "[WARNING][$(date +"%Y-%m-%d %T")] Did not find $uuid in source database"
	fi
fi

update_lastImportedRow "$INI_FILE" "$uuid"


document_count=$(mongosh --host "$MONGO_DB_HOST" --port "$MONGO_DB_PORT" --eval 'db.'"$MONGO_DB_COLLECTION"'.countDocuments()' "$MONGO_DB_NAME")
if [[ $document_count ]]; then
	sql="select count(*) from images where created_at >= '$createdAt'"
	output=$(psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -t -A -c "$sql" 2> "logs/health/temp-error.log")
	psql_exit_code=$?
	if [ $psql_exit_code -ne 0 ]; then
		echo -e "[WARNING][$(date +"%Y-%m-%d %T")] Error occurred while executing SQL query for Health check.\n Check logs/health/temp-error.log for details."
    		exit 1
	fi
	if [[ $output -eq $document_count ]]; then
                echo "[INFO][$(date +"%Y-%m-%d %T")] count matches at : $output"
        else
                echo -e "[WARNING][$(date +"%Y-%m-%d %T")] count does not match with:\n -Mongo count: $document_count\n -postgresql count: $output"
        fi

fi
