#!/usr/bin/env bash
#
# Configure Ubuntu Server 24.04 networking with Netplan and systemd-networkd.
#
# Author: Joan Puiggali aka kopernix
# License: MIT

set -Eeuo pipefail
IFS=$'\n\t'

TARGET_FILE="/etc/netplan/50-cloud-init.yaml"
TEMP_FILE=""
BACKUP_FILE=""
HAD_ORIGINAL=0
CHANGES_WRITTEN=0
CURRENT_STEP="Pre-flight checks"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_RESET=$'\033[0m'
else
    C_GREEN=""
    C_RED=""
    C_YELLOW=""
    C_CYAN=""
    C_RESET=""
fi

SUMMARY=()
OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

record_ok() {
    SUMMARY+=("OK|$1")
    OK_COUNT=$((OK_COUNT + 1))
}

record_warn() {
    SUMMARY+=("WARN|$1")
    WARN_COUNT=$((WARN_COUNT + 1))
}

record_fail() {
    SUMMARY+=("FAIL|$1")
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

print_summary() {
    local result status detail

    printf '\n%s\n' '============================================================'
    printf ' Network configuration summary\n'
    printf '%s\n' '============================================================'

    for result in "${SUMMARY[@]}"; do
        IFS='|' read -r status detail <<< "$result"
        case "$status" in
            OK)   printf ' %s[OK]%s   %s\n' "$C_GREEN" "$C_RESET" "$detail" ;;
            WARN) printf ' %s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$detail" ;;
            FAIL) printf ' %s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$detail" ;;
        esac
    done

    if [[ "$FAIL_COUNT" -eq 0 ]]; then
        printf '\n %sResult: %d passed, %d warnings%s\n' \
            "$C_GREEN" "$OK_COUNT" "$WARN_COUNT" "$C_RESET"
    else
        printf '\n %sResult: %d passed, %d warnings, %d failed%s\n' \
            "$C_RED" "$OK_COUNT" "$WARN_COUNT" "$FAIL_COUNT" "$C_RESET"
    fi
    printf '%s\n' '============================================================'
}

cleanup() {
    [[ -z "$TEMP_FILE" || ! -e "$TEMP_FILE" ]] || rm -f -- "$TEMP_FILE"
}

restore_previous_file() {
    if [[ "$HAD_ORIGINAL" -eq 1 ]]; then
        [[ -f "$BACKUP_FILE" ]] || return 1
        cp -a -- "$BACKUP_FILE" "$TARGET_FILE"
    else
        rm -f -- "$TARGET_FILE"
    fi
}

on_error() {
    local rc=$?
    local failed_command="$BASH_COMMAND"
    trap - ERR

    if [[ "$CHANGES_WRITTEN" -eq 1 ]]; then
        if restore_previous_file; then
            record_ok "Previous Netplan file restored after an unexpected error"
        else
            record_fail "Could not restore the previous Netplan file"
        fi
    fi
    record_fail "${CURRENT_STEP} (command failed: ${failed_command})"
    print_summary
    exit "$rc"
}

trap cleanup EXIT
trap on_error ERR

die() {
    printf '\n%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
    exit 1
}

