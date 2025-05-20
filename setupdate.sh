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

# If user is not owner, change ownership
if [ "$(stat -c '%U' "$BINARY_FILE")" != "$USER" ]; then
  echo "Changing ownership of $BINARY_FILE to $USER"
  sudo chown $USER "$BINARY_FILE"
fi

# If permissions not 755, change them
if [ "$(stat -c '%a' "$BINARY_FILE")" != "755" ]; then
  echo "Changing permissions of $BINARY_FILE to 755"
  sudo chmod 755 "$BINARY_FILE"
fi

# If not yet executable, make it executable
if [ ! -x "$BINARY_FILE" ]; then
  echo "Making $BINARY_FILE executable"
  sudo chmod +x "$BINARY_FILE"
fi
