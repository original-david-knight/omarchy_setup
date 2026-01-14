#!/bin/bash

# Replace 'username' with the actual username you want to grant access to
TARGET_USER=$USER
SUDOERS_FILE="/etc/sudoers.d/$TARGET_USER"

# Check if the user exists
if ! id "$TARGET_USER" &>/dev/null; then
    echo "User $TARGET_USER does not exist. Please create the user first."
    exit 1
fi

# Add the NOPASSWD entry to a new file in /etc/sudoers.d/
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "$SUDOERS_FILE" > /dev/null

# Set the correct permissions (0440) and ownership (root:root) for the new file
sudo chmod 0440 "$SUDOERS_FILE"
sudo chown root:root "$SUDOERS_FILE"

echo "Passwordless sudo configured for user $TARGET_USER."
echo "The user may need to log out and log back in for the changes to take effect."