valid_ipv4() {
    local address="$1"
    local octet
    local -a octets

    [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$address"
    for octet in "${octets[@]}"; do
        ((10#$octet <= 255)) || return 1
    done
}

valid_ipv4_cidr() {
    local value="$1"
    local address prefix

    [[ "$value" =~ ^([^/]+)/([0-9]{1,2})$ ]] || return 1
    address="${BASH_REMATCH[1]}"
    prefix="${BASH_REMATCH[2]}"
    valid_ipv4 "$address" && ((10#$prefix <= 32))
}

interface_is_available() {
    local wanted="$1"
    local interface

    for interface in "${INTERFACES[@]}"; do
        [[ "$interface" == "$wanted" ]] && return 0
    done
    return 1
}

write_yaml() {
    local mode="$1"
    local interface="$2"
    local address="${3:-}"
    local gateway="${4:-}"
    local dns_primary="${5:-}"
    local dns_secondary="${6:-}"

    if [[ "$mode" == "dhcp" ]]; then
        cat <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${interface}:
      dhcp4: true
EOF
    else
        cat <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${interface}:
      addresses:
        - ${address}
      nameservers:
        addresses:
          - ${dns_primary}
          - ${dns_secondary}
      routes:
        - to: default
          via: ${gateway}
          on-link: true
EOF
    fi
}

[[ "$EUID" -eq 0 ]] || die "Run this script as root (for example: sudo ./set-ubuntu-ip.sh)."
[[ -r /etc/os-release ]] || die "Cannot identify the operating system."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] || \
    die "This script supports Ubuntu Server 24.04 only (detected: ${PRETTY_NAME:-unknown})."
command -v ip >/dev/null 2>&1 || die "The ip command is required."
command -v netplan >/dev/null 2>&1 || die "Netplan is required."
command -v systemctl >/dev/null 2>&1 || die "systemctl is required."
systemctl is-active --quiet systemd-networkd.service || \
    die "systemd-networkd.service must be active."
[[ -d /etc/netplan ]] || die "/etc/netplan does not exist."
[[ ! -L "$TARGET_FILE" ]] || die "$TARGET_FILE must not be a symbolic link."
[[ ! -e "$TARGET_FILE" || -f "$TARGET_FILE" ]] || die "$TARGET_FILE is not a regular file."

mapfile -t INTERFACES < <(
    ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' |
        while IFS= read -r interface; do
            [[ "$interface" =~ ^[a-zA-Z0-9_.-]+$ ]] || continue
            [[ "$interface" != "lo" ]] || continue
            [[ -r "/sys/class/net/${interface}/type" ]] || continue
            [[ "$(<"/sys/class/net/${interface}/type")" == "1" ]] || continue
            [[ ! "$interface" =~ ^(veth|docker|br-|virbr|tap|tun|wg|tailscale) ]] || continue
            printf '%s\n' "$interface"
        done
)

[[ ${#INTERFACES[@]} -gt 0 ]] || die "No suitable Ethernet interface was detected."

printf '\n%s\n' '============================================================'
printf ' %sNETWORK CONFIGURATION - UBUNTU SERVER 24.04%s\n' "$C_CYAN" "$C_RESET"
printf '%s\n\n' '============================================================'

if [[ ${#INTERFACES[@]} -eq 1 ]]; then
    printf 'Detected interface: %s\n' "${INTERFACES[0]}"
    read -r -p "Interface [${INTERFACES[0]}]: " INTERFACE
    INTERFACE="${INTERFACE:-${INTERFACES[0]}}"
else
    printf 'Detected interfaces:\n'
    printf '  - %s\n' "${INTERFACES[@]}"
    read -r -p 'Interface: ' INTERFACE
fi

interface_is_available "$INTERFACE" || die "The selected interface does not exist or is not suitable."

printf '\nConfiguration mode:\n\n'
printf '  1) DHCP\n'
printf '  2) Static IP / OVH Additional IP\n\n'

while true; do
    read -r -p 'Select an option [1-2]: ' selection
    case "$selection" in
        1) MODE="dhcp"; break ;;
        2) MODE="static"; break ;;
        *) printf '%sInvalid selection. Enter 1 or 2.%s\n' "$C_YELLOW" "$C_RESET" ;;
    esac
done

ADDRESS=""
GATEWAY=""
DNS_PRIMARY="8.8.8.8"
DNS_SECONDARY="1.1.1.1"

if [[ "$MODE" == "static" ]]; then
    read -r -p 'IP/CIDR: ' ADDRESS
    valid_ipv4_cidr "$ADDRESS" || die "Enter a valid IPv4 address with CIDR, for example 51.38.162.62/32."

    read -r -p 'Gateway: ' GATEWAY
    valid_ipv4 "$GATEWAY" || die "Enter a valid IPv4 gateway."

    read -r -p "Primary DNS [${DNS_PRIMARY}]: " input
    DNS_PRIMARY="${input:-$DNS_PRIMARY}"
    valid_ipv4 "$DNS_PRIMARY" || die "Enter a valid primary DNS address."

    read -r -p "Secondary DNS [${DNS_SECONDARY}]: " input
    DNS_SECONDARY="${input:-$DNS_SECONDARY}"
    valid_ipv4 "$DNS_SECONDARY" || die "Enter a valid secondary DNS address."
fi

printf '\n%s\n' 'Proposed configuration'
printf '%s\n' '------------------------------------------------------------'
printf ' %-12s %s\n' 'Interface:' "$INTERFACE"
if [[ "$MODE" == "dhcp" ]]; then
    printf ' %-12s %s\n' 'Mode:' 'DHCP'
else
    printf ' %-12s %s\n' 'Mode:' 'Static IP / OVH Additional IP'
    printf ' %-12s %s\n' 'IP:' "$ADDRESS"
    printf ' %-12s %s\n' 'Gateway:' "$GATEWAY"
    printf ' %-12s %s, %s\n' 'DNS:' "$DNS_PRIMARY" "$DNS_SECONDARY"
    printf ' %-12s %s\n' 'On-link:' 'yes'
fi
printf ' %-12s %s\n' 'Renderer:' 'systemd-networkd'
printf ' %-12s %s\n' 'File:' "$TARGET_FILE"
printf '%s\n\n' '------------------------------------------------------------'
printf 'The existing file will be backed up before it is replaced.\n'
printf 'Cloud-Init will not be enabled, used, or modified.\n\n'

read -r -p 'Save this configuration? [y/N]: ' confirmation
if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    printf 'Operation cancelled. No changes were made.\n'
    exit 0
fi

CURRENT_STEP="Backing up the current Netplan file"
if [[ -f "$TARGET_FILE" ]]; then
    HAD_ORIGINAL=1
    BACKUP_FILE="${TARGET_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$TARGET_FILE" "$BACKUP_FILE"
    record_ok "Existing configuration backed up to ${BACKUP_FILE}"
else
    record_warn "No existing ${TARGET_FILE} file was found; no backup was needed"
fi

CURRENT_STEP="Writing the new Netplan file"
TEMP_FILE="$(mktemp /etc/netplan/.50-cloud-init.yaml.tmp.XXXXXX)"
write_yaml "$MODE" "$INTERFACE" "$ADDRESS" "$GATEWAY" "$DNS_PRIMARY" "$DNS_SECONDARY" > "$TEMP_FILE"
chown root:root "$TEMP_FILE"
chmod 600 "$TEMP_FILE"
mv -f -- "$TEMP_FILE" "$TARGET_FILE"
TEMP_FILE=""
CHANGES_WRITTEN=1
record_ok "Configuration written to ${TARGET_FILE}"
record_ok "Permissions on ${TARGET_FILE} set to 600"

CURRENT_STEP="Validating the Netplan configuration"
if ! generate_output="$(netplan generate 2>&1)"; then
    printf '\n%snetplan generate failed:%s\n%s\n' "$C_RED" "$C_RESET" "$generate_output" >&2
    record_fail "netplan generate rejected the new configuration"

    if restore_previous_file; then
        CHANGES_WRITTEN=0
        record_ok "Previous Netplan file restored"
        if ! restore_output="$(netplan generate 2>&1)"; then
            record_fail "Restored Netplan configuration also failed validation: ${restore_output//$'\n'/; }"
        fi
    else
        record_fail "Could not restore the previous Netplan file"
    fi

    print_summary
    exit 1
fi
record_ok "netplan generate validated the configuration"
if [[ -n "$generate_output" ]]; then
    record_warn "netplan generate returned: ${generate_output//$'\n'/; }"
fi

printf '\n%sGenerated configuration:%s\n' "$C_CYAN" "$C_RESET"
printf '%s\n' '------------------------------------------------------------'
sed 's/^/  /' "$TARGET_FILE"
printf '%s\n' '------------------------------------------------------------'

printf '\n%sWhen connected through SSH, use netplan try so the network can roll back%s\n' \
    "$C_YELLOW" "$C_RESET"
printf '%sif the new configuration is not confirmed.%s\n\n' "$C_YELLOW" "$C_RESET"
read -r -p 'Test the new configuration with "netplan try"? [y/N]: ' try_confirmation

if [[ "$try_confirmation" =~ ^[Yy]$ ]]; then
    CURRENT_STEP="Testing the configuration with netplan try"
    if netplan try; then
        record_ok "netplan try completed and the configuration was confirmed"
    else
        record_warn "netplan try did not complete successfully; runtime changes should have been rolled back"
    fi
else
    record_warn "Configuration saved but not applied; run sudo netplan try when ready"
fi

print_summary

if [[ "$FAIL_COUNT" -ne 0 ]]; then
    exit 1
fi
