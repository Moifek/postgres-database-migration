./dataExtractionScript.sh
./dataImportScript.sh

EXIT_CODE=$?

# Check if the exit code is not equal to 1
if [ $EXIT_CODE -ne 1 ]; then
    echo "dataExtractionScript.sh executed successfully or with a non-error exit code."
else
    echo "dataExtractionScript.sh exited with code 1, which indicates an error."
fi
