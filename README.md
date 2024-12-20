# Factorio

**Overview**

This is a step-by-step guide on how to set up and run a Factorio server.

**Prerequisites**

- Ubuntu server (20.04 or higher recommended)
- Basic knowledge of terminal commands
- A user with sudo privileges

> [!Caution]
> Directory structures may differ based on your specific setup.

# Step 1: Update and Upgrade Your System

    sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y

# Step 2: Install Required Dependencice 
    
**Install Screen (Session Manager)**

    sudo apt install screen -y

**Install OpenSSH Sever**

This enables secure remote access to your server.

    sudo apt install openssh-server -y

**Install UFW (Uncomplicated Firewall)**

    sudo apt install ufw -y

# Step 3: Configure UFW (Uncomplicated Firewall)

Allow all incoming connections to port 34197:

    sudo ufw allow from any proto udp to any port 34197 comment "Factorio Server Port"

> [!TIP]
 For added security, change "any" to a specific IP address or range.

**Allow SSH Connections Through UFW** (Optional)

    sudo ufw allow from any to any port 22 comment "SSH"

> [!TIP]
> For added security, change "any" to a specific IP address or range.

Set the default rule to deny incoming traffic (Optional)

    sudo ufw default deny incoming

**Enable UFW** (UFW will enable on reboot)

    sudo ufw enable

Check the UFW status after enabling it:

    sudo ufw status
    
--------------------------------------------------------------------------------
# Step 4: Create a Non Sudo User

Replace "*your_username*" with the desired username.

    sudo adduser your_username

> [!NOTE]
> This will prompt you through the setup

**Reboot the system**

    sudo reboot

-------------------------------------------------------------------------------
# Step 5: Download the Factorio Dedicated Server Files & Set-Up

**Log in to your server with the new user account through cmd, PowerShell, PuTTY, etc. Use your preferred terminal emulator.**

**Make a Server Directory. Replace *server_dir_name* with the name you want**

    mkdir -p server_dir_name/factorio

**Make a Downloads Directory. You can replace *Downloads* with any name you want.**

    mkdir Downloads

**Download The server Files**

    wget -v -O ~/Downloads/factorio-headless_linux$(date +%Y-%m-%d).tar.xz https://factorio.com/get-download/stable/headless/linux64

**Copy The file in the Downloads Directory to The Server Directory**

    cp ~/Downloads/the_server_file ~/server_dir_name

**Extract the file into the Factorio Server directory**

    tar -xvf server_dir_name/factorio the_zip_in_the_Downloads_dir --strip-comments=1 -C ~/server_dir_name/factorio

**Navigate to the Server Directory. Replace *server_dir_name* with the one you created from above**

    cd ~/server_dir_name





# Step 6: Configure the Server





# Step 7: Create a Startup Script (Optional)

Return to the users home directory

    cd

Create a directory to place you scripts. Change the "*name*" with your desired directory name:

    mkdir name

Change to the new directory. Change the "*name*" with the one you just created:

    cd name

Create a script. Change the "*name.sh*" with your desired script name.

    nano name.sh

Copy and edit the following script:

    #!/bin/bash

    #set -x     # Uncomment to enable debug output. This will show you each command as it’s executed, which can help identify where it fails

    # Log file
    LOGFILE="/path/to/your/logfile.txt"  # Update with your log file path
    DIRPATH="/path/to/your/server" # Update with the directory containing "*name.sh*"

    # Create the log directory if it doesn't exist
    LOGDIR=$(dirname "$LOGFILE")
    mkdir -p "$LOGDIR"

    # Create the log file if it doesn't exist
    touch "$LOGFILE"

    # Function to log messages with date/time
    log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
    }

    # Update PalWorld using steamcmd
    {
            log "Updating PalWorld..."
        if /usr/games/steamcmd +force_install_dir "$DIRPATH" +login anonymous +app_update 2394010 validate +quit; then
            log "Update completed."
        else
            log "Update failed."
        fi

        # Start the PalWorld server
            log "Starting PalWorld server..."
        if /usr/bin/screen -dmS PalWorld "$DIRPATH/PalServer.sh" -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS -PublicLobby 2>> "$LOGFILE"; then
            log "PalWorld server started successfully."
        else
            log "Failed to start PalWorld server."
            exit 1  # Exit if the server fails to start
        fi
    } 2>&1 | tee -a "$LOGFILE"

Make the script executable by the user:

    chmod u+x palworld.sh

# Step 8: Create a Systemd Service (Optional)

Switch to your sudo user that you used at the beginning. Replace "*your_username*" with the actual username.

    su your_username

**Create the service file:**

    sudo nano /etc/systemd/system/PalWorld.service

**Add the following configuration:**

    [Unit]
    Description=Your Application Description
    After=network.target

    [Service]
    Type=simple
    User=youruser         # Replace with the username you created in the beginning
    ExecStart=/path/to/your/executable/startup/script.sh      # Replace with your full script path
    RemainAfterExit=yes
    Restart=on-failure
    RestartSec=5
    StandardOutput=append:/var/log/yourapp.log
    StandardError=append:/var/log/yourapp.log

    [Install]
    WantedBy=multi-user.target

> **Example**
> 
> User=test
> 
> ExecStart=/home/test/scripts/palworld.sh

**Enable and Start the Service**

    sudo systemctl daemon-reload
    sudo systemctl enable PalWorld.service
    sudo systemctl start PalWorld.service

> [!Important]
>  *This systemd service, along with the accompanying script, ensures that your server automatically starts after a reboot and updates itself before launching.*

# Step 9: Hardening (Optional)

Login with the sudo user and edit the sshd_config file

    sudo nano /etc/ssh/sshd_config

Locate the following lines and uncomment them, making the specified edits:

 **#LoginGraceTime 2m**

    LoginGraceTime 1m

 **#PermitRootLogin prohibit-password**

    PermitRootLogin no

 **#MaxSessions 10**

    Max Sessions 4

Reload systemctl & restart sshd.services

    sudo systemctl daemon-reload
    sudo systemctl restart ssh.service

**Example:**

![image](https://github.com/user-attachments/assets/f12f25af-807d-4981-9e53-ebe2ab3d2688)

These are some steps you can take to enhance the security of your SSH service.

# Change Who Can Use the Switch User (su) Command

Make a new group for the su command. Replace "*group_name*" with your desired name for the new group.

    sudo groupadd group_name

> **Example:** *sudo groupadd restrictedsu*

**Edit who can use the *su* command**

Edit the *su* config

    sudo nano /etc/pam.d/su

Edit the following line to restrict su. Replace "*group_name*" with the one you made ealier.

    auth       required   pam_wheel.so group=group_name

> **Example:** *auth       required   pam_wheel.so group=restrictedsu*

**Example:** 

![image](https://github.com/user-attachments/assets/3d3c941b-aadd-4bdb-b736-e2fb4c7b5c8b)


**Conclusion**

You have successfully set up your Palworld server! For further customization, refer to the game’s official documentation.


**References**
- https://www.factorio.com/download
- https://wiki.factorio.com/Multiplayer
- https://www.digitalocean.com/community/tutorials/ufw-essentials-common-firewall-rules-and-commands
