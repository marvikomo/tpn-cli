#!/bin/sh

# User welcome message
echo -e "\n####################################################################"
echo '# 👋 Welcome, this is the setup script for the tpn CLI tool.'
echo -e "# Note: this script will ask for your password once or multiple times."
echo -e "####################################################################\n\n"

# Set the binary folder
BINARY_FOLDER="/usr/local/bin"
BINARY_FILE="$BINARY_FOLDER/tpn"

# Download the current executable
REPO_URL="https://raw.githubusercontent.com/taofu-labs/tpn-cli"
FILE_URL="$REPO_URL/main/tpn.sh"

# Ask for sudo once, in most systems this will cache the permissions for a bit
sudo echo "Starting TPN installation"
echo -e "[ 1 ] Superuser permissions acquired."

# Make sure binfolder exists
echo -e "[ 2 ] Ensuring the binary folder exists at $BINARY_FOLDER"
sudo mkdir -p "$BINARY_FOLDER"

# Download the file to tempfolder and move it to the binary folder
echo -e "[ 3 ] Downloading the TPN CLI tool from Github"
sudo rm -f "$BINARY_FILE"
TEMP_DIR=$(mktemp -d -t tpn_download_XXXXXX)
curl -sSL "$FILE_URL" -o "$TEMP_DIR/tpn.sh"
sudo mv "$TEMP_DIR/tpn.sh" "$BINARY_FILE"
rm -rf "$TEMP_DIR"

# Get the current owner (macOS-compatible)
OWNER=$(stat -f '%Su' "$BINARY_FILE")

# If user is not owner, change ownership
if [ "$OWNER" != "$USER" ]; then
    echo -e "[ ! ] Changing ownership of $BINARY_FILE to $USER"
    sudo chown "$USER" "$BINARY_FILE"
fi

# Get current permissions
PERMS=$(stat -f '%Mp%Lp' "$BINARY_FILE")

# If permissions not 755, change them
if [ "$PERMS" != "0755" ]; then
    echo -e "[ ! ] Changing permissions of $BINARY_FILE to 755"
    sudo chmod 755 "$BINARY_FILE"
fi

# If not yet executable, make it executable
if [ ! -x "$BINARY_FILE" ]; then
    echo -e "[ ! ] Making $BINARY_FILE executable"
    sudo chmod +x "$BINARY_FILE"
fi

# Final message
echo -e "\n####################################################################"
echo "# 🎉 TPN CLI tool has been successfully installed at $BINARY_FILE"
echo "# You can now use it by typing 'tpn' in your terminal."
echo -e "####################################################################\n"