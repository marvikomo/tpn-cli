#!/bin/sh

# Set the binary folder
BINARY_FOLDER="/usr/local/bin"
BINARY_FILE="$BINARY_FOLDER/tpn"

# Download the current executable
REPO_URL="https://raw.githubusercontent.com/taofu-labs/tpn-cli"
FILE_URL="$REPO_URL/main/tpn.sh"

# Download the file
printf '[ 1 ] Downloading latest TPN CLI version from GitHub\n'
rm -f "$BINARY_FILE"  # Remove any existing file
curl -fsSL "$FILE_URL" | tee "$BINARY_FILE" > /dev/null

# Get the current owner (macOS-compatible)
OWNER=$(stat -f '%Su' "$BINARY_FILE")

# If user is not owner, change ownership
if [ "$OWNER" != "$USER" ]; then
  printf 'Changing ownership of %s to %s\n' "$BINARY_FILE" "$USER"
  chown "$USER" "$BINARY_FILE"
fi

# Get current permissions
PERMS=$(stat -f '%Mp%Lp' "$BINARY_FILE")

# If permissions not 755, change them
if [ "$PERMS" != "0755" ]; then
  printf 'Changing permissions of %s to 755\n' "$BINARY_FILE"
  chmod 755 "$BINARY_FILE"
fi

# If not yet executable, make it executable
if [ ! -x "$BINARY_FILE" ]; then
  printf 'Making %s executable\n' "$BINARY_FILE"
  chmod +x "$BINARY_FILE"
fi
