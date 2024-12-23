# Setting Up a Dedicated Factorio Server

## **Overview**

- This is a step-by-step guide on how to set up and run a Factorio server.

## **Prerequisites**

This guide is not intended for complete beginners to Linux or server administration. It assumes the following:

- Basic knowledge of Linux: You should be comfortable using the terminal (command line), understanding file system paths, and basic Linux commands like cd, ls, mkdir, and cp.
- Basic networking understanding: Familiarity with concepts like IP addresses, ports, and SSH will help as you configure remote access to your server.
- Experience with server setup: You should have some experience setting up and managing servers. This includes installing packages, configuring firewalls, and understanding security practices like disabling 
  root login.
- Access to a Linux server: You should have a VPS or dedicated server with a fresh installation of a supported Linux distribution (Ubuntu or Debian recommended).
- Root or Sudo privileges: You need to be able to execute administrative commands (with sudo or as root) on the server.

- If you are not familiar with these concepts, you may want to spend some time with basic Linux tutorials before proceeding. This guide will walk you through the setup step-by-step, but we won’t be able to 
  cover fundamental Linux concepts in detail. You can find helpful resources online, such as the Linux Foundation’s tutorials, or consider following beginner guides for server setup.

> [!Caution]
> Directory structures may differ based on your specific setup. Always check paths and ensure you're working in the correct directories to avoid issues.

# Step 1: Update and Upgrade Your System

    sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y

# Step 2: Install Required Dependencies 
    
> Install Screen (Session Manager)

    sudo apt install screen -y

> **Install OpenSSH Sever**

    sudo apt install openssh-server -y
> [!NOTE]
> This enables secure remote access to your server.

> Install UFW (Uncomplicated Firewall)

    sudo apt install ufw -y

# Step 3: Configure UFW (Uncomplicated Firewall)

> Allow all incoming connections to port 34197:

    sudo ufw allow from any proto udp to any port 34197 comment "Factorio Server Port"

> [!TIP]
> For improved security, restrict access to only trusted IP addresses.

**Allow SSH Connections Through UFW** (Optional)

    sudo ufw allow from any to any port 22 comment "SSH"

> [!TIP]
> For improved security, restrict access to only trusted IP addresses.

> Set the default rule to deny incoming traffic (Optional)

    sudo ufw default deny incoming

> **Enable UFW** (UFW will enable on reboot)

    sudo ufw enable

> Check the UFW status after enabling it:

    sudo ufw status
    
--------------------------------------------------------------------------------
# Step 4: Create a Non Sudo User

> Replace "*your_username*" with the desired username.

    sudo adduser your_username

> [!NOTE]
> This will prompt you through the setup

> **Reboot the system**

    sudo reboot

-------------------------------------------------------------------------------
# Step 5: Download the Factorio Dedicated Server Files & Set-Up

**Log in to your server with the new user account through cmd, PowerShell, PuTTY, etc. Use your preferred terminal emulator.**

> **Make a Server Directory. Replace *server_dir_name* with the name you want**

    mkdir -p server_dir_name/factorio

> **Make a Downloads Directory. You can replace *Downloads* with any name you want.**

    mkdir Downloads

> **Download The server Files**

    wget -v -O ~/Downloads/factorio-headless_linux$(date +%Y-%m-%d).tar.xz https://factorio.com/get-download/stable/headless/linux64

> **Copy The file in the Downloads Directory to The Server Directory**

    cp ~/Downloads/the_server_file ~/server_dir_name

> **Extract the file into the Factorio Server directory**

    tar -xvf server_dir_name/factorio the_zip_in_the_Downloads_dir --strip-components=1 -C ~/server_dir_name/factorio

> **Navigate to the Server Directory. Replace *server_dir_name* with the one you created from above**

    cd ~/server_dir_name/factorio

> **Delete the Zip file. Replace *the_zip_file* with the correct name**

    rm the_zip_file

> **Create a *saves* Directory**

    mkdir saves

> **Create a new save Replace *my-save.zip* with what you want the save to be called. Example: Fun-Land.zip**

    ./bin/x64/factorio --create ./saves/my-save.zip

# Step 6: Configure the Server

> **Navigate to the **data** Directory. Replace *server_dir_name* with the one you created**

    cd ~/server_dir_name/factorio/data

> [!NOTE]
> There are three files you can edit before starting the server. Howerver this is optional, but highly recomended.

> **Edit the Map Settings**

    nano map-settings.example.json

> [!TIP]
> When you are done making changes. Press the "Ctrl" + "o", then delete the **.example** in the file name. Press "Enter", then press "Y". Lastly press "Ctrl" + "x"

