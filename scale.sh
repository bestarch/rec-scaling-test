#!/bin/bash

# This script scales a Redis database in Redis Cloud using the Redis Cloud API.

SUBS_ID=$1
DB_ID=$2
SLEEP_SECONDS=$3

# Check if SUBSCRIPTION_ID and DB_ID are provided
if [ -z "$SUBS_ID" ] || [ -z "$DB_ID" ]; then
  echo "Usage --> $0 SUBSCRIPTION_ID DB_ID SLEEP_SECONDS"
  echo "Example --> $0 2712295 13140775 15"
  exit 1
fi
# If SLEEP_SECONDS is not provided, set it to 15
if [ -z "$SLEEP_SECONDS" ]; then
  SLEEP_SECONDS=15
fi
# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq to run this script."
    exit 1
fi
# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "curl could not be found. Please install curl to run this script."
    exit 1
fi
# Check if the required environment variables are set
if [ -z "$ACCOUNT_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo "Please set the ACCOUNT_KEY and SECRET_KEY environment variables."
    exit 1
fi

SLEEP_SECONDS=15

# Redis Cloud API base URL
API_BASE_URL="https://api.redislabs.com/v1"

# Start time
start_time=$(date +%s)
echo "Starting scaling at: $(date)"

data='{
  "dryRun": false,
  "throughputMeasurement": {
    "by": "operations-per-second",
    "value": 20000
  }
}'

echo "Scaling up Redis database $DB_ID"
resp=$(curl -s --location --request PUT "${API_BASE_URL}/subscriptions/${SUBS_ID}/databases/${DB_ID}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ACCOUNT_KEY" \
  -H "x-api-secret-key: $SECRET_KEY" \
  -d "$data") 

echo "Response: $resp"
taskId=$(echo "$resp" | jq -r '.taskId')
echo "TaskId: $taskId"
echo

# Check if taskId is not null or blank
if [[ -n "$taskId" && "$taskId" != "null" ]]; then
      while true; do
        status=$(curl -s --location --request GET "${API_BASE_URL}/tasks/${taskId}" \
          -H "Content-Type: application/json" \
          -H "x-api-key: $ACCOUNT_KEY" \
          -H "x-api-secret-key: $SECRET_KEY" \
          | jq -r '.status')

        echo "Current task status: $status"

        if [[ "$status" == "processing-completed" ]]; then
            echo "✅ Task completed."
            echo
            break
        fi
        sleep "$SLEEP_SECONDS"
      done
else
    echo "⚠️ Status is null or blank. Error occurred while scaling up."
fi

# Get the updated database details
updated_db=$(curl -s --location --request GET "${API_BASE_URL}/subscriptions/${SUBS_ID}/databases/${DB_ID}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ACCOUNT_KEY" \
  -H "x-api-secret-key: $SECRET_KEY") 
echo "Updated database details: $updated_db"
echo

# End time
end_time=$(date +%s)
echo "Scaling completed at: $(date)"

# Time taken
duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))
echo "Scaling operation took: ${minutes} minute(s) and ${seconds} second(s)"
