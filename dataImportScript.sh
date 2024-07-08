# Function to read variables from the ini file
read_ini_file() {
    local ini_file=$1
    while IFS=' = ' read -r key value
    do
        if [[ $key =~ ^\[.*\]$ ]]; then
            section=${key:1:${#key}-2}
        elif [[ $key && $value ]]; then
            key=$(echo "${section}_${key}" | tr '.' '_')
            eval "${key}='${value}'"
        fi
    done < "$ini_file"
}


# Read variables from the ini file
INI_FILE="variables.ini"
read_ini_file "$INI_FILE"

# Check if the variables are set
if [ -z "$pagination_pageSize" ] || [ -z "$pagination_pageNumber" ]; then
    echo "[ERROR] Variables pageSize or pageNumber are not set in $INI_FILE"
    exit 1
fi

# Define variables
PAGE_SIZE=${pagination_pageSize}
PAGE_NUMBER=${pagination_pageNumber}
Iterator=1
mongoConnectionString="mongodb://localhost:27019/"

# Connect to mongoDB
# mongosh $mongoConnectionString

while true; do
    if [[ $Iterator -le $(($PAGE_NUMBER - 1)) ]]; then
        echo "[INFO] using file exported-images-page$Iterator.json"
	mongoimport $mongoConnectionString --db test --collection testingImport --mode upsert --upsertFields uuid --type json --file exported-images-page$Iterator.json --jsonArray
        Iterator=$((Iterator + 1))  # Increment Iterator
    else
        break
    fi
done

echo "[INFO] Iteration complete."
exit 0
