#!/bin/bash

set -e  # Exit on any error

# Configurable Variables
FACTORIO_DIR="YOUR_PATH/factorio_server"  # Set the path to your Factorio server directory
BACKUP_DIR="YOUR_PATH"  # Set the path to where you want backups to be stored
DOWNLOADS_DIR="YOUR_PATH/Downloads"  # Set the path to your downloads directory
LOGS_DIR="YOUR_PATH/logs"  # Set the path to your logs directory
FACTORIO_FILE="factorio-headless_linux$(date +%Y-%m-%d).tar.xz"  # Name of the Factorio server download
FACTORIO_URL="https://factorio.com/get-download/stable/headless/linux64"  # URL for downloading Factorio headless server
BACKUP_NAME="${BACKUP_DIR}/BackUp"  # Backup with timestamp
UPDATE_LOG_FILE="${LOGS_DIR}/UpdateServer-$(date +%Y-%m-%d_%H-%M-%S).txt"  # Log file for updates
SCREEN_NAME="YOUR_SCREEN_SESSION_NAME"  # Name of your screen session (e.g., Factorio_Server)
SAVE_FILE="${FACTORIO_DIR}/factorio/saves/YOUR_SAVE_FILE.zip"  # Path to the save file for the Factorio server
SERVER_SETTINGS="${FACTORIO_DIR}/factorio/data/server-settings.json"  # Path to server settings file
CHECKSUM_FILE="${DOWNLOADS_DIR}/factorio_checksum.txt"  # File to store the checksum of the downloaded Factorio file

# Log function to log messages to the update log file
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${UPDATE_LOG_FILE}"
}

# Ensure necessary directories exist
mkdir -p "${LOGS_DIR}" "${FACTORIO_DIR}" "${DOWNLOADS_DIR}"

# Redirect all output for the update process to its log file
exec > >(tee -a "${UPDATE_LOG_FILE}") 2>&1

echo "========== Update Process Started: $(date) =========="

# Step 1: Check checksum to avoid unnecessary downloads
if [[ -f "${CHECKSUM_FILE}" ]]; then
    echo "Verifying checksum..."

    # Get the checksum of the currently downloaded server file
    NEW_CHECKSUM=$(wget -qO- "${FACTORIO_URL}" | sha256sum | awk '{print $1}')

    # Read the previously stored checksum (if it exists)
    PREVIOUS_CHECKSUM=$(cat "${CHECKSUM_FILE}")

    if [[ "$NEW_CHECKSUM" == "$PREVIOUS_CHECKSUM" ]]; then
        echo "Checksum matches. Skipping download and backup, starting the server."

        # Step 2: Start the Factorio server
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
        echo "Starting Factorio server..." >> "${UPDATE_LOG_FILE}"
        screen -dmS "${SCREEN_NAME}" "${FACTORIO_DIR}/factorio/bin/x64/factorio" --start-server "${SAVE_FILE}" --server-settings "${SERVER_SETTINGS}" >> "${UPDATE_LOG_FILE}" 2>&1

        # Check if the screen session is running
        if screen -list | grep -q "${SCREEN_NAME}"; then
            echo "Factorio server started successfully in screen session: ${SCREEN_NAME}" >> "${UPDATE_LOG_FILE}"
        else
            echo "Failed to start Factorio server." >> "${UPDATE_LOG_FILE}"
            exit 1
        fi

        # Clean up old update log files in ~/logs
        LOG_COUNT=$(ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | wc -l)
        if [ "${LOG_COUNT}" -gt 30 ]; then
            ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | tail -n +31 | xargs -d '\n' -r rm --
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

# Step 3: Backup the current Factorio server
if [ -d "${BACKUP_NAME}" ]; then
    echo "Removing existing BackUp directory..."
    rm -rf "${BACKUP_NAME}"
    echo "BackUp directory removed."
else
    echo "No BackUp directory found. Skipping removal."
fi

# Step 4: Always create a backup of "factorio_server"
cp -r "${FACTORIO_DIR}" "${BACKUP_NAME}"
if [ $? -eq 0 ]; then
    echo "Backup created at ${BACKUP_NAME}."
else
    echo "Error: Failed to create backup."
    exit 1
fi

# Step 5: Download the Factorio headless server file with retry mechanism
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

# Step 6: Store checksum after download (Ensure the file only contains the latest checksum)
sha256sum "${DOWNLOADS_DIR}/${FACTORIO_FILE}" | awk '{print $1}' > "${CHECKSUM_FILE}"
echo "Checksum for the downloaded file saved."

# Step 7: Copy the downloaded file to the Factorio directory
echo "Copying downloaded file to ${FACTORIO_DIR}..."
cp "${DOWNLOADS_DIR}/${FACTORIO_FILE}" "${FACTORIO_DIR}"
echo "File copied to ${FACTORIO_DIR}."

# Step 8: Extract the file into the Factorio directory
echo "Extracting ${FACTORIO_FILE} to ${FACTORIO_DIR}/factorio..."
mkdir -p "${FACTORIO_DIR}/factorio"
tar -xvf "${FACTORIO_DIR}/${FACTORIO_FILE}" --strip-components=1 -C "${FACTORIO_DIR}/factorio" || {
    echo "Extraction failed." >> "${UPDATE_LOG_FILE}"
    exit 1
}
echo "Extraction completed."

# Step 9: Start Factorio server using screen
echo "Starting Factorio server..." >> "${UPDATE_LOG_FILE}"
screen -dmS "${SCREEN_NAME}" "${FACTORIO_DIR}/factorio/bin/x64/factorio" --start-server "${SAVE_FILE}" --server-settings "${SERVER_SETTINGS}" >> "${UPDATE_LOG_FILE}" 2>&1

# Check if the screen session is running
if screen -list | grep -q "${SCREEN_NAME}"; then
    echo "Factorio server started successfully in screen session: ${SCREEN_NAME}" >> "${UPDATE_LOG_FILE}"
else
    echo "Failed to start Factorio server." >> "${UPDATE_LOG_FILE}"
    exit 1
fi

# Step 10: Remove the downloaded tar.xz file in the Factorio directory
echo "Cleaning up the tar.xz file from ${FACTORIO_DIR}..."

# Check if the tar.xz file exists in FACTORIO_DIR
if ls "${FACTORIO_DIR}"/*.tar.xz 1> /dev/null 2>&1; then
    rm -f "${FACTORIO_DIR}"/*.tar.xz
    echo "All .tar.xz files removed from ${FACTORIO_DIR}."
else
    echo "No .tar.xz files found in ${FACTORIO_DIR} to remove."
fi

# Step 11: Clean up all Factorio headless server .tar.xz files in Downloads
if ls "${DOWNLOADS_DIR}"/*.tar.xz 1> /dev/null 2>&1; then
    echo "Cleaning up all .tar.xz files in ${DOWNLOADS_DIR}..."
    rm -f "${DOWNLOADS_DIR}"/*.tar.xz
    echo "All .tar.xz files removed from ${DOWNLOADS_DIR}."
else
    echo "No .tar.xz files found in ${DOWNLOADS_DIR}. No cleanup needed."
fi

# Step 12: Clean up old update log files in ~/logs
LOG_COUNT=$(ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | wc -l)
if [ "${LOG_COUNT}" -gt 30 ]; then
    ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | tail -n +31 | xargs -d '\n' -r rm --
    echo "Old update log files cleaned up."
else
    echo "Update log files do not exceed limit; no cleanup needed."
fi

# Step 13: Ensure the script exits cleanly after starting the server
echo "========== Update Process Completed: $(date) =========="

exit 0  # Exit the script after completion
