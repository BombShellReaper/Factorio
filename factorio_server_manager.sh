#!/bin/bash

set -e  # Exit on any error

# Configurable Variables
FACTORIO_SERVER_DIR="<path_to_your_factorio_server>"                                # Path to your Factorio server directory (e.g., /home/user/factorio)
BACKUP_DIR="<path_to_backup_directory>"                                             # Path to where backups will be stored (e.g., /home/user/factorio_backups)
DOWNLOADS_DIR="<path_to_downloads_directory>"                                       # Path to your downloads directory (e.g., /home/user/downloads)
LOGS_DIR="<path_to_logs_directory>"                                                 # Path to where the logs will be saved (e.g., /home/user/factorio_logs)
FACTORIO_FILE="factorio-headless_linux$(date +%Y-%m-%d).tar.xz"                     # Name of the downloaded Factorio server file with a date suffix
FACTORIO_URL="https://factorio.com/get-download/stable/headless/linux64"            # Factorio server download URL
BACKUP_DIR_NAME="${BACKUP_DIR}/factorio_backup_$(date +%Y-%m-%d_%H-%M-%S)"          # Backup directory with timestamp (e.g., /home/user/factorio_backups/factorio_backup_2024-12-23)
UPDATE_LOG_FILE="${LOGS_DIR}/factorio_update_log_$(date +%Y-%m-%d_%H-%M-%S).txt"    # Log file for the update process (e.g., /home/user/factorio_logs/factorio_update_log_2024-12-23_15-30-00.txt)
SCREEN_SESSION_NAME="factorio_server_session"                                       # Name for the screen session running the server (e.g., factorio_server_session)
SAVE_FILE="${FACTORIO_SERVER_DIR}/factorio/saves/community_server.zip"              # Path to the save file used by the server (e.g., /home/user/factorio/saves/community_server.zip)
SERVER_SETTINGS="${FACTORIO_SERVER_DIR}/factorio/data/server-settings.json"         # Path to the Factorio server settings file (e.g., /home/user/factorio/data/server-settings.json)
CHECKSUM_FILE="${DOWNLOADS_DIR}/factorio_checksum.txt"                              # Path to store the checksum of the downloaded Factorio server file (e.g., /home/user/factorio/factorio_checksum.txt)

