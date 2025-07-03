#!/bin/sh

# Trap SIGINT (Ctrl+C) and exit with a message
trap 'printf "\nAborted by user.\n"; exit 130' INT

# User welcome message
printf '\n####################################################################\n'
printf '# 👋 Welcome, this is the setup script for the tpn CLI tool.\n'
printf '####################################################################\n\n'

printf 'This script will:\n\n'
printf '1. Install dependencies needed to make VPN connections.\n'
printf '2. Download the latest version of the TPN CLI tool.\n'
printf '3. Verify that everything is working correctly.\n'
printf '\nNote: installation will ask for your password at least once.\n\n'

# Set the binary folder
BINARY_FOLDER="/usr/local/bin"
BINARY_FILE="$BINARY_FOLDER/tpn"

# Download the current executable
REPO_URL="https://raw.githubusercontent.com/marvikomo/tpn-cli"
FILE_URL="$REPO_URL/marvikomo-patch-1/tpn.sh"

# Tell the user to expect sudo
printf '[ 0 ] Requesting superuser permissions for installation...\n'

# Ask for sudo once, in most systems this will cache the permissions for a bit
sudo -v > /dev/null 2>&1
if [ $? -ne 0 ]; then
    printf "You need to provide superuser permissions to install the TPN CLI tool.\n"
    exit 1
fi
printf '[ 1 ] Superuser permissions acquired.\n'

# Make sure binfolder exists
printf '[ 2 ] Ensuring the binary folder exists at %s\n' "$BINARY_FOLDER"
sudo mkdir -p "$BINARY_FOLDER"

# Download the file to tempfolder and move it to the binary folder
printf '[ 3 ] Downloading the TPN CLI tool from Github\n'
sudo rm -f "$BINARY_FILE"
TEMP_DIR=$(mktemp -d -t tpn_download_XXXXXX)
curl -sSL "$FILE_URL" -o "$TEMP_DIR/tpn.sh"
sudo mv "$TEMP_DIR/tpn.sh" "$BINARY_FILE"
rm -rf "$TEMP_DIR"

# Get the current owner (macOS-compatible)
OWNER=$(stat -f '%Su' "$BINARY_FILE")

# If user is not owner, change ownership
if [ "$OWNER" != "$USER" ]; then
    printf '[ ! ] Changing ownership of %s to %s\n' "$BINARY_FILE" "$USER"
    sudo chown "$USER" "$BINARY_FILE"
fi

# Get current permissions
PERMS=$(stat -f '%Mp%Lp' "$BINARY_FILE")

# If permissions not 755, change them
if [ "$PERMS" != "0755" ]; then
    printf '[ ! ] Changing permissions of %s to 755\n' "$BINARY_FILE"
    sudo chmod 755 "$BINARY_FILE"
fi

# If not yet executable, make it executable
if [ ! -x "$BINARY_FILE" ]; then
    printf '[ ! ] Making %s executable\n' "$BINARY_FILE"
    sudo chmod +x "$BINARY_FILE"
fi

# Run TPN visudo
printf '[ 4 ] Running TPN visudo to ensure proper permissions\n'
tpn visudo

# Final message
printf '\n####################################################################\n'
echo "# 🎉 TPN CLI tool has been successfully installed"
echo "# You can now use it by typing 'tpn' in your terminal."
printf '####################################################################\n\n'
