#!/bin/sh

# tpn — manage WireGuard configs via remote API (POSIX-compliant)
# Supports: failover endpoints, timeout, connect/disconnect, countries listing,
# sudoers setup, panic, dry-run, and verbose output

# --------------------
# Configuration
# --------------------
BASE_URLS="http://161.35.91.172:3000"
TIMEOUT=${TIMEOUT:-60}
TMP_DIR=${TMPDIR:-/tmp}
INTERFACE_NAME="tpn_config"
TMP_CONF=""
IP_SERVICE="ipv4.icanhazip.com"
CURRENT_VERSION='v0.0.10'
REPO_URL="https://raw.githubusercontent.com/taofu-labs/tpn-cli"
DEBUG=${DEBUG:-false}

# --------------------
# Helpers
# --------------------

green() {
  if [ $# -gt 0 ]; then
    printf '\033[0;32m%s\033[0m\n' "$*"
  else
    while IFS= read -r line; do
      printf '\033[0;32m%s\033[0m\n' "$line"
    done
  fi
}

red() {
  if [ $# -gt 0 ]; then
    printf '\033[0;31m%s\033[0m\n' "$*"
  else
    while IFS= read -r line; do
      printf '\033[0;31m%s\033[0m\n' "$line"
    done
  fi
}

grey() {
  if [ $# -gt 0 ]; then
    printf '\033[0;90m%s\033[0m\n' "$*"
  else
    while IFS= read -r line; do
      printf '\033[0;90m%s\033[0m\n' "$line"
    done
  fi
}


# --------------------
# Locate wg tools
# --------------------
WG_QUICK=$(command -v wg-quick 2>/dev/null)
WG_TOOL=$(command -v wg 2>/dev/null)

# --------------------
# Prompt helper
# --------------------
confirm() {
  printf "%s [Y/n] " "$1"
  read ans || return 1
  case "$ans" in [Nn]*) return 1;; *) return 0;; esac
}

# --------------------
# Install wireguard-tools if missing
# --------------------
install_tools() {
  os=$(uname)
  printf '%s\n' "wireguard-tools not found. One-time install required."
  confirm "Install wireguard-tools now?" || { printf '%s\n' "Aborting."; exit 1; }

  if [ "$os" = "Linux" ]; then
    [ -f /proc/version ] && grep -qi microsoft /proc/version && printf '%s\n' "Detected WSL environment."
    printf '%s\n' "Running: sudo apt-get update && sudo apt-get install -y wireguard-tools"
    sudo apt-get update && sudo apt-get install -y wireguard-tools
  elif [ "$os" = "Darwin" ]; then
    # Check if Homebrew is installed, install if not
    if ! command -v brew >/dev/null 2>&1; then
      printf '%s\n' "Homebrew not found. Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    printf '%s\n' "Running: brew install wireguard-tools"
    HOMEBREW_NO_AUTO_UPDATE=1 brew install wireguard-tools
  else
    printf '%s\n' "Unsupported OS: $os. Install wireguard-tools manually." >&2
    exit 1
  fi

  WG_QUICK=$(command -v wg-quick)
  WG_TOOL=$(command -v wg)
}

# --------------------
# Ensure wg tools exist
# --------------------
if [ -z "$WG_QUICK" ] || [ -z "$WG_TOOL" ]; then
  install_tools
fi

# --------------------
# Cleanup utility
# --------------------
# cleanup() {
  
# }
# trap cleanup EXIT

# --------------------
# Usage help
# --------------------
usage() {
  cat <<EOF
TPN $CURRENT_VERSION - CLI for creating VPN connections via the Tensor Private Network (TPN)
Usage: tpn <command> [options]

Commands:
  countries [code|name]            list country codes or names
  connect <code> [opts]            fetch & bring up WireGuard interface
  status                            show public IP and connection status
  disconnect [--dry] [--verbose]    bring down WireGuard interface
  visudo                            one-time sudoers entry for wg-quick
  panic                             DESTRUCTIVE: wipe or remove network interfaces
  help                              show this help
  update [--silent]                 check for updates and install if available
  uninstall                         remove tpn CLI, config, and sudoers entry

Options for connect:
  -l, --lease_minutes <min>  lease duration (default 10)
  -t, --timeout <sec>        API timeout (default $TIMEOUT)
  -f                         skip confirmation
  --dry                      dry-run
  -v, --verbose              show wg-quick output

Examples:
  tpn countries
  tpn connect US
  tpn status
  tpn disconnect
  tpn update

Options for disconnect:
  --dry                      dry-run
  -v, --verbose              show wg-quick output
EOF
  exit 1
}

# --------------------
# Curl with retry
# --------------------
call_url() {
  url="$1"
  timeout="${2:-$TIMEOUT}"
  # If DEBUG=true log out url to call
  curl --retry 3 --retry-delay 5 --max-time "$timeout" -s "$url"
}


# --------------------
# API request with failover
# --------------------
api_request() {
  path="$1"
  for base in $BASE_URLS; do
    resp=$(call_url "$base$path") && {
      printf "%s" "$resp"
      return 0
    }
  done
  red "Error: all endpoints failed for $path" >&2
  exit 1
}

# --------------------
# Get current public IP
# --------------------
current_ip() {
  call_url "$IP_SERVICE"
}

# --------------------
# List available countries
# --------------------
countries() {
  fmt="name"
  if [ "$1" = "name" ] || [ "$1" = "code" ]; then
    fmt="$1"
    shift
  fi
  prefix="$1"

  [ "$DEBUG" = true ] && grey "API call: /api/config/countries?format=$fmt"

  result=$(api_request "/api/config/countries?format=$fmt")
  printf "%s\n" "$result"
}

# --------------------
# Connect to TPN node
# --------------------
connect() {
  lease=10; timeout_override=""; skip_confirm=0; dry=0; verbose=0; country=""

  # If DEBUG=true set verbose to 1
  [ "$DEBUG" = true ] && verbose=1

  # Parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      -l|--lease_minutes) lease="$2"; shift 2;;
      --lease_minutes=*) lease="${1#*=}"; shift;;
      -t|--timeout) timeout_override="$2"; shift 2;;
      --timeout=*) timeout_override="${1#*=}"; shift;;
      -f) skip_confirm=1; shift;;
      --dry) dry=1; shift;;
      -v|--verbose) verbose=1; shift;;
      --) shift; break;;
      -*) red "Unknown option: $1" >&2; usage;;
      *) [ -z "$country" ] && country="$1"; shift;;
    esac
  done

  # Print parsed values if verbose
  [ $verbose -eq 1 ] && printf '%s\n' "Called with: lease=$lease, timeout=$timeout_override, skip_confirm=$skip_confirm, dry=$dry, verbose=$verbose"

  # Validate input
  [ -n "$timeout_override" ] && TIMEOUT="$timeout_override"
  [ -z "$country" ] && { red "Error: country code required" >&2; usage; }

  [ ! -f /etc/sudoers.d/tpn ] && { red "No sudoers entry for wg-quick."; confirm "Add entry?" && visudo; }
  [ $skip_confirm -eq 0 ] && ! confirm "Connecting to $country for $lease minutes" && { red "Aborted."; return; }

  cfg="$TMP_DIR/${INTERFACE_NAME}.conf"

  # Disconnect previous config if exists
  if [ -f "$cfg" ]; then
    grey "Cleaning up old connection..."
    if [ $dry -eq 1 ]; then
      grey "DRY RUN: sudo wg-quick down $cfg"
      grey "DRY RUN: rm -f $cfg"
    else
      if [ $verbose -eq 1 ]; then
        grey "Running: sudo wg-quick down $cfg"
        sudo wg-quick down "$cfg"
      else
        sudo wg-quick down "$cfg" >/dev/null 2>&1
      fi
      rm -f "$cfg"
    fi
  fi

  IP_BEFORE_CONNECT="$(current_ip)"
  TMP_CONF="$cfg"
  grey "Connecting you to a TPN node..."

  call_path="/api/config/new?format=text&geo=$country&lease_minutes=$lease"
  [ $verbose -eq 1 ] && grey "API call: $call_path"
  api_request "$call_path" > "$TMP_CONF"

  # Check if TMP_CONF contains json with the key "error", if so exit with error. Do not use jq
  if grep -q '"error"' "$TMP_CONF"; then
    red "Error: $(grep '"error"' "$TMP_CONF" | cut -d'"' -f4)" >&2
    rm -f "$TMP_CONF"
    exit 1
  fi
  

  [ $verbose -eq 1 ] && {
    grey "Config file: $TMP_CONF"
    cat "$TMP_CONF"
  }

  if [ $dry -eq 1 ]; then
    grey "DRY RUN: sudo wg-quick up $TMP_CONF"
  else
    if [ $verbose -eq 1 ]; then
        sudo wg-quick up "$TMP_CONF"
      else
        sudo wg-quick up "$TMP_CONF" >/dev/null 2>&1
    fi
  fi

  IP_AFTER_CONNECT="$(current_ip)"
  green "IP address changed from $IP_BEFORE_CONNECT to $IP_AFTER_CONNECT"

  # Save a timestamp for when we expect the lease to expire to the temp directory in teh file tpn_lease_end. Use the right date command for the OS
  now=$(date +%s)
  lease_end_timestamp=$(( now + lease * 60 ))

  # Do the same os dependent conversion for the readable date
  if [ "$(uname)" = "Darwin" ]; then
    lease_end_readable=$(date -j -v+${lease}M +"%Y-%m-%d %H:%M:%S")
  else
    lease_end_readable=$(date -d "+${lease} minutes" +"%Y-%m-%d %H:%M:%S")
  fi

  # Save lease end timestamp to temp file
  printf '%s\n' "$lease_end_timestamp" > "$TMP_DIR/tpn_lease_end_timestamp"
  printf '%s\n' "$lease_end_readable" > "$TMP_DIR/tpn_lease_end_readable"

  grey "TPN Connection lease ends in $lease minutes ($lease_end_readable)"

}

