![Build Status](https://img.shields.io/badge/Dedicated_Server-Linux-green)
![Factorio](https://img.shields.io/badge/Factorio-8A2BE2)
# Factorio Linux Server Setup Guide

**Overview**

This is a step-by-step guide on how to set up and run an Ubuntu Factorio headless dedicated server, including a hardened backup/update/start pipeline, a graceful stop that verifies the world was saved, an automated update checker, a root maintenance script, and a systemd unit that tracks the real game process.

**Prerequisites**

- Ubuntu server (20.04 or higher recommended)
- Basic knowledge of terminal commands
- A user with sudo privileges

> [!Caution]
> Directory structures may differ based on your specific setup. The scripts below assume the server user is `Your_Username`, the install directory is `/home/Your_Username/factorio`, the save is `MyWorld.zip` and the port is `34197` (Factorio's default). Change those values at the top of each script to match your own setup.

> [!Note]
> Factorio is **not** distributed through SteamCMD. The headless server is downloaded directly from factorio.com, and there is no free Steam server app (Steam app 427520 is the paid game). The scripts here use the official version API (`https://factorio.com/api/latest-releases`) and the official download URL instead.

--------------------------------------------------------------------------------
# Step 1: Update and Upgrade Your System

    sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y

--------------------------------------------------------------------------------
# Step 2: Install Required Dependencies

**Install Screen (Session Manager), JSON/transfer tools and xz**

    sudo apt install screen jq rsync curl xz-utils -y

> [!Important]
> `jq` and `rsync` are required by the start script. `jq` reads the installed version and the version API. `rsync` swaps in a new version cleanly during an update. The start script checks for every dependency and tells you which one is missing.

**Install OpenSSH Server**

    sudo apt install openssh-server -y

**Install UFW (Uncomplicated Firewall)**

    sudo apt install ufw -y

--------------------------------------------------------------------------------
# Step 3: Configure UFW (Uncomplicated Firewall)

Allow incoming connections to the game port (Factorio uses UDP):

    sudo ufw allow from any proto udp to any port 34197 comment "Factorio Server Port"

**Allow SSH Connections Through UFW** (Optional)

    sudo ufw allow from any to any port 22 comment "SSH"

Set the default rule to deny incoming traffic (Optional)

    sudo ufw default deny incoming

**Enable UFW**

    sudo ufw enable
    sudo ufw status

--------------------------------------------------------------------------------
# Step 4: Create a Non Sudo User

    sudo adduser Your_Username
    sudo reboot

--------------------------------------------------------------------------------
# Step 5: Install the Factorio Headless Server

Log in as the new user, then download and extract the current stable headless build:

    mkdir -p ~/factorio ~/.downloads
    curl -fSL -o ~/.downloads/factorio-headless.tar.xz https://factorio.com/get-download/stable/headless/linux64
    xz -t ~/.downloads/factorio-headless.tar.xz
    tar -xf ~/.downloads/factorio-headless.tar.xz --strip-components=1 -C ~/factorio
    rm ~/.downloads/factorio-headless.tar.xz

Confirm the installed version:

    cat ~/factorio/data/base/info.json | grep '"version"'

--------------------------------------------------------------------------------
# Step 6: First Run and Configuration

**Create the world**

    cd ~/factorio
    ./bin/x64/factorio --create saves/MyWorld.zip

**Create the server settings file**

    cp data/server-settings.example.json data/server-settings.json
    nano data/server-settings.json

Set at least the server name, description, visibility, and any game password or admin list you want.

**Test run**

    ./bin/x64/factorio --start-server saves/MyWorld.zip --server-settings data/server-settings.json --port 34197

Wait until the console shows the server is hosting the game, then stop it with `Ctrl+C`.

> [!Important]
> Edit `server-settings.json` while the server is **off**. A running server can overwrite it on exit.

> [!Note]
> Put any mods in `~/factorio/mods/`. The routine backup includes the save and the small config. The pre-update backup also includes `mods/`.

--------------------------------------------------------------------------------
# Step 7: Create the Start Script

    cd
    mkdir -p .scripts .logs .backups .downloads .run .flock .screen
    chmod 700 .screen
    cd .scripts
    nano start_server.sh

Copy and edit the following. The variables at the top (`SERVER_PORT`, `SAVE_FILE`, `FACTORIO_DIR`) are the only things you should need to change:

    #!/bin/bash
    set -o pipefail

    #set -x     # Uncomment to enable debug output.

    INSTANCE_NAME="Factorio_Server"
    SERVER_PORT="34197"
    FACTORIO_DIR="/home/Your_Username/factorio"
    SAVE_FILE="$FACTORIO_DIR/saves/MyWorld.zip"
    SERVER_SETTINGS="$FACTORIO_DIR/data/server-settings.json"
    BACKUP_DIR="/home/Your_Username/.backups"
    DOWNLOAD_DIR="/home/Your_Username/.downloads"
    TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
    LOG_DIR="/home/Your_Username/.logs/Start_Server"
    LOGFILE="$LOG_DIR/factorio_$TIMESTAMP.log"
    PID_DIR="/home/Your_Username/.run"
    PID_FILE="$PID_DIR/factorio.pid"
    LOCK_DIR="/home/Your_Username/.flock"
    LOCK_FILE="$LOCK_DIR/start_server.lock"
    # Admin creates this file to approve an update that changes the major.minor
    # series (for example 2.0.x -> 2.1.x). It is deleted after a successful install.
    ALLOW_MAJOR_FILE="$PID_DIR/allow_major_update"
    GAME_PROCESS_NAME="factorio"
    VERSION_API="https://factorio.com/api/latest-releases"
    DOWNLOAD_URL_BASE="https://factorio.com/get-download"
    MIN_FREE_PERCENT=20
    PID_WAIT_MAX=60       # seconds to wait for the factorio process to appear
    PORT_WAIT_MAX=300     # seconds to wait for the game port (large saves load slowly)

    export SCREENDIR="/home/Your_Username/.screen"

    mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$DOWNLOAD_DIR" "$PID_DIR" "$LOCK_DIR"

    # --- SELF-LOCK: prevent overlapping invocations from racing the duplicate check ---
    # fd 200 is closed for the game launch below so the long-running game never holds this lock.
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Another instance of start_server.sh is already running (lock held). Exiting cleanly."
        exit 0
    fi

    log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    }

    game_pid() {
        pgrep -u "$(id -u)" -x "$GAME_PROCESS_NAME" | head -n1
    }

    port_listening() {
        ss -H -lun "sport = :$SERVER_PORT" 2>/dev/null | grep -q .
    }

    installed_version() {
        jq -r '.version // empty' "$FACTORIO_DIR/data/base/info.json" 2>/dev/null
    }

    latest_version() {
        curl -fsS --max-time 20 --retry 2 "$VERSION_API" 2>/dev/null | jq -r '.stable.headless // empty' 2>/dev/null
    }

    valid_version() {
        [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
    }

    # true when $1 is strictly newer than $2
    version_gt() {
        [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
    }

    series() {
        echo "$1" | cut -d. -f1-2
    }

    get_used_percent() {
        df --output=pcent "$BACKUP_DIR" | tail -n1 | tr -dc '0-9'
    }

    dump_game_log() {
        if [ -f "$FACTORIO_DIR/factorio-current.log" ]; then
            log "Last lines of factorio-current.log:"
            tail -n 15 "$FACTORIO_DIR/factorio-current.log"
        fi
    }

    # make_backup <label> <item>...   (items are relative to $FACTORIO_DIR; missing ones are skipped)
    make_backup() {
        local label="$1"; shift
        local items=() item
        for item in "$@"; do
            [ -e "$FACTORIO_DIR/$item" ] && items+=("$item")
        done
        if [ ${#items[@]} -eq 0 ]; then
            log "Warning: nothing to back up for '$label'."
            return 1
        fi
        ( umask 077; tar -czf "$BACKUP_DIR/factorioserver_${label}_$TIMESTAMP.tar.gz" -C "$FACTORIO_DIR" "${items[@]}" )
    }

    # Download, verify and install Factorio headless <version>.
    # Returns 0 = installed and verified, 2 = failed before touching the install (safe), 1 = failed mid-install.
    install_update() {
        local target="$1" work archive staged staged_version
        work=$(mktemp -d -p "$DOWNLOAD_DIR" "update-${target}.XXXXXX") || { log "Warning: could not create a staging directory."; return 2; }
        archive="$work/factorio-headless_linux_${target}.tar.xz"
        staged="$work/staged"

        log "Downloading Factorio headless $target..."
        if ! curl -fSL --retry 3 --retry-delay 10 --max-time 1200 -o "$archive" "$DOWNLOAD_URL_BASE/$target/headless/linux64"; then
            log "Warning: download failed."
            rm -rf "$work"; return 2
        fi
        if ! xz -t "$archive"; then
            log "Warning: downloaded archive failed its integrity test."
            rm -rf "$work"; return 2
        fi
        mkdir -p "$staged"
        if ! tar -xf "$archive" --strip-components=1 -C "$staged"; then
            log "Warning: extraction failed."
            rm -rf "$work"; return 2
        fi
        staged_version=$(jq -r '.version // empty' "$staged/data/base/info.json" 2>/dev/null)
        if [ "$staged_version" != "$target" ] || [ ! -x "$staged/bin/x64/factorio" ]; then
            log "Warning: staged build reports version '${staged_version:-none}', expected '$target' (or binary missing)."
            rm -rf "$work"; return 2
        fi

        log "Archive verified (version $staged_version). Installing into $FACTORIO_DIR..."
        # Only the game's own directories are replaced. saves/, mods/, config/ and the
        # admin-managed data/*.json files (server-settings.json etc.) are never touched.
        if ! rsync -a --checksum --delete "$staged/bin/" "$FACTORIO_DIR/bin/"; then
            log "Critical Error: failed while replacing bin/."
            return 1
        fi
        if ! rsync -a --checksum --delete --exclude='/*.json' "$staged/data/" "$FACTORIO_DIR/data/"; then
            log "Critical Error: failed while replacing data/."
            return 1
        fi
        local f
        for f in config-path.cfg README.txt; do
            [ -f "$staged/$f" ] && cp -f "$staged/$f" "$FACTORIO_DIR/$f"
        done
        rm -rf "$work"

        if [ "$(installed_version)" != "$target" ]; then
            log "Critical Error: after install the version on disk is '$(installed_version)', expected '$target'."
            return 1
        fi
        return 0
    }

    # Run the backup, update, and start block
    {
        # --- STEP -1: REQUIRED COMMANDS ---
        MISSING_DEPS=""
        for dep in jq rsync curl xz ss screen pgrep; do
            command -v "$dep" >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS $dep"
        done
        if [ -n "$MISSING_DEPS" ]; then
            log "Critical Error: required command(s) not installed:$MISSING_DEPS"
            log "Install with: sudo apt install -y jq rsync curl xz-utils screen iproute2"
            exit 1
        fi

        # --- STEP 0: DUPLICATE SCREEN SESSION PROTECTION ---
        screen -wipe >/dev/null 2>&1     # drop dead sockets left by a crash so they don't look like a live session
        if /usr/bin/screen -list | grep -q "\.${INSTANCE_NAME}[[:space:]]"; then
            log "'${INSTANCE_NAME}' is already running in an active Screen session. Nothing to do."
            LIVE_PID=$(game_pid)
            if [ -n "$LIVE_PID" ] && [ "$(cat "$PID_FILE" 2>/dev/null)" != "$LIVE_PID" ]; then
                echo "$LIVE_PID" > "$PID_FILE"
                log "Rewrote stale PID file to match the running process ($LIVE_PID)."
            fi
            exit 0
        fi

        # --- STEP 1: BACKUP & ROTATION ---
        log "Initiating pre-start Factorio backup (world save, settings)..."
        BACKUP_OK=0
        if make_backup routine "saves/$(basename "$SAVE_FILE")" mods/mod-list.json mods/mod-settings.dat config \
            data/server-settings.json data/map-gen-settings.json data/map-settings.json \
            data/server-adminlist.json data/server-whitelist.json data/server-banlist.json; then
            BACKUP_OK=1
            log "Backup successfully created: factorioserver_routine_$TIMESTAMP.tar.gz"
        else
            log "Warning: Backup failed. Any pending update will be skipped this run."
        fi

        find "$BACKUP_DIR" -name "factorioserver_*.tar.gz" -type f -mtime +30 -exec rm -f {} \;
        log "Backup rotation check complete (30-day cutoff)."

        # Space-aware safety net: if free space is still tight after the 30-day cutoff,
        # keep pruning the oldest backups until there is enough headroom.
        USED_PERCENT=$(get_used_percent)
        FREE_PERCENT=$((100 - ${USED_PERCENT:-0}))
        while [ "$FREE_PERCENT" -lt "$MIN_FREE_PERCENT" ]; do
            OLDEST=$(ls -1t "$BACKUP_DIR"/factorioserver_*.tar.gz 2>/dev/null | tail -n1)
            if [ -z "$OLDEST" ]; then
                log "WARNING: Free space still below ${MIN_FREE_PERCENT}% but no more backups left to prune."
                break
            fi
            log "Free space at ${FREE_PERCENT}% (below ${MIN_FREE_PERCENT}% minimum). Pruning oldest backup: $(basename "$OLDEST")"
            rm -f "$OLDEST"
            USED_PERCENT=$(get_used_percent)
            FREE_PERCENT=$((100 - ${USED_PERCENT:-0}))
        done
        log "Space-aware backup safety check complete (free space: ${FREE_PERCENT}%)."

        find "$LOG_DIR" -name "factorio_*.log" -type f -mtime +30 -exec rm -f {} \;
        log "Log rotation check complete."
        find "$DOWNLOAD_DIR" -mindepth 1 -maxdepth 1 -type d -name 'update-*' -mtime +1 -exec rm -rf {} + 2>/dev/null

        # --- STEP 2: GAME SOFTWARE UPDATE (direct from factorio.com) ---
        INSTALLED_VERSION=$(installed_version)
        if [ -z "$INSTALLED_VERSION" ] || [ ! -x "$FACTORIO_DIR/bin/x64/factorio" ]; then
            [ ! -x "$FACTORIO_DIR/bin/x64/factorio" ] && log "Critical Error: $FACTORIO_DIR/bin/x64/factorio is missing or not executable."
            [ ! -f "$FACTORIO_DIR/data/base/info.json" ] && log "Critical Error: $FACTORIO_DIR/data/base/info.json is missing."
            [ -f "$FACTORIO_DIR/data/base/info.json" ] && log "Critical Error: could not read a version from $FACTORIO_DIR/data/base/info.json: $(head -c 200 "$FACTORIO_DIR/data/base/info.json")"
            exit 1
        fi
        log "Installed Factorio version: $INSTALLED_VERSION"

        LATEST_VERSION=$(latest_version)
        if ! valid_version "$LATEST_VERSION"; then
            log "Warning: could not determine the latest stable version from $VERSION_API. Starting the installed version."
        elif ! version_gt "$LATEST_VERSION" "$INSTALLED_VERSION"; then
            log "Factorio is up to date ($INSTALLED_VERSION; latest stable is $LATEST_VERSION)."
        elif [ "$(series "$LATEST_VERSION")" != "$(series "$INSTALLED_VERSION")" ] && [ ! -f "$ALLOW_MAJOR_FILE" ]; then
            log "Warning: $LATEST_VERSION is a different release series than $INSTALLED_VERSION. NOT installing automatically."
            log "Saves are upgraded one-way and mods may break. To approve: touch $ALLOW_MAJOR_FILE and restart the service."
        elif [ "$BACKUP_OK" != 1 ]; then
            log "Warning: skipping the $INSTALLED_VERSION -> $LATEST_VERSION update because the backup step failed."
        else
            log "Update available: $INSTALLED_VERSION -> $LATEST_VERSION."
            if make_backup "preupdate_${INSTALLED_VERSION}" saves mods config \
                data/server-settings.json data/map-gen-settings.json data/map-settings.json \
                data/server-adminlist.json data/server-whitelist.json data/server-banlist.json; then
                log "Pre-update backup created: factorioserver_preupdate_${INSTALLED_VERSION}_$TIMESTAMP.tar.gz (all saves + mods)."
                install_update "$LATEST_VERSION"
                RC=$?
                if [ "$RC" -eq 0 ]; then
                    log "Update completed successfully ($INSTALLED_VERSION -> $(installed_version))."
                    rm -f "$ALLOW_MAJOR_FILE"
                elif [ "$RC" -eq 2 ]; then
                    log "Warning: update failed before the install was touched. Starting $INSTALLED_VERSION."
                else
                    log "Critical Error: update failed part-way through the install. Aborting start; reinstall $LATEST_VERSION manually."
                    exit 1
                fi
            else
                log "Warning: pre-update backup failed. Skipping the update and starting $INSTALLED_VERSION."
            fi
        fi

        # --- STEP 3: START APPLICATION WINDOW ---
        if [ ! -f "$SAVE_FILE" ]; then
            log "Critical Error: save file not found at $SAVE_FILE."
            exit 1
        fi
        if [ ! -f "$SERVER_SETTINGS" ]; then
            log "Critical Error: server settings not found at $SERVER_SETTINGS."
            exit 1
        fi

        log "Starting Factorio $(installed_version) inside Screen session on port $SERVER_PORT..."
        /usr/bin/screen -dmS "$INSTANCE_NAME" "$FACTORIO_DIR/bin/x64/factorio" \
            --start-server "$SAVE_FILE" --server-settings "$SERVER_SETTINGS" --port "$SERVER_PORT" 200>&-

        sleep 5

        if /usr/bin/screen -list | grep -q "\.${INSTANCE_NAME}[[:space:]]"; then
            log "Screen session is alive. Verifying the actual game process next..."
        else
            log "Critical Error: Failed to start Factorio screen session (the game exited immediately)."
            dump_game_log
            exit 1
        fi

        # --- STEP 3.5: CAPTURE THE ACTUAL GAME PROCESS PID, THEN WAIT FOR THE GAME PORT ---
        log "Waiting for $GAME_PROCESS_NAME to appear so we can confirm the server actually started..."
        PID_WAIT_COUNT=0
        GAME_PID=""
        while [ -z "$GAME_PID" ] && [ $PID_WAIT_COUNT -lt $PID_WAIT_MAX ]; do
            GAME_PID=$(game_pid)
            if [ -z "$GAME_PID" ]; then
                sleep 1
                ((PID_WAIT_COUNT++))
            fi
        done

        if [ -z "$GAME_PID" ]; then
            log "Critical Error: Screen session is up, but $GAME_PROCESS_NAME never appeared after ${PID_WAIT_MAX}s."
            dump_game_log
            exit 1
        fi
        echo "$GAME_PID" > "$PID_FILE"

        PORT_WAIT_COUNT=0
        while ! port_listening && [ $PORT_WAIT_COUNT -lt $PORT_WAIT_MAX ]; do
            if [ -z "$(game_pid)" ]; then
                log "Critical Error: $GAME_PROCESS_NAME exited while loading the save (bad save, mod, or settings)."
                dump_game_log
                exit 1
            fi
            sleep 2
            PORT_WAIT_COUNT=$((PORT_WAIT_COUNT + 2))
        done

        if port_listening; then
            log "Factorio server started successfully in background (PID $GAME_PID), listening on UDP $SERVER_PORT."
        else
            log "WARNING: process $GAME_PID is running but UDP $SERVER_PORT did not open within ${PORT_WAIT_MAX}s (still loading a large save?). Leaving it running."
        fi
        exit 0
    } 2>&1 | tee -a "$LOGFILE"

Make it executable:

    chmod u+x start_server.sh

**What the start script does, in order**

1. Checks that every required tool is installed.
2. Takes a self-lock so two copies cannot launch at once.
3. Exits cleanly if the server is already running.
4. Takes a routine backup, rotates backups older than 30 days, and prunes extra backups if free space is low.
5. Compares the installed version with the latest stable release. If a newer release is in the **same** `X.Y` series, it downloads, verifies and installs it, taking a full backup of saves and mods first.
6. Starts Factorio inside a detached screen session, waits for the process, writes the PID file, and waits for the UDP port to open.

> [!Important]
> **Release-series guard.** An update that changes the `X.Y` series (for example 2.1 to 2.2) is never applied automatically, because major releases can break mods and saves. When you are ready, run `touch /home/Your_Username/.run/allow_major_update` and the next start installs it.

> [!Note]
> If the version API or the download is unreachable, the script starts the existing install instead of failing.

**Attach to the console**

    export SCREENDIR=/home/Your_Username/.screen
    screen -ls
    screen -r Factorio_Server

Press `Ctrl+A` then `D` to leave without stopping the server. To make the `SCREENDIR` setting permanent:

    echo 'export SCREENDIR=/home/Your_Username/.screen' >> ~/.bashrc

--------------------------------------------------------------------------------
# Step 8: Create the Stop Script

Factorio has a console, so the stop script can warn players and save the world before it exits.

    nano stop_server.sh

Copy and edit the following:

    #!/bin/bash
    set -o pipefail

    #set -x     # Uncomment to enable debug output.

    INSTANCE_NAME="Factorio_Server"
    GAME_PROCESS_NAME="factorio"
    FACTORIO_DIR="/home/Your_Username/factorio"
    SAVE_FILE="$FACTORIO_DIR/saves/MyWorld.zip"
    TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
    LOG_DIR="/home/Your_Username/.logs/Stop_Server"
    LOGFILE="$LOG_DIR/factorio_stop_$TIMESTAMP.log"
    PID_FILE="/home/Your_Username/.run/factorio.pid"
    SAVE_CONFIRM_MAX=60    # seconds to wait for the /save to land on disk
    EXIT_WAIT_MAX=120      # seconds to wait for the process to exit after SIGINT

    # Crucial: use the isolated screen directory so all session lookups and console
    # input target the same sockets the systemd unit created.
    export SCREENDIR="/home/Your_Username/.screen"

    mkdir -p "$LOG_DIR"

    log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    }

    game_pid() {
        pgrep -u "$(id -u)" -x "$GAME_PROCESS_NAME" | head -n1
    }

    # Type a line into the server console (plain text = chat message, /command = command)
    send_console() {
        /usr/bin/screen -S "$INSTANCE_NAME" -X stuff "$1"$'\n'
    }

    save_mtime() {
        stat -c %Y "$SAVE_FILE" 2>/dev/null || echo 0
    }

    {
        find "$LOG_DIR" -name "factorio_stop_*.log" -type f -mtime +30 -exec rm -f {} \;
        log "Stop log rotation check complete."

        screen -wipe >/dev/null 2>&1
        SESSION_UP=0
        if /usr/bin/screen -list | grep -q "\.${INSTANCE_NAME}[[:space:]]"; then
            SESSION_UP=1
        fi
        SERVER_PID=$(game_pid)

        if [ "$SESSION_UP" = 1 ]; then
            log "Active Factorio session discovered. Initializing graceful countdown..."

            send_console "Server shutting down in 5 minutes! Please finish up and log out."
            sleep 120
            send_console "Server shutting down in 3 minutes! Find a safe spot."
            sleep 120
            send_console "Server shutting down in 60 seconds! Please log out."
            sleep 30
            send_console "Server shutting down in 30 seconds!"
            sleep 25

            MTIME_BEFORE=$(save_mtime)
            log "Saving the world via the server console..."
            send_console "Saving world state..."
            send_console "/save"

            WAITED=0
            while [ "$(save_mtime)" -le "$MTIME_BEFORE" ] && [ $WAITED -lt $SAVE_CONFIRM_MAX ]; do
                sleep 2
                WAITED=$((WAITED + 2))
            done
            if [ "$(save_mtime)" -gt "$MTIME_BEFORE" ]; then
                log "Console /save confirmed: save file updated after ${WAITED}s."
            else
                log "WARNING: save file did not change within ${SAVE_CONFIRM_MAX}s of /save. Relying on the shutdown save."
            fi
        elif [ -n "$SERVER_PID" ]; then
            log "WARNING: $GAME_PROCESS_NAME (PID $SERVER_PID) is running but has no screen session, so no countdown can be broadcast. Going straight to SIGINT."
            MTIME_BEFORE=$(save_mtime)
        else
            log "No active server found. Lifecycle step skipped."
            [ -f "$PID_FILE" ] && rm -f "$PID_FILE" && log "Removed stale PID file."
            exit 0
        fi

        # --- ASK THE PROCESS TO EXIT, THEN VERIFY IT ACTUALLY DID ---
        SERVER_PID=$(game_pid)
        if [ -n "$SERVER_PID" ]; then
            log "Sending SIGINT to PID $SERVER_PID..."
            kill -INT "$SERVER_PID"

            WAITED=0
            while kill -0 "$SERVER_PID" 2>/dev/null && [ $WAITED -lt $EXIT_WAIT_MAX ]; do
                sleep 2
                WAITED=$((WAITED + 2))
            done

            if kill -0 "$SERVER_PID" 2>/dev/null; then
                log "Still running ${WAITED}s after SIGINT. Force killing as last resort (possible data loss)."
                kill -9 "$SERVER_PID"
                sleep 2
            else
                log "Process exited cleanly after SIGINT (${WAITED}s)."
            fi
        else
            log "Process already gone after the console save."
        fi

        MTIME_AFTER=$(save_mtime)
        if [ "$MTIME_AFTER" -gt "$MTIME_BEFORE" ]; then
            log "World save verified: $(basename "$SAVE_FILE") last written $(date -d "@$MTIME_AFTER" '+%Y-%m-%d %H:%M:%S')."
        else
            log "WARNING: $(basename "$SAVE_FILE") was not updated during this shutdown. Check factorio-current.log."
        fi

        # --- CLEAN UP ---
        screen -wipe >/dev/null 2>&1
        if /usr/bin/screen -list | grep -q "\.${INSTANCE_NAME}[[:space:]]"; then
            log "Screen session still present. Force closing."
            /usr/bin/screen -S "$INSTANCE_NAME" -X quit
        fi

        if [ -f "$PID_FILE" ]; then
            rm -f "$PID_FILE"
            log "Removed stale PID file."
        fi

        log "Factorio engine instance safely terminated."
    } 2>&1 | tee -a "$LOGFILE"

Make it executable:

    chmod u+x stop_server.sh

**What the stop script does**

1. Warns players in chat with a countdown (5 minutes, 3 minutes, 60 seconds, 30 seconds).
2. Sends `/save` to the console and confirms the save file's modification time changed.
3. Sends `SIGINT` for a clean exit and waits up to 120 seconds.
4. Falls back to `SIGKILL` only as a last resort, then verifies the save, sweeps leftover screen sessions, and removes the PID file.

--------------------------------------------------------------------------------
# Step 9: Create an Automated Update Checker (Optional)

    nano update_checker.sh

Copy and edit the following, updating `WEBHOOK_URL` (optional) to match your setup:

    #!/bin/bash
    set -o pipefail

    GAME_NAME="Factorio"
    SERVER_PORT="34197"
    FACTORIO_DIR="/home/Your_Username/factorio"
    STOP_SCRIPT="/home/Your_Username/.scripts/stop_server.sh"
    GAME_PROCESS_NAME="factorio"
    VERSION_API="https://factorio.com/api/latest-releases"
    RESTART_WAIT_MAX=900     # seconds to wait for systemd to bring the server back (RestartSec + install + load)
    TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
    LOG_DIR="/home/Your_Username/.logs/Update_Checker"
    LOG_FILE="factorio_update_$TIMESTAMP.log"
    RUN_DIR="/home/Your_Username/.run"
    WEBHOOK_URL=""    # paste your Discord webhook URL here (optional)
    IMAGE_URL=""      # optional image for the "Maintenance Started" embed
    DISCORD_FOOTER="Server Maintenance Automation"

    export SCREENDIR="/home/Your_Username/.screen"

    # ==============================================================================
    #                 AUTOMATED ENGINE EXECUTION LOGIC (DO NOT EDIT)
    # ==============================================================================
    FULL_LOG_PATH="$LOG_DIR/$LOG_FILE"
    # If this file exists the checker refuses to stop the server. It is created when an
    # update did not apply after a restart. Clear it with: rm "$BLOCK_FLAG"
    BLOCK_FLAG="$RUN_DIR/update_checker_blocked"
    # Admin approval for a different release series (see start_server.sh)
    ALLOW_MAJOR_FILE="$RUN_DIR/allow_major_update"
    # Remembers which version we already announced as "needs manual approval"
    NOTIFIED_FILE="$RUN_DIR/major_update_notified"

    mkdir -p "$LOG_DIR" "$RUN_DIR"

    log() {
        echo "$1"
    }

    send_discord_message() {
        local message="$1"
        local emoji="🛠️"

        if [[ "$message" == *"No updates found"* ]]; then
            emoji="🛠️ ℹ️"
        elif [[ "$message" == *"Maintenance Complete"* ]]; then
            emoji="🛠️ 🔄"
        elif [[ "$message" == *"Updates Found"* ]]; then
            emoji="🛠️ ✅"
        elif [[ "$message" == *"Maintenance Failed"* ]]; then
            emoji="🛠️ ❌"
        fi

        [[ -n "$WEBHOOK_URL" ]] || return 0

        local image=""
        [[ "$message" == *"Maintenance Started"* ]] && image="$IMAGE_URL"

        local json_payload
        json_payload=$(jq -n --arg t "$emoji $message" --arg f "$DISCORD_FOOTER" --arg img "$image" \
            '{embeds: [ ({title: $t, color: 16711680, footer: {text: $f}} + (if $img != "" then {image: {url: $img}} else {} end)) ]}')
        curl -s -H "Content-Type: application/json" -X POST -d "$json_payload" "$WEBHOOK_URL" > /dev/null 2>&1
    }

    game_pid() {
        pgrep -u "$(id -u)" -x "$GAME_PROCESS_NAME" | head -n1
    }

    port_listening() {
        ss -H -lun "sport = :$SERVER_PORT" 2>/dev/null | grep -q .
    }

    installed_version() {
        jq -r '.version // empty' "$FACTORIO_DIR/data/base/info.json" 2>/dev/null
    }

    latest_version() {
        curl -fsS --max-time 20 --retry 2 "$VERSION_API" 2>/dev/null | jq -r '.stable.headless // empty' 2>/dev/null
    }

    valid_version() {
        [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
    }

    # true when $1 is strictly newer than $2
    version_gt() {
        [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
    }

    series() {
        echo "$1" | cut -d. -f1-2
    }

    {
        # --- STEP -1: REQUIRED COMMANDS ---
        MISSING_DEPS=""
        for dep in jq curl ss pgrep; do
            command -v "$dep" >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS $dep"
        done
        if [ -n "$MISSING_DEPS" ]; then
            log "Critical Error: required command(s) not installed:$MISSING_DEPS"
            log "Install with: sudo apt install -y jq rsync curl xz-utils screen iproute2"
            exit 1
        fi

        # --- STEP 0: LOG ROTATION ---
        find "$LOG_DIR" -name "factorio_update_*.log" -type f -mtime +3 -exec rm -f {} \;
        log "$(date '+%Y-%m-%d %H:%M:%S') - Update-checker log rotation check complete."

        # --- STEP 1: HONOR THE SAFETY BLOCK ---
        if [ -f "$BLOCK_FLAG" ]; then
            log "$(date '+%Y-%m-%d %H:%M:%S') - Checker is BLOCKED by $BLOCK_FLAG (a previous update did not apply). Not touching the server."
            log "Reason recorded: $(head -c 300 "$BLOCK_FLAG")"
            log "Investigate, then run: rm $BLOCK_FLAG"
            exit 0
        fi

        # --- STEP 2: INSTALLED VERSION FROM THE GAME'S OWN METADATA ---
        INSTALLED_VERSION=$(installed_version)
        if [ -z "$INSTALLED_VERSION" ]; then
            log "$(date '+%Y-%m-%d %H:%M:%S') - CRITICAL ERROR: cannot read the installed version from $FACTORIO_DIR/data/base/info.json (file missing or unreadable)."
            log "A systemic issue may be present. Aborting execution lifecycle to protect server integrity."
            exit 1
        fi
        log "$(date '+%Y-%m-%d %H:%M:%S') - Installed version: $INSTALLED_VERSION"

        # --- STEP 3: LATEST STABLE VERSION FROM FACTORIO.COM ---
        LATEST_VERSION=$(latest_version)
        if ! valid_version "$LATEST_VERSION"; then
            log "$(date '+%Y-%m-%d %H:%M:%S') - Error: version API query failed or returned an unexpected value ('$LATEST_VERSION'). Skipping check."
            exit 1
        fi
        log "$(date '+%Y-%m-%d %H:%M:%S') - Latest stable version: $LATEST_VERSION"

        # --- STEP 4: COMPARE ---
        if ! version_gt "$LATEST_VERSION" "$INSTALLED_VERSION"; then
            log "$(date '+%Y-%m-%d %H:%M:%S') - $GAME_NAME is fully up to date."
            exit 0
        fi

        # A different release series (e.g. 2.0 -> 2.1) upgrades saves one-way and can break
        # mods, so it needs an admin's explicit approval instead of a surprise 3 AM restart.
        if [ "$(series "$LATEST_VERSION")" != "$(series "$INSTALLED_VERSION")" ] && [ ! -f "$ALLOW_MAJOR_FILE" ]; then
            log "$(date '+%Y-%m-%d %H:%M:%S') - $LATEST_VERSION is a new release series (installed: $INSTALLED_VERSION). Manual approval required."
            log "To approve: touch $ALLOW_MAJOR_FILE   (the next cycle will then update)."
            if [ "$(cat "$NOTIFIED_FILE" 2>/dev/null)" != "$LATEST_VERSION" ]; then
                send_discord_message "Maintenance Failed: $GAME_NAME $LATEST_VERSION is a new release series (installed $INSTALLED_VERSION). Manual approval required; no action taken."
                echo "$LATEST_VERSION" > "$NOTIFIED_FILE"
            fi
            exit 0
        fi

        log "=============================================================================="
        log "$(date '+%Y-%m-%d %H:%M:%S') --- STARTING ROOT SYSTEM MAINTENANCE [$GAME_NAME] ---"
        log "Update detected: $INSTALLED_VERSION -> $LATEST_VERSION"

        send_discord_message "Maintenance Started: Updates Found on factorio.com for $GAME_NAME. Initializing patching pipeline."

        log "$(date '+%Y-%m-%d %H:%M:%S') Executing established graceful shutdown script..."
        bash "$STOP_SCRIPT"

        # systemd (Restart=always) restarts the service; start_server.sh installs the new version.
        log "$(date '+%Y-%m-%d %H:%M:%S') Server process terminated. Waiting for systemd auto-restart to bring it back..."

        WAITED=0
        SERVER_UP=0
        while [ $WAITED -lt $RESTART_WAIT_MAX ]; do
            if [ -n "$(game_pid)" ] && port_listening; then
                SERVER_UP=1
                break
            fi
            if (( WAITED % 60 == 0 )); then
                log "$(date '+%Y-%m-%d %H:%M:%S') Still waiting for systemd auto-restart... (${WAITED}s elapsed)"
            fi
            sleep 5
            WAITED=$((WAITED + 5))
        done

        if [ "$SERVER_UP" != 1 ]; then
            # No manual fallback start: launching the game from here would put it outside
            # systemd's control. Systemd keeps retrying until StartLimitBurst; if that trips,
            # an admin needs to run: sudo systemctl reset-failed Factorio && sudo systemctl start Factorio
            log "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $GAME_NAME did not come back within ${RESTART_WAIT_MAX}s."
            send_discord_message "Maintenance Failed: Systemd auto-restart did not bring $GAME_NAME back within $((RESTART_WAIT_MAX / 60)) minutes. Server may be DOWN; admin intervention required."
            exit 1
        fi
        log "$(date '+%Y-%m-%d %H:%M:%S') Server back online after ${WAITED}s."

        # --- STEP 5: VERIFY THE UPDATE ACTUALLY LANDED ---
        NEW_VERSION=$(installed_version)
        if [ "$NEW_VERSION" != "$LATEST_VERSION" ]; then
            log "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Update did NOT apply. Installed version is '$NEW_VERSION', expected '$LATEST_VERSION'."
            {
                echo "$(date '+%Y-%m-%d %H:%M:%S') update did not apply after restart: installed '$NEW_VERSION', expected '$LATEST_VERSION'"
            } > "$BLOCK_FLAG"
            log "Checker blocked via $BLOCK_FLAG so it cannot restart the server in a loop."
            send_discord_message "Maintenance Failed: $GAME_NAME update to $LATEST_VERSION did not apply (still $NEW_VERSION). Auto-updates paused until an admin clears the block."
            exit 1
        fi

        send_discord_message "Maintenance Complete: $GAME_NAME updated to $NEW_VERSION and back online."
        log "$(date '+%Y-%m-%d %H:%M:%S') --- MAINTENANCE SEQUENCE COMPLETE ---"

    } 2>&1 | tee -a "$FULL_LOG_PATH"

Make it executable, then schedule it (every 30 minutes below):

    chmod u+x update_checker.sh
    crontab -e

Add:

    */30 * * * * flock -n /home/Your_Username/.flock/update_checker.lock /home/Your_Username/.scripts/update_checker.sh

**How it behaves**

- It compares the installed version with the latest stable release.
- For a same-series update it runs the stop script, waits for systemd to restart the server (the start script installs the update), then confirms the installed version now matches. It never starts the server by hand, so the systemd unit stays the single owner of the process.
- For a new release series it sends a one-time Discord notice and does nothing else until you create `allow_major_update`.
- If an update does not apply, it writes `/home/Your_Username/.run/update_checker_blocked` and alerts you so a bad update cannot restart the server every 30 minutes. After you have looked at the cause, clear it:

        rm /home/Your_Username/.run/update_checker_blocked

--------------------------------------------------------------------------------
# Step 10: Create a Systemd Service

    sudo nano /etc/systemd/system/Factorio.service

Copy the following (already includes the hardening):

    [Unit]
    Description=Factorio Dedicated Game Server (MyWorld)
    After=network.target network-online.target
    Wants=network-online.target
    StartLimitIntervalSec=1800
    StartLimitBurst=3

    [Service]
    Type=forking
    User=Your_Username
    Group=Your_Username
    WorkingDirectory=/home/Your_Username
    ExecStart=/home/Your_Username/.scripts/start_server.sh
    ExecStop=/home/Your_Username/.scripts/stop_server.sh
    PIDFile=/home/Your_Username/.run/factorio.pid
    KillMode=control-group
    SendSIGKILL=no
    TimeoutStartSec=900
    TimeoutStopSec=540
    RemainAfterExit=no
    Restart=always
    RestartSec=60
    StandardOutput=journal
    StandardError=journal
    Environment="SCREENDIR=/home/Your_Username/.screen"

    # '+' = run outside the sandbox below. REQUIRED: the sandbox itself needs these
    # directories to exist (otherwise 217/USER or 226/NAMESPACE), and `install -d`
    # creates them owned by the game user rather than root.
    ExecStartPre=+/usr/bin/install -d -o Your_Username -g Your_Username -m 0755 /home/Your_Username/.run /home/Your_Username/.flock /home/Your_Username/.logs /home/Your_Username/.backups /home/Your_Username/.downloads
    ExecStartPre=+/usr/bin/install -d -o Your_Username -g Your_Username -m 0700 /home/Your_Username/.screen

    NoNewPrivileges=true
    PrivateTmp=true
    ProtectSystem=strict
    ProtectHome=read-only
    ReadWritePaths=/home/Your_Username/factorio
    ReadWritePaths=/home/Your_Username/.run
    ReadWritePaths=/home/Your_Username/.flock
    ReadWritePaths=/home/Your_Username/.screen
    ReadWritePaths=/home/Your_Username/.logs
    ReadWritePaths=/home/Your_Username/.backups
    ReadWritePaths=/home/Your_Username/.downloads

    [Install]
    WantedBy=multi-user.target

> [!Important]
> `Restart=always`, not `on-failure`. A `SIGINT` shutdown is not counted as a failure by `on-failure`, so auto-restart could be silently skipped.

> [!Important]
> `+` on `ExecStartPre=` is required. Without it the setup commands run inside the same sandbox as the main process and fail with `status=217/USER` or `226/NAMESPACE`. The directories listed in `ReadWritePaths` must exist, which is exactly what those lines guarantee.

> [!Note]
> `TimeoutStopSec=540` covers the full stop script (5 minute countdown plus save and exit). `StartLimitIntervalSec=1800` must be longer than `TimeoutStartSec=900`, or the retry limit never triggers.

**Lock down the scripts** (files before directory, because your own shell expands `*.sh` before `sudo` runs):

    sudo chown root:Your_Username /home/Your_Username/.scripts/*.sh
    sudo chmod 750 /home/Your_Username/.scripts/*.sh
    sudo chown root:Your_Username /home/Your_Username/.scripts
    sudo chmod 750 /home/Your_Username/.scripts

**Enable, start, and confirm:**

    sudo systemctl daemon-reload
    sudo systemctl enable Factorio.service
    sudo systemctl start Factorio.service
    sudo systemctl status Factorio.service
    cat /home/Your_Username/.run/factorio.pid
    sudo systemd-analyze security Factorio.service

You want `active (running)`, a non-zero Main PID, and a screen session visible with `SCREENDIR` exported.

> [!Note]
> A full `sudo systemctl restart Factorio.service` takes about 5.5 minutes because of the stop countdown.

--------------------------------------------------------------------------------
# Step 11: Create the Host-Level Maintenance Script (Optional)

Steps 7-10 handle the *game* lifecycle. This step handles the *host*: applying OS security patches and rebooting on a schedule while cleanly stopping the game first. This needs **root**, so log in as your sudo user.

    sudo nano /usr/local/sbin/factorio_maintenance.sh

Copy and edit the following, updating `WEBHOOK_URL` (optional):

    #!/bin/bash
    # Install as /usr/local/sbin/factorio_maintenance.sh (root). Run from root's crontab, e.g.:
    #   0 6 * * * flock -n /tmp/factorio_maintenance.lock /usr/local/sbin/factorio_maintenance.sh

    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

    # --- CONFIGURATION ---
    LOGFILE="/var/log/factorio_system_maintenance.log"
    SERVICE_NAME="Factorio.service"
    GAME_USER="Your_Username"
    GAME_PROCESS_NAME="factorio"
    WEBHOOK_URL=""    # paste your Discord webhook URL here (optional)
    IMAGE_URL=""      # optional image for the "Maintenance Started" embed

    touch "$LOGFILE"

    log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    }

    send_discord_message() {
        local message="$1"
        local emoji="🛠️"

        if [[ "$message" == *"No updates found"* ]]; then
            emoji="🛠️ ℹ️"
        elif [[ "$message" == *"Maintenance Complete"* ]]; then
            emoji="🛠️ 🔄"
        elif [[ "$message" == *"Updates Found"* ]]; then
            emoji="🛠️ ✅"
        elif [[ "$message" == *"Maintenance Failed"* ]]; then
            emoji="🛠️ ❌"
        fi

        [[ -n "$WEBHOOK_URL" ]] || return 0

        local image=""
        [[ "$message" == *"Maintenance Started"* ]] && image="$IMAGE_URL"

        local json_payload
        json_payload=$(jq -n --arg t "$emoji $message" --arg f "Factorio Host System Maintenance Automation" --arg img "$image" \
            '{embeds: [ ({title: $t, color: 16711680, footer: {text: $f}} + (if $img != "" then {image: {url: $img}} else {} end)) ]}')
        curl -s -H "Content-Type: application/json" -X POST -d "$json_payload" "$WEBHOOK_URL" > /dev/null 2>&1
    }

    # --- GLOBAL LOGGING BLOCK ---
    {
        echo "=============================================================================="
        log "--- STARTING ROOT SYSTEM MAINTENANCE SEQUENCE ---"
        send_discord_message "Maintenance Started: Shutting down Factorio & checking for OS updates."

        # --- 1. GRACEFUL STOP ---
        # `systemctl stop` runs the unit's ExecStop (stop_server.sh): player countdown,
        # console save, SIGINT, verification. TimeoutStopSec in the unit covers all of it.
        log "Stopping $SERVICE_NAME (delegates to stop_server.sh for graceful shutdown)..."
        if systemctl stop "$SERVICE_NAME"; then
            log "$SERVICE_NAME stopped successfully."
        else
            log "WARNING: systemctl stop reported a failure for $SERVICE_NAME."
        fi

        if pgrep -u "$GAME_USER" -x "$GAME_PROCESS_NAME" > /dev/null; then
            log "WARNING: a $GAME_PROCESS_NAME process is still running after the stop. Check the stop log before trusting this reboot."
        fi

        # --- 2. CHECK AND APPLY LINUX UBUNTU OS UPDATES ---
        log "Checking for Ubuntu system updates..."
        apt-get update > /dev/null

        if apt-get upgrade -s 2>/dev/null | grep -q "^Inst"; then
            send_discord_message "Updates Found. Applying system patches..."
            log "Updates found! Applying full system upgrades..."
            DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" -y full-upgrade
            apt-get autoremove -y
            log "Updates applied successfully."
        else
            send_discord_message "No updates found. Core OS is clean."
            log "No OS updates found."
        fi

        # --- 3. EXECUTE HARDWARE REBOOT ---
        send_discord_message "Maintenance Complete: Rebooting server. Factorio will auto-restart (and self-update if needed)."
        log "Maintenance finished. Flushing storage buffers and executing system reboot."
        echo "=============================================================================="

        sync
        sleep 10
        reboot

    } 2>&1 | tee -a "$LOGFILE"

Make it executable:

    sudo chmod 750 /usr/local/sbin/factorio_maintenance.sh

> [!Note]
> `apt-get upgrade -s | grep "^Inst"` (a dry-run simulation) is used deliberately instead of `apt-get list --upgradable`. `apt-get` has no `list` subcommand, and that combination silently reports "no updates" even when real updates are pending.

**Schedule it via root's crontab** (not the game user's):

    sudo crontab -e

Add (6 AM daily shown):

    0 6 * * * flock -n /tmp/factorio_maintenance.lock /usr/local/sbin/factorio_maintenance.sh

After the reboot, systemd starts the server and the start script installs any pending Factorio update on the way up.

> [!Tip]
> Optional: to stop Ubuntu's `needrestart` from prompting during unattended upgrades, set the restart mode to list-only (`$nrconf{restart} = 'l';` in `/etc/needrestart/needrestart.conf`).

--------------------------------------------------------------------------------
# Step 12: Hardening (Optional)

Login with the sudo user and edit the sshd_config file

    sudo nano /etc/ssh/sshd_config

Locate and edit:

    LoginGraceTime 1m
    PermitRootLogin no
    MaxSessions 4

Reload and restart

    sudo systemctl daemon-reload
    sudo systemctl restart ssh.service

**Change Who Can Use the Switch User (su) Command**

    sudo groupadd restrictedsu
    sudo nano /etc/pam.d/su

Add the line:

    auth       required   pam_wheel.so group=restrictedsu

> [!TIP]
> If you want to trigger `start_server.sh`/`stop_server.sh` remotely without giving that system a general-purpose shell, consider a forced-command SSH key restricted to exactly one script (`command="/home/Your_Username/.scripts/start_server.sh",restrict ssh-ed25519 ...` in `authorized_keys`).

--------------------------------------------------------------------------------

# Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `Critical Error: no usable Factorio install` | A dependency is missing. Run `command -v jq rsync curl xz ss screen pgrep` and install whatever is absent. |
| Lua error inside a built-in mod and no third-party mods in the log | Mixed old and new game files from extracting an update over an old install. Reinstall `bin/` and `data/` from a fresh archive. Saves, mods and settings are untouched by this. |
| `screen -ls` shows nothing but the server is up | Your shell is not using the scripts' screen directory. Run `export SCREENDIR=/home/Your_Username/.screen`. |
| Checker says it is BLOCKED | A previous update did not apply. Read the reason in the checker log, fix it, then `rm /home/Your_Username/.run/update_checker_blocked`. |
| Update not installing | The new version is in a different `X.Y` series. Run `touch /home/Your_Username/.run/allow_major_update` and restart the service. |
| `status=217/USER` or `226/NAMESPACE` | The `ExecStartPre=+` lines are missing the `+`, or a `ReadWritePaths` directory does not exist. |
| Update downloaded but files look unchanged | Rsync must use `--checksum` (the start script already does), because file sizes and times can match across versions. |

--------------------------------------------------------------------------------

**Conclusion**

You have successfully set up a hardened Factorio server with automated backups, a verified graceful shutdown, safe automatic updates with a major-release guard, and a systemd service that tracks the real game process.

**References**
- https://factorio.com/api/latest-releases
- https://wiki.factorio.com/Multiplayer
- https://wiki.factorio.com/Command_line_parameters
- https://www.digitalocean.com/community/tutorials/ufw-essentials-common-firewall-rules-and-commands
