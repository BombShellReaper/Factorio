#!/bin/bash

set -e  # Exit on any error

# Configurable Variables
FACTORIO_DIR="<path_to_your_factorio_server>"  # Replace with the path to your Factorio server directory
BACKUP_DIR="<path_to_backup_directory>"  # Replace with the path to your backup directory
DOWNLOADS_DIR="<path_to_downloads_directory>"  # Replace with the path to your downloads directory
LOGS_DIR="<path_to_logs_directory>"  # Replace with the path to your logs directory
FACTORIO_FILE="factorio-headless_linux$(date +%Y-%m-%d).tar.xz"
FACTORIO_URL="https://factorio.com/get-download/stable/headless/linux64"  # Factorio server download URL
BACKUP_NAME="${BACKUP_DIR}/BackUp"  # Backup with timestamp
UPDATE_LOG_FILE="${LOGS_DIR}/UpdateServer-$(date +%Y-%m-%d_%H-%M-%S).txt"  # Unique log file for the update
SCREEN_NAME="Factorio_Server_Community"
SAVE_FILE="${FACTORIO_DIR}/factorio/saves/community_server.zip"
SERVER_SETTINGS="${FACTORIO_DIR}/factorio/data/server-settings.json"
CHECKSUM_FILE="${DOWNLOADS_DIR}/factorio_checksum.txt"

# Log function to log messages to the update log file
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${UPDATE_LOG_FILE}"
}

# Ensure necessary directories exist
mkdir -p "${LOGS_DIR}" "${FACTORIO_DIR}" "${DOWNLOADS_DIR}"

# Step 1: Redirect all output for the update process to its log file
exec > >(tee -a "${UPDATE_LOG_FILE}") 2>&1

echo "========== Update Process Started: $(date) =========="

# Step 2: Check checksum to avoid unnecessary downloads
if [[ -f "${CHECKSUM_FILE}" ]]; then
    echo "Verifying checksum..."

    # Get the checksum of the currently downloaded server file
    NEW_CHECKSUM=$(wget -qO- "${FACTORIO_URL}" | sha256sum | awk '{print $1}')

    # Read the previously stored checksum (if it exists)
    PREVIOUS_CHECKSUM=$(cat "${CHECKSUM_FILE}")

    if [[ "$NEW_CHECKSUM" == "$PREVIOUS_CHECKSUM" ]]; then
        echo "Checksum matches. Skipping download and backup, starting the server."

        # Step 3: Start the Factorio server
        echo "========== Starting Factorio Server: $(date) =========="

        # Ensure the Factorio binary exists and the directory structure
        if [ ! -d "${FACTORIO_DIR}/factorio/bin/x64" ] || [ ! -f "${FACTORIO_DIR}/factorio/bin/x64/factorio" ]; then
            log "Error: Factorio binary not found at ${FACTORIO_DIR}/factorio/bin/x64/factorio"
            exit 1
        fi

        # Check if the Factorio server is already running in screen, and kill it if so
        if screen -list | grep -q "${SCREEN_NAME}"; then
            echo "Killing existing Factorio server..."
            screen -S "${SCREEN_NAME}" -X quit
        fi

        # Start Factorio server using screen
        screen -dmS "${SCREEN_NAME}" "${FACTORIO_DIR}/factorio/bin/x64/factorio" --start-server "${SAVE_FILE}" --server-settings "${SERVER_SETTINGS}"

        if [ $? -eq 0 ]; then
            log "Factorio server started successfully."
        else
            log "Error: Failed to start Factorio server."
            exit 1
        fi

         # Clean up old update log files in ~/logs
        LOG_COUNT=$(ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | wc -l)
        if [ "${LOG_COUNT}" -gt 30 ]; then
            ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | tail -n +31 | while read log_file; do
                # Check if the log file exists before attempting to remove it
                if [ -f "${LOGS_DIR}/${log_file}" ]; then
                    rm -f "${LOGS_DIR}/${log_file}"
                    echo "Removed old log file: ${log_file}"
                else
                    echo "Log file ${log_file} no longer exists, skipping."
                fi
            done
            echo "Old update log files cleaned up."
        else
            echo "Update log files do not exceed limit; no cleanup needed."
        fi

        exit 0  # Exit early if the server is started
    else
        echo "Checksum mismatch. Proceeding with download and update."
    fi
else
    echo "Checksum file does not exist, proceeding with download and update."
fi

# Step 4: Backup the current Factorio server
if [ -d "${BACKUP_NAME}" ]; then
    echo "Removing existing BackUp directory..."
    rm -rf "${BACKUP_NAME}"
    echo "BackUp directory removed."