# --------------------
# Show status
# --------------------
status() {
  if [ "$(wg show interfaces | wc -l)" -eq 0 ]; then
    IS_CONNECTED="Disconnected"
  else
    IS_CONNECTED="Connected"
  fi

  MESSAGE="TPN status: $IS_CONNECTED ($(current_ip))"
  if [ "$IS_CONNECTED" = "Connected" ]; then
    green "$MESSAGE"
  else
    printf '%s\n' "$MESSAGE"
  fi

  # If connected, show the time to lease end 
  if [ "$IS_CONNECTED" = "Connected" ]; then
    if [ -f "$TMP_DIR/tpn_lease_end_readable" ]; then
      now=$(date +%s)
      lease_end_timestamp=$(cat "$TMP_DIR/tpn_lease_end_timestamp")
      lease_end=$(cat "$TMP_DIR/tpn_lease_end_readable")
      minutes_until_lease_end=$(( (lease_end_timestamp - now) / 60 ))
      [ "$minutes_until_lease_end" -lt 0 ] && minutes_until_lease_end=0
      grey "Lease ends in $minutes_until_lease_end minutes ($lease_end)"
    else
      printf '%s\n' "No lease end time found."
      return
    fi
  fi
}

# --------------------
# Disconnect command
# --------------------
disconnect() {
  dry=0; verbose=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry) dry=1; shift;;
      -v|--verbose) verbose=1; shift;;
      *) break;;
    esac
  done

  cfg="$TMP_DIR/${INTERFACE_NAME}.conf"
  grey "Disconnecting TPN..."
  IP_BEFORE_DISCONNECT="$(current_ip)"

  [ ! -f "$cfg" ] && { printf '%s\n' "Error: no config to disconnect" >&2; exit 1; }

  if [ $dry -eq 1 ]; then
    grey "DRY RUN: sudo wg-quick down $cfg"
  else
    if [ $verbose -eq 1 ]; then
      sudo wg-quick down "$cfg"
    else
      sudo wg-quick down "$cfg" >/dev/null 2>&1
    fi
    rm -f "$cfg"
  fi

  IP_AFTER_DISCONNECT="$(current_ip)"
  green "IP changed back from $IP_BEFORE_DISCONNECT to $IP_AFTER_DISCONNECT"
}