> **Edit the Server Setting**

    nano server-settings.example.json

> [!TIP]
> When you are done making changes. Press the "Ctrl" + "o", then delete the **.example** in the file name. Press "Enter", then press "Y". Lastly press "Ctrl" + "x"

> **Edit The Map Generation settings. This is optional since you already generated the world**

    nano map-gen-settings.example.json

> [!TIP]
> When you are done making changes. Press the "Ctrl" + "o", then delete the **.example** in the file name. Press "Enter", then press "Y". Lastly press "Ctrl" + "x"

> [!NOTE]
> If you want to change the **map-gen-settings**, then you will need to delete the current **my-save.zip** in the **saves** directory and re-create a new **my.save.zip**

> **Start the server. Replace *my-save.zip* with the name you chose in the previous instructions.**

    ./bin/x64/factorio --start-server ./saves/my-save.zip

> [!NOTE]
> Once the server starts and only if it starts you will stop the server by pressing "Ctrl" + "c". 

# Step 7: Create a Startup Script (Optional)

> Return to the users home directory

    cd

> Create a directory to place you scripts. Change the "*name*" with your desired directory name:

    mkdir name

> Change to the new directory. Change the "*name*" with the one you just created:

    cd name

> Create a script. You can change the "*factorio_server_manager.sh*" with your desired script name, but remember to change it throught the following instrustions.

    nano factorio_server_manager.sh


> **Make the script executable by the user:**

    chmod +x factorio_server_manager.sh

> **Copy & edit The Variables In The Begining Of The Script**

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
    
# Step 8: Create a Systemd Service (Optional)

> Switch to your sudo user that you used at the beginning. Replace "*your_username*" with the actual username.

    su your_username

> **Create the service file:**

    sudo nano /etc/systemd/system/factorio_server.service

> **Add the following configuration:**

    [Unit]
    Description=Custom Game Server
    After=network.target
    
    [Service]
    Type=simple
    User=yourusername                          # Define the user under which the service will run. Default is "user".
    ExecStart=/path/to/start_server.sh         # Path to the script that starts the server. 
    Restart=on-failure
    RestartSec=5
    StartLimitIntervalSec=60
    StartLimitBurst=3
    StandardOutput=/var/log/game_server.log    # Standard output and error logs. The log file location can be customized.
    StandardError=/var/log/game_server.log     # Standard output and error logs. The log file location can be customized.
    
    [Install]
    WantedBy=multi-user.target

> **Example**
> 
> User=test
> 
> ExecStart=/home/test/scripts/palworld.sh

**Enable and Start the Service**

    sudo systemctl daemon-reload
    sudo systemctl enable factorio_server.service
    sudo systemctl start factorio_server.service

> [!Important]
>  *This systemd service, along with the accompanying script, ensures that your server automatically starts after a reboot and updates itself before launching.*

# Step 9: Hardening (Optional)

> Login with the sudo user and edit the sshd_config file

    sudo nano /etc/ssh/sshd_config

Locate the following lines and uncomment them, making the specified edits:

> **LoginGraceTime 2m**

    LoginGraceTime 1m

> **PermitRootLogin prohibit-password**

    PermitRootLogin no

> **MaxSessions 10**

    Max Sessions 4

> Reload systemctl & restart sshd.services

    sudo systemctl daemon-reload
    sudo systemctl restart ssh.service

> **Example:**

![image](https://github.com/user-attachments/assets/f12f25af-807d-4981-9e53-ebe2ab3d2688)

These are some steps you can take to enhance the security of your SSH service.

# Change Who Can Use the Switch User (su) Command

Make a new group for the su command. Replace "*group_name*" with your desired name for the new group.

    sudo groupadd group_name

> **Example:** *sudo groupadd restrictedsu*

**Edit who can use the *su* command**

> Edit the *su* config

    sudo nano /etc/pam.d/su

> Edit the following line to restrict su. Replace "*group_name*" with the one you made ealier.

    auth       required   pam_wheel.so group=group_name

> **Example:** *auth       required   pam_wheel.so group=restrictedsu*

**Example:** 

![image](https://github.com/user-attachments/assets/3d3c941b-aadd-4bdb-b736-e2fb4c7b5c8b)


**Conclusion**

You have successfully set up your factorio server! For further customization, refer to the game’s official documentation.


- https://www.factorio.com/download
- https://wiki.factorio.com/Multiplayer
- https://www.digitalocean.com/community/tutorials/ufw-essentials-common-firewall-rules-and-commands