# Default log level (can be overridden by environment variable LOG_LEVEL)
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Log function to log messages to the update log file
log() {
    local level="$1"
    local message="$2"
    
    # Determine whether to log based on log level
    case "$LOG_LEVEL" in
        DEBUG)
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message" >> "${UPDATE_LOG_FILE}"
            ;;
        INFO)
            if [[ "$level" == "INFO" || "$level" == "ERROR" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message" >> "${UPDATE_LOG_FILE}"
            fi
            ;;
        ERROR)
            if [[ "$level" == "ERROR" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message" >> "${UPDATE_LOG_FILE}"
            fi
            ;;
        *)
            echo "Invalid log level specified. Defaulting to INFO."
            LOG_LEVEL="INFO"
            ;;
    esac
}

# Ensure necessary directories exist
mkdir -p "${LOGS_DIR}" "${FACTORIO_DIR}" "${DOWNLOADS_DIR}"

# Step 1: Redirect all output for the update process to its log file
exec > >(tee -a "${UPDATE_LOG_FILE}") 2>&1

log INFO "========== Update Process Started: $(date) =========="

# Step 2: Check checksum to avoid unnecessary downloads
if [[ -f "${CHECKSUM_FILE}" ]]; then
    log INFO "Verifying checksum..."

    # Get the checksum of the currently downloaded server file
    NEW_CHECKSUM=$(wget -qO- "${FACTORIO_URL}" | sha256sum | awk '{print $1}')

    # Read the previously stored checksum (if it exists)
    PREVIOUS_CHECKSUM=$(cat "${CHECKSUM_FILE}")

    if [[ "$NEW_CHECKSUM" == "$PREVIOUS_CHECKSUM" ]]; then
        log INFO "Checksum matches. Skipping download and backup, starting the server."

        # Step 3: Start the Factorio server
        log INFO "========== Starting Factorio Server: $(date) =========="

        # Ensure the Factorio binary exists and the directory structure
        if [ ! -d "${FACTORIO_DIR}/factorio/bin/x64" ] || [ ! -f "${FACTORIO_DIR}/factorio/bin/x64/factorio" ]; then
            log ERROR "Error: Factorio binary not found at ${FACTORIO_DIR}/factorio/bin/x64/factorio"
            exit 1
        fi

        # Check if the Factorio server is already running in screen, and kill it if so
        if screen -list | grep -q "${SCREEN_NAME}"; then
            log INFO "Killing existing Factorio server..."
            screen -S "${SCREEN_NAME}" -X quit
        fi

        # Start Factorio server using screen
        screen -dmS "${SCREEN_NAME}" "${FACTORIO_DIR}/factorio/bin/x64/factorio" --start-server "${SAVE_FILE}" --server-settings "${SERVER_SETTINGS}"

        if [ $? -eq 0 ]; then
            log INFO "Factorio server started successfully."
        else
            log ERROR "Error: Failed to start Factorio server."
            exit 1
        fi

        # Clean up old update log files in ~/logs
        LOG_COUNT=$(ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | wc -l)
        if [ "${LOG_COUNT}" -gt 30 ]; then
            ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | tail -n +31 | while read log_file; do
                # Check if the log file exists before attempting to remove it
                if [ -f "${LOGS_DIR}/${log_file}" ]; then
                    rm -f "${LOGS_DIR}/${log_file}"
                    log INFO "Removed old log file: ${log_file}"
                else
                    log INFO "Log file ${log_file} no longer exists, skipping."
                fi
            done
            log INFO "Old update log files cleaned up."
        else
            log INFO "Update log files do not exceed limit; no cleanup needed."
        fi

        exit 0  # Exit early if the server is started
    else
        log INFO "Checksum mismatch. Proceeding with download and update."
    fi
else
    log INFO "Checksum file does not exist, proceeding with download and update."
fi

# Step 4: Backup the current Factorio server
if [ -d "${BACKUP_NAME}" ]; then
    log INFO "Removing existing BackUp directory..."
    rm -rf "${BACKUP_NAME}"
    log INFO "BackUp directory removed."
else
    log INFO "No BackUp directory found. Skipping removal."
fi

# Step 5: Always create a backup of "factorio_server"
cp -r "${FACTORIO_DIR}" "${BACKUP_NAME}"
if [ $? -eq 0 ]; then
    log INFO "Backup created at ${BACKUP_NAME}."
else
    log ERROR "Error: Failed to create backup."
    exit 1
fi

# Step 6: Download the Factorio headless server file with retry mechanism
log INFO "Downloading Factorio headless server to ${DOWNLOADS_DIR}/${FACTORIO_FILE}..."
attempt=1
max_attempts=2

while [ $attempt -le $max_attempts ]; do
    # Attempt to download the file
    wget -v -O "${DOWNLOADS_DIR}/${FACTORIO_FILE}" "${FACTORIO_URL}"

    # Check if the download was successful (exit status 0)
    if [ $? -eq 0 ]; then
        log INFO "Download successful on attempt ${attempt}."
        break
    else
        # If this was the first attempt, wait 60 seconds before retrying
        if [ $attempt -eq 1 ]; then
            log INFO "Download failed on attempt ${attempt}. Retrying in 60 seconds..."
            sleep 60
        fi

        # Increment the attempt counter
        attempt=$((attempt + 1))

        # If it's the second attempt and it fails, log the error and exit
        if [ $attempt -gt $max_attempts ]; then
            log ERROR "Download failed after ${max_attempts} attempts. Exiting."
            exit 1
        fi
    fi
done

# Step 7: Store checksum after download (Ensure the file only contains the latest checksum)
sha256sum "${DOWNLOADS_DIR}/${FACTORIO_FILE}" | awk '{print $1}' > "${CHECKSUM_FILE}"
log INFO "Checksum for the downloaded file saved."

# Step 8: Copy the downloaded file to the Factorio directory
log INFO "Copying downloaded file to ${FACTORIO_DIR}..."
cp "${DOWNLOADS_DIR}/${FACTORIO_FILE}" "${FACTORIO_DIR}"
log INFO "File copied to ${FACTORIO_DIR}."

# Step 9: Extract the file into the Factorio directory
log INFO "Extracting ${FACTORIO_FILE} to ${FACTORIO_DIR}/factorio..."
mkdir -p "${FACTORIO_DIR}/factorio"
tar -xvf "${FACTORIO_DIR}/${FACTORIO_FILE}" --strip-components=1 -C "${FACTORIO_DIR}/factorio" || {
    log ERROR "Extraction failed."
    exit 1
}
log INFO "Extraction completed."

# Step 10: Start Factorio server using screen
screen -dmS "${SCREEN_NAME}" "${FACTORIO_DIR}/factorio/bin/x64/factorio" --start-server "${SAVE_FILE}" --server-settings "${SERVER_SETTINGS}"

if [ $? -eq 0 ]; then
    log INFO "Factorio server started successfully."
else
    log ERROR "Error: Failed to start Factorio server."
    exit 1
fi

# Step 11: Remove the downloaded tar.xz file in the Factorio directory
log INFO "Cleaning up the tar.xz file from ${FACTORIO_DIR}..."

if ls "${FACTORIO_DIR}"/*.tar.xz 1> /dev/null 2>&1; then
    rm -f "${FACTORIO_DIR}"/*.tar.xz
    log INFO "All .tar.xz files removed from ${FACTORIO_DIR}."
else
    log INFO "No .tar.xz files found in ${FACTORIO_DIR} to remove."
fi

# Step 12: Remove the dowloaded tar.xz in the Downloads directory
log INFO "Cleaning up the tar.xz file from ${DOWNLOADS_DIR}..."

if ls "${DOWNLOADS_DIR}"/*.tar.xz 1> /dev/null 2>&1; then
    rm -f "${DOWNLOADS_DIR}"/*.tar.xz
    log INFO "All .tar.xz files removed from ${DOWNLOADS_DIR}."
else
    log INFO "No .tar.xz files found in ${FACTORIO_DIR} to remove."
fi

# Step 13: Clean up old update log files in ~/logs
LOG_COUNT=$(ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | wc -l)
if [ "${LOG_COUNT}" -gt 30 ]; then
    ls -tp "${LOGS_DIR}" | grep "UpdateServer-.*\.txt" | tail -n +31 | while read log_file; do
        # Check if the log file exists before attempting to remove it
        if [ -f "${LOGS_DIR}/${log_file}" ]; then
            rm -f "${LOGS_DIR}/${log_file}"
            log INFO "Removed old log file: ${log_file}"
        else
            log INFO "Log file ${log_file} no longer exists, skipping."
        fi
    done
    log INFO "Old update log files cleaned up."
else
    log INFO "Update log files do not exceed limit; no cleanup needed."
fi

# Step 14: Ensure the script exits cleanly after starting the server
log INFO "========== Update Process Completed: $(date) =========="

exit 0  # Exit the script after completion
