# TPN - Command line tool

The Tensor Private Network (TPN) command line tool allows you to create VPN connections to the [TPN network](https://tpn.taofu.xyz/) that runs on Bittensor subnet 65.

![TPN](https://tpn.taofu.xyz/img/tpn-social-card.jpg)

**Installation:**

```bash
# Run the install script
curl -sS "https://raw.githubusercontent.com/taofu-labs/tpn-cli/main/setup.sh" | sh
```

**Usage:**

For a list of commands, run `tpn help`, which will show you available options like so:

```md
TPN v0.0.5 - CLI for creating VPN connections via the Tensor Private Network (TPN)
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
  -t, --timeout <sec>        API timeout (default 60)
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
```

**Example usage:**

```bash
# List available countries
tpn countries

# Connect to any country
tpn connect any

# Check connection status
tpn status

# Disconnect from the VPN
tpn disconnect
```