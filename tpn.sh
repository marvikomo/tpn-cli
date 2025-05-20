#!/bin/sh

# tpn — manage WireGuard configs via remote API (POSIX-compliant)
# Supports: failover endpoints, timeout, connect/disconnect, countries listing,
# sudoers setup, panic, dry-run, and verbose output

# --------------------
# Configuration
# --------------------
BASE_URLS="http://185.189.44.166:3000 http://185.189.44.167:3000 http://185.189.44.168:3000"
TIMEOUT=${TIMEOUT:-60}
TMP_DIR=${TMPDIR:-/tmp}
INTERFACE_NAME="tpn_config"
TMP_CONF=""
IP_SERVICE="ipv4.icanhazip.com"
CURRENT_VERSION='v0.0.2'
REPO_URL="https://raw.githubusercontent.com/taofu-labs/tpn-cli"


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
  echo "wireguard-tools not found. One-time install required."
  confirm "Install wireguard-tools now?" || { echo "Aborting."; exit 1; }

  if [ "$os" = "Linux" ]; then
    [ -f /proc/version ] && grep -qi microsoft /proc/version && echo "Detected WSL environment."
    echo "Running: sudo apt-get update && sudo apt-get install -y wireguard-tools"
    sudo apt-get update && sudo apt-get install -y wireguard-tools
  elif [ "$os" = "Darwin" ]; then
    echo "Running: brew install wireguard-tools"
    brew install wireguard-tools
  else
    echo "Unsupported OS: $os. Install wireguard-tools manually." >&2
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
# Preserve config file on exit
# --------------------
cleanup() {
  # [ -n "$TMP_CONF" ] && echo "Preserving config file: $TMP_CONF"
  echo ""
}
trap cleanup EXIT

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
# API request with failover
# --------------------
api_request() {
  path="$1"
  for base in $BASE_URLS; do
    resp=$(curl -s --max-time "$TIMEOUT" "$base$path") && {
      printf "%s" "$resp"
      return 0
    }
  done
  echo "Error: all endpoints failed for $path" >&2
  exit 1
}

# --------------------
# Get current public IP
# --------------------
current_ip() {
  curl -s "$IP_SERVICE"
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
  result=$(api_request "/api/config/countries?format=$fmt")
  printf "%s\n" "$result"
}

# --------------------
# Connect to TPN node
# --------------------
connect() {
  lease=10; timeout_override=""; skip_confirm=0; dry=0; verbose=0; country=""

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
      -*) echo "Unknown option: $1" >&2; usage;;
      *) [ -z "$country" ] && country="$1"; shift;;
    esac
  done

  # Print parsed values if verbose
  [ $verbose -eq 1 ] && echo "Called with: lease=$lease, timeout=$timeout_override, skip_confirm=$skip_confirm, dry=$dry, verbose=$verbose"

  # Validate input
  [ -n "$timeout_override" ] && TIMEOUT="$timeout_override"
  [ -z "$country" ] && { echo "Error: country code required" >&2; usage; }

  echo "Connecting to $country (lease=$lease min)..."

  [ ! -f /etc/sudoers.d/tpn ] && { echo "No sudoers entry for wg-quick."; confirm "Add entry?" && visudo; }
  [ $skip_confirm -eq 0 ] && ! confirm "Proceed?" && { echo "Aborted."; return; }

  cfg="$TMP_DIR/${INTERFACE_NAME}.conf"

  # Disconnect previous config if exists
  if [ -f "$cfg" ]; then
    echo "Cleaning up old connection..."
    if [ $dry -eq 1 ]; then
      echo "DRY RUN: sudo wg-quick down $cfg"
      echo "DRY RUN: rm -f $cfg"
    else
      if [ $verbose -eq 1 ]; then
        echo "Running: sudo wg-quick down $cfg"
        sudo wg-quick down "$cfg"
      else
        sudo wg-quick down "$cfg" >/dev/null 2>&1
      fi
      rm -f "$cfg"
    fi
  fi

  echo "IP before: $(current_ip)"
  TMP_CONF="$cfg"
  echo "Connecting you to a TPN node..."

  api_request "/api/config/new?format=text&geo=$country&lease_minutes=$lease" > "$TMP_CONF"

  # Check if TMP_CONF contains json with the key "error", if so exit with error. Do not use jq
  if grep -q '"error"' "$TMP_CONF"; then
    echo "Error: $(grep '"error"' "$TMP_CONF" | cut -d'"' -f4)" >&2
    rm -f "$TMP_CONF"
    exit 1
  fi
  

  [ $verbose -eq 1 ] && {
    echo "Config file: $TMP_CONF"
    cat "$TMP_CONF"
  }

  if [ $dry -eq 1 ]; then
    echo "DRY RUN: sudo wg-quick up $TMP_CONF"
  else
    echo "Running: sudo wg-quick up $TMP_CONF"
    [ $verbose -eq 1 ] && sudo wg-quick up "$TMP_CONF" || sudo wg-quick up "$TMP_CONF" >/dev/null 2>&1
  fi

  echo "IP after: $(current_ip)"
}

