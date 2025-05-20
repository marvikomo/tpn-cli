#!/bin/sh

# Set the binary folder
BINARY_FOLDER="/usr/local/bin"
BINARY_FILE="$BINARY_FOLDER/tpn"

# Download the current executable
REPO_URL="https://raw.githubusercontent.com/taofu-labs/tpn-cli"
FILE_URL="$REPO_URL/main/tpn.sh"

# Make sure binfolder exists
mkdir -p "$BINARY_FOLDER"

# Download the file
curl -fsSL "$FILE_URL" | sudo tee "$BINARY_FILE" > /dev/null

# Make it executable
chown $USER "$BINARY_FILE"
chmod 755 "$BINARY_FILE"
chmod u+x "$BINARY_FILE"