# --------------------
# Add sudoers entry
# --------------------
visudo() {
  if [ -n "$USER" ]; then
    user="$USER"
  else
    user=$(id -un)
  fi
  file="/etc/sudoers.d/tpn"
  grey "Creating sudoers entry for wg and wg-quick..."
  [ -f "$file" ] && sudo rm -f "$file"

  # Find binary locations
  WG_QUICK_BIN=$(command -v wg-quick 2>/dev/null)
  WG_BIN=$(command -v wg 2>/dev/null)

  # Add sudoers entry for wg and wg-quick (all parameters allowed)
  printf "%s ALL=(ALL) NOPASSWD: %s, %s\n" \
    "$user" "$WG_QUICK_BIN" "$WG_BIN" \
    | sudo tee "$file" >/dev/null
  sudo chmod 440 "$file"
  grey "Added sudoers entry for $user: $file"
  green "You can now run TPN without sudo password."
}

# --------------------
# Panic (dangerous!)
# --------------------
panic() {
  os=$(uname)
  red "WARNING: irreversible destructive action."
  confirm "Proceed?" || { printf '%s\n' "Aborted."; exit 1; }

  if [ "$os" = "Darwin" ]; then
    confirm "Erase macOS network settings? Your computer will reboot." || exit 1
    sudo rm /Library/Preferences/SystemConfiguration/{com.apple.airport.preferences.plist,com.apple.network.identification.plist,NetworkInterfaces.plist,preferences.plist}
    confirm "Are you sure you want to reboot now?" || exit 1
    sudo reboot
  elif [ "$os" = "Linux" ]; then
    wg_ifaces=$(sudo wg show interfaces)
    tun_ifaces=$(ip -o link show | awk -F': ' '/^tun/ {print $2}')
    grey "WireGuard interfaces: $wg_ifaces"
    grey "TUN interfaces: $tun_ifaces"
    confirm "Delete these interfaces?" || exit 1
    for iface in $wg_ifaces; do
      sudo wg-quick down "$iface" >/dev/null 2>&1 || sudo ip link set "$iface" down >/dev/null 2>&1
      sudo ip link delete "$iface" >/dev/null 2>&1 || true
    done
    for iface in $tun_ifaces; do
      sudo ip link set "$iface" down >/dev/null 2>&1
      sudo ip link delete "$iface" >/dev/null 2>&1
    done
  else
    red "Unsupported OS: $os"
    exit 1
  fi
}