# --------------------
# Show status
# --------------------
status() {
  echo "TPN status: $(wg show interfaces | wc -l | grep -q 0 && echo "Disconnected" || echo "Connected") ($(current_ip))"
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
  echo "Disconnecting TPN..."

  [ ! -f "$cfg" ] && { echo "Error: no config to disconnect" >&2; exit 1; }

  if [ $dry -eq 1 ]; then
    echo "DRY RUN: sudo wg-quick down $cfg"
  else
    if [ $verbose -eq 1 ]; then
      sudo wg-quick down "$cfg"
    else
      echo "Running: sudo wg-quick down $cfg"
      sudo wg-quick down "$cfg" >/dev/null 2>&1
    fi
    rm -f "$cfg"
  fi

  echo "IP now: $(current_ip)"
}

# --------------------
# Add sudoers entry
# --------------------
visudo() {
  user=$(id -un)
  file="/etc/sudoers.d/tpn"
  echo "Creating sudoers entry for wg-quick..."
  [ -f "$file" ] && sudo rm -f "$file"

  # Add sudoers entry for wg-quick up and down
  printf "%s ALL=(ALL) NOPASSWD: %s up %s, %s down %s\n" \
    "$user" "$WG_QUICK" "$TMP_DIR/${INTERFACE_NAME}.conf" \
    "$WG_QUICK" "$TMP_DIR/${INTERFACE_NAME}.conf" \
    | sudo tee "$file" >/dev/null
  sudo chmod 440 "$file"
  echo "Added sudoers entry for $user: $file"
  echo "You can now run tpn without sudo."
}

# --------------------
# Panic (dangerous!)
# --------------------
panic() {
  os=$(uname)
  echo "WARNING: irreversible destructive action."
  confirm "Proceed?" || { echo "Aborted."; exit 1; }

  if [ "$os" = "Darwin" ]; then
    confirm "Erase macOS network settings?" || exit 1
    sudo rm /Library/Preferences/SystemConfiguration/{com.apple.airport.preferences.plist,com.apple.network.identification.plist,NetworkInterfaces.plist,preferences.plist}
    sudo reboot
  elif [ "$os" = "Linux" ]; then
    wg_ifaces=$(sudo wg show interfaces)
    tun_ifaces=$(ip -o link show | awk -F': ' '/^tun/ {print $2}')
    echo "WireGuard interfaces: $wg_ifaces"
    echo "TUN interfaces: $tun_ifaces"
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
    echo "Unsupported OS: $os"
    exit 1
  fi
}

# --------------------
# Update script
# --------------------
update() {
  REMOTE_SCRIPT_URL="$REPO_URL/main/tpn.sh"
  REMOTE_UPDATE_URL="$REPO_URL/main/setupdate.sh"

  echo "Checking for updates..."

  if curl -sS "$REMOTE_SCRIPT_URL" | grep -q "$CURRENT_VERSION"; then
    echo "Already up to date. Current version: $CURRENT_VERSION"
  else
    echo "New version available."
    echo "This will run: curl -sS $REMOTE_UPDATE_URL | bash"
    echo "Press any key to continue or Ctrl+C to cancel"
    read
    curl -sS "$REMOTE_UPDATE_URL" | sudo sh
  fi

  exit 0
}

# --------------------
# Main command dispatch
# --------------------
[ "$#" -ge 1 ] || usage
cmd=$1; shift

case "$cmd" in
  countries)  countries "$@";;
  connect)    connect "$@";;
  status)     status;;
  disconnect) disconnect "$@";;
  visudo)     visudo;;
  panic)      panic;;
  update)     update;;
  help|--help)usage;;
  *)          usage;;
esac

exit 0
