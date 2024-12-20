#!/bin/bash

# Configurable Variables
SESSION_NAME="${SESSION_NAME:-'Factorio_Server'}"  # The name of the screen session
REBOOT_WARNING_15="${REBOOT_WARNING_15:-'The server is rebooting in 15 minutes.'}"  # Message for 15 minutes warning
REBOOT_WARNING_10="${REBOOT_WARNING_10:-'The server is rebooting in 10 minutes.'}"  # Message for 10 minutes warning
REBOOT_WARNING_5="${REBOOT_WARNING_5:-'The server is rebooting in 5 minutes. Please logout ASAP. Thank you :)'}"  # Message for 5 minutes warning
SAVE_COMMAND="${SAVE_COMMAND:-'server_save'}"  # Command to save the game state (if applicable)

# Check if the screen session exists
if screen -list | grep -q "$SESSION_NAME"; then
    # Send 15 minute reboot message to the screen session
    screen -S "$SESSION_NAME" -X stuff "$REBOOT_WARNING_15"$(echo -ne '\r')
    sleep 300  # Wait for 5 minutes

    # Send 10 minute reboot message to the screen session
    screen -S "$SESSION_NAME" -X stuff "$REBOOT_WARNING_10"$(echo -ne '\r')
    sleep 300  # Wait for 5 minutes

    # Send 5 minute reboot message to the screen session
    screen -S "$SESSION_NAME" -X stuff "$REBOOT_WARNING_5"$(echo -ne '\r')
    screen -S "$SESSION_NAME" -X stuff "$SAVE_COMMAND"$(echo -ne '\r')

else
    echo "Screen session '$SESSION_NAME' not found."
fi

# Tell the server to stop running (send Ctrl+C to stop the server)
screen -S "$SESSION_NAME" -X stuff $'\003'