# --------------------
# Update script
# --------------------
update() {
  silent=0
  # Parse optional parameter
  while [ $# -gt 0 ]; do
    case "$1" in
      --silent) silent=1; shift;;
      *) shift;;
    esac
  done

  REMOTE_SCRIPT_URL="$REPO_URL/main/tpn.sh"
  REMOTE_UPDATE_URL="$REPO_URL/main/update.sh"

  grey "Checking for updates..."

  if curl -sS "$REMOTE_SCRIPT_URL" | grep -q "$CURRENT_VERSION"; then
    green "Already up to date. Current version: $CURRENT_VERSION"
  else
    green "New version available."
    grey "This will run: curl -sS $REMOTE_UPDATE_URL | sh"
    if [ "$silent" -eq 0 ]; then
      grey "Press any key to continue or Ctrl+C to cancel"
      read
    fi
    curl -sS "$REMOTE_UPDATE_URL" | sh
  fi

  exit 0
}

# --------------------
# Uninstall script
# --------------------
uninstall() {

  grey "Uninstalling TPN CLI tool..."

  # Disconnect if connected
  if [ -f "$TMP_DIR/${INTERFACE_NAME}.conf" ]; then
    grey "Disconnecting TPN..."
    tpn disconnect
  fi

  BIN_PATH=$(command -v tpn 2>/dev/null)
  if [ -n "$BIN_PATH" ] && [ -f "$BIN_PATH" ]; then
    grey "Removing TPN binary, this may ask for your password..."
    sudo rm -f "$BIN_PATH"
    green "TPN binary removed."
  else
    grey "TPN binary not found in PATH."
  fi
  grey "Removing temporary files..."
  rm -f "$TMP_DIR/${INTERFACE_NAME}.conf"
  # Remove visudo file if it exists
  if [ -f "/etc/sudoers.d/tpn" ]; then
    grey "Removing sudoers visudo file..."
    sudo rm -f /etc/sudoers.d/tpn
    grey "Sudoers visudo file removed."
  fi
  green "TPN uninstall complete."
  exit 0
}

# --------------------
# Main command dispatch
# --------------------
[ "$#" -ge 1 ] || usage
cmd=$1; shift

trap 'printf "\nAborted by user.\n"; exit 130' INT

case "$cmd" in
  countries)  countries "$@";;
  connect)    connect "$@";;
  status)     status;;
  disconnect) disconnect "$@";;
  visudo)     visudo;;
  panic)      panic;;
  update)     update;;
  uninstall)  uninstall;;
  help|--help)usage;;
  *)          usage;;
esac

exit 0