else
    echo "No BackUp directory found. Skipping removal."
fi

# Step 5: Always create a backup of "factorio_server"
cp -r "${FACTORIO_DIR}" "${BACKUP_NAME}"
if [ $? -eq 0 ]; then
    echo "Backup created at ${BACKUP_NAME}."
else
    echo "Error: Failed to create backup."
    exit 1
fi

# Step 6: Download the Factorio headless server file with retry mechanism
echo "Downloading Factorio headless server to ${DOWNLOADS_DIR}/${FACTORIO_FILE}..."
attempt=1
max_attempts=2

while [ $attempt -le $max_attempts ]; do
    # Attempt to download the file
    wget -v -O "${DOWNLOADS_DIR}/${FACTORIO_FILE}" "${FACTORIO_URL}"

    # Check if the download was successful (exit status 0)
    if [ $? -eq 0 ]; then
        echo "Download successful on attempt ${attempt}."
        break
    else
        # If this was the first attempt, wait 60 seconds before retrying
        if [ $attempt -eq 1 ]; then
            echo "Download failed on attempt ${attempt}. Retrying in 60 seconds..."
            sleep 60
        fi

        # Increment the attempt counter
        attempt=$((attempt + 1))

        # If it's the second attempt and it fails, log the error and exit
        if [ $attempt -gt $max_attempts ]; then
            echo "Download failed after ${max_attempts} attempts. Exiting."
            echo "Download failed after ${max_attempts} attempts to ${FACTORIO_URL}" >> "${UPDATE_LOG_FILE}"
            exit 1
        fi
    fi
done

# Step 7: Store checksum after download (Ensure the file only contains the latest checksum)
sha256sum "${DOWNLOADS_DIR}/${FACTORIO_FILE}" | awk '{print $1}' > "${CHECKSUM_FILE}"
echo "Checksum for the downloaded file saved."

# Step 8: Copy the downloaded file to the Factorio directory
echo "Copying downloaded file to ${FACTORIO_DIR}..."
cp "${DOWNLOADS_DIR}/${FACTORIO_FILE}" "${FACTORIO_DIR}"
echo "File copied to ${FACTORIO_DIR}."

# Step 9: Extract the file into the Factorio directory
echo "Extracting ${FACTORIO_FILE} to ${FACTORIO_DIR}/factorio..."
mkdir -p "${FACTORIO_DIR}/factorio"
tar -xvf "${FACTORIO_DIR}/${FACTORIO_FILE}" --strip-components=1 -C "${FACTORIO_DIR}/factorio" || {
    echo "Extraction failed." >> "${UPDATE_LOG_FILE}"
    exit 1
}
echo "Extraction completed."

# Step 10: Start Factorio server using screen
screen -dmS "${SCREEN_NAME}" "${FACTORIO_DIR}/factorio/bin/x64/factorio" --start-server "${SAVE_FILE}" --server-settings "${SERVER_SETTINGS}"

if [ $? -eq 0 ]; then
    log "Factorio server started successfully."
else
    log "Error: Failed to start Factorio server."
    exit 1
fi

# Step 11: Remove the downloaded tar.xz file in the Factorio directory
echo "Cleaning up the tar.xz file from ${FACTORIO_DIR}..."

# Step 12: Check if the tar.xz file exists in FACTORIO_DIR
if ls "${FACTORIO_DIR}"/*.tar.xz 1> /dev/null 2>&1; then
    rm -f "${FACTORIO_DIR}"/*.tar.xz
    echo "All .tar.xz files removed from ${FACTORIO_DIR}."
else
    echo "No .tar.xz files found in ${FACTORIO_DIR} to remove."
fi

# Step 13: Clean up old update log files in ~/logs
LOG_COUNT=$(ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | wc -l)
if [ "${LOG_COUNT}" -gt 30 ]; then
    ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | tail -n +31 | while read log_file; do
        # Check if the log file exists before attempting to remove it
        if [ -f "${LOGS_DIR}/${log_file}" ]; then
            rm -f "${LOGS_DIR}/${log_file}"
            echo "Removed old log file: ${log_file}"
        else
            echo "Log file ${log_file} no longer exists, skipping."
        fi
    done
    echo "Old update log files cleaned up."
else
    echo "Update log files do not exceed limit; no cleanup needed."
fi

# Step 14: Ensure the script exits cleanly after starting the server
echo "========== Update Process Completed: $(date) =========="

exit 0  # Exit the script after completion
