#!/bin/bash

# This script scales a Redis database in Redis Cloud using the Redis Cloud API.
# It takes the following parameters:
SUBS_ID=$1
DB_ID=$2
TARGET_TPS=$3
POLL_SECONDS=$4

echo "SUBS_ID: $SUBS_ID"
echo "DB_ID: $DB_ID"
echo "TARGET_TPS: $TARGET_TPS"
echo "POLL_SECONDS: $POLL_SECONDS"

# Check if SUBSCRIPTION_ID and DB_ID are provided
# if [ -z "$SUBS_ID" ] || [ -z "$DB_ID" ]; then
#   echo "Usage --> $0 SUBSCRIPTION_ID DB_ID TARGET_TPS POLL_SECONDS"
#   echo "Example --> $0 2712295 13140775 10000 15"
#   exit 1
# fi

# Check if SUBSCRIPTION_ID, DB_ID and TARGET_TPS are provided
if ! [[ "$SUBS_ID" =~ ^[0-9]+$ ]] || ! [[ "$DB_ID" =~ ^[0-9]+$ ]] || ! [[ "$TARGET_TPS" =~ ^[0-9]+$ ]]; then
  echo "SUBSCRIPTION_ID, DB_ID and TARGET_TPS must have valid values."
  echo "Usage --> $0 SUBSCRIPTION_ID DB_ID TARGET_TPS POLL
_SECONDS"
  echo "Example --> $0 2712295 13140775 10000 15"
  exit 1
fi

# If POLL_SECONDS is not provided, set it to 15
if [ -z "$POLL_SECONDS" ]; then
  POLL
_SECONDS=15
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

# Redis Cloud API base URL
API_BASE_URL="https://api.redislabs.com/v1"

# Start time
start_time=$(date +%s)
echo "Starting scaling at: $(date)"

data=$(cat <<EOF
{
  "dryRun": false,
  "throughputMeasurement": {
    "by": "operations-per-second",
    "value": $TARGET_TPS
  }
}
EOF
)

echo "Scaling Redis database $DB_ID"

resp=$(curl -s --location --request PUT "${API_BASE_URL}/subscriptions/${SUBS_ID}/databases/${DB_ID}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ACCOUNT_KEY" \
  -H "x-api-secret-key: $SECRET_KEY" \
  -d "$data") 

taskId=$(echo "$resp" | jq -r '.taskId')
echo "TaskId: $taskId"
echo

processing_completed=false

echo "Sending request..."
# Check if taskId is not null or blank
if [[ -n "$taskId" && "$taskId" != "null" ]]; then
      while true; do
        status=$(curl -s --location --request GET "${API_BASE_URL}/tasks/${taskId}" \
          -H "Content-Type: application/json" \
          -H "x-api-key: $ACCOUNT_KEY" \
          -H "x-api-secret-key: $SECRET_KEY" \
          | jq -r '.status')

        #echo "Current task status: $status"
        if [[ "$status" == "processing-completed" ]]; then
            echo "Processing completed."
            processing_completed=true
            echo
            break
        fi
        sleep 2
      done
else
    echo "⚠️ Status is null or blank. Error occurred while scaling up."
fi


if [[ "$processing_completed" == true ]]; then
  # Check if scaling operation to complete
  db_status=$(curl -s --location --request GET "${API_BASE_URL}/subscriptions/${SUBS_ID}/databases/${DB_ID}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ACCOUNT_KEY" \
  -H "x-api-secret-key: $SECRET_KEY" \
  | jq -r '.status') 
  echo "Current status of the database: $db_status"    
  echo "Waiting for the scaling operation to complete..."
  while true; do
    if [[ "$db_status" == "active" ]]; then
        echo "✅ Scaling completed."
        echo "The database is active again"
        end_time=$(date +%s)
        echo "Scaling completed at: $(date)"
        duration=$((end_time - start_time))
        minutes=$((duration / 60))
        seconds=$((duration % 60))
        echo "Database scaled to ${TARGET_TPS} ops/sec in ${minutes} minute(s) and ${seconds} second(s)"
        break
    else 
        sleep "$POLL
      _SECONDS"
        db_status=$(curl -s --location --request GET "${API_BASE_URL}/subscriptions/${SUBS_ID}/databases/${DB_ID}" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ACCOUNT_KEY" \
        -H "x-api-secret-key: $SECRET_KEY" \
        | jq -r '.status')
    fi
  done    
fi
