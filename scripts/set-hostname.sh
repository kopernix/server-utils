#!/usr/bin/env bash
#
# Safely change the hostname and local FQDN on Debian or Ubuntu.
#
# Author: Joan Puiggali aka kopernix
# License: MIT

set -Eeuo pipefail
IFS=$'\n\t'

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_RESET=$'\033[0m'
else
    C_GREEN=""
    C_RED=""
    C_YELLOW=""
    C_RESET=""
fi

SUMMARY=()
OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
CURRENT_STEP="Pre-flight checks"
CHANGES_STARTED=0
ROLLBACK_RUNNING=0
BACKUP_DIR=""
OLD_HOSTNAME=""
NEW_HOSTNAME=""
NEW_DOMAIN=""
NEW_FQDN=""

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

print_verification_summary() {
    local result status detail

    printf '\n%s\n' '===================================================================='
    printf ' Hostname change verification\n'
    printf '%s\n' '===================================================================='

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
    printf '%s\n' '===================================================================='
}

restore_backups() {
    [[ "$CHANGES_STARTED" -eq 1 ]] || return 0
    [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || return 0

    ROLLBACK_RUNNING=1
    printf '\nAttempting to restore the previous configuration...\n' >&2
    cp -a -- "$BACKUP_DIR/hostname" /etc/hostname || true
    cp -a -- "$BACKUP_DIR/hosts" /etc/hosts || true
    if [[ -n "$OLD_HOSTNAME" ]]; then
        hostnamectl set-hostname "$OLD_HOSTNAME" || true
    fi
}

on_error() {
    local rc=$?
    local failed_command="$BASH_COMMAND"
    trap - ERR

    if [[ "$ROLLBACK_RUNNING" -eq 0 ]]; then
        restore_backups
    fi
    record_fail "${CURRENT_STEP} (command failed: ${failed_command})"
    print_verification_summary
    exit "$rc"
}

trap on_error ERR

die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

validate_hostname() {
    local value="$1"
    [[ ${#value} -le 63 ]] || return 1
    [[ "$value" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]
}

validate_domain() {
    local value="$1"
    local label
    local -a labels

    [[ -z "$value" ]] && return 0
    [[ ${#value} -le 189 ]] || return 1
    [[ "$value" != .* && "$value" != *. && "$value" != *..* ]] || return 1

    IFS='.' read -r -a labels <<< "$value"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 ]] || return 1
        [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
    done
}

value_or_missing() {
    local file="$1"
    if [[ -r "$file" ]]; then
        tr '\n' ' ' < "$file" | sed 's/[[:space:]]*$//'
    else
        printf '%s' '(not present or not readable)'
    fi
}

discover_hostname_files() {
    local hostname_value="$1"
    local fqdn_value="$2"
    local file
    local -A found=()

    while IFS= read -r file; do
        [[ -n "$file" ]] && found["$file"]=1
    done < <(grep -rIlF --exclude='*.crt' --exclude='*.key' --exclude='*.pem' \
        -- "$hostname_value" /etc 2>/dev/null || true)

    if [[ -n "$fqdn_value" && "$fqdn_value" != "$hostname_value" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && found["$file"]=1
        done < <(grep -rIlF --exclude='*.crt' --exclude='*.key' --exclude='*.pem' \
            -- "$fqdn_value" /etc 2>/dev/null || true)
    fi

    if [[ ${#found[@]} -eq 0 ]]; then
        printf '   %s\n' '(none found)'
        return
    fi

    printf '%s\n' "${!found[@]}" | LC_ALL=C sort | sed 's/^/   /'
}

cloud_init_status() {
    local matches
    matches="$(grep -RhsE '^[[:space:]]*(preserve_hostname|hostname|fqdn)[[:space:]]*:' \
        /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.d 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
        printf '%s' "${matches//$'\n'/; }"
    elif [[ -d /etc/cloud ]]; then
        printf '%s' '(installed; no hostname directive found)'
    else
        printf '%s' '(not installed)'
    fi
}

print_host_report() {
    local title="$1"
    local runtime_hostname static_hostname fqdn domain os_name

    runtime_hostname="$(hostname 2>/dev/null || true)"
    static_hostname="$(hostnamectl --static 2>/dev/null || true)"
    fqdn="$(hostname --fqdn 2>/dev/null || true)"
    domain="$(dnsdomainname 2>/dev/null || true)"
    os_name="${PRETTY_NAME:-unknown}"

    printf '\n%s\n' '===================================================================='
    printf ' %s\n' "$title"
    printf '%s\n' '===================================================================='
    printf ' %-24s %s\n' 'Distribution:' "$os_name"
    printf ' %-24s %s\n' 'Runtime hostname:' "${runtime_hostname:-unknown}"
    printf ' %-24s %s\n' 'Static hostname:' "${static_hostname:-unknown}"
    printf ' %-24s %s\n' 'Resolved FQDN:' "${fqdn:-unavailable}"
    printf ' %-24s %s\n' 'Resolved domain:' "${domain:-none}"
    printf ' %-24s %s\n' '/etc/hostname:' "$(value_or_missing /etc/hostname)"
    printf ' %-24s %s\n' '/etc/mailname:' "$(value_or_missing /etc/mailname)"
    printf ' %-24s %s\n' 'Cloud-init hostname:' "$(cloud_init_status)"

    printf '\n /etc/hosts relevant entries:\n'
    awk -v host="$runtime_hostname" -v fqdn="$fqdn" '
        /^[[:space:]]*#/ { next }
        $1 == "127.0.0.1" || $1 == "127.0.1.1" ||
        (host != "" && index($0, host)) || (fqdn != "" && index($0, fqdn)) {
            print "   " $0
            shown=1
        }
        END { if (!shown) print "   (no relevant entries found)" }
    ' /etc/hosts

    printf '\n Files under /etc containing the current hostname or FQDN:\n'
    discover_hostname_files "$runtime_hostname" "$fqdn"
    printf '%s\n' '===================================================================='
}

write_hostname_file() {
    local temp_file
    temp_file="$(mktemp /etc/hostname.server-utils.XXXXXX)"
    printf '%s\n' "$NEW_HOSTNAME" > "$temp_file"
    chmod --reference=/etc/hostname "$temp_file"
    chown --reference=/etc/hostname "$temp_file"
    mv -f -- "$temp_file" /etc/hostname
}

write_hosts_file() {
    local temp_file
    temp_file="$(mktemp /etc/hosts.server-utils.XXXXXX)"

    awk -v entry="127.0.1.1\t${NEW_FQDN}${NEW_DOMAIN:+ ${NEW_HOSTNAME}}" '
        $1 == "127.0.1.1" {
            if (!written) {
                print entry
                written=1
            }
            next
        }
        { print }
        END {
            if (!written) print entry
        }
    ' /etc/hosts > "$temp_file"

    chmod --reference=/etc/hosts "$temp_file"
    chown --reference=/etc/hosts "$temp_file"
    mv -f -- "$temp_file" /etc/hosts
}

verify_changes() {
    local static_hostname runtime_hostname expected_hosts

    static_hostname="$(hostnamectl --static 2>/dev/null || true)"
    runtime_hostname="$(hostname 2>/dev/null || true)"
    expected_hosts="${NEW_FQDN}${NEW_DOMAIN:+ ${NEW_HOSTNAME}}"

    if [[ "$(tr -d '\n' < /etc/hostname)" == "$NEW_HOSTNAME" ]]; then
        record_ok "/etc/hostname contains ${NEW_HOSTNAME}"
    else
        record_fail "/etc/hostname does not contain ${NEW_HOSTNAME}"
    fi

    if [[ "$static_hostname" == "$NEW_HOSTNAME" ]]; then
        record_ok "Static hostname is ${NEW_HOSTNAME}"
    else
        record_fail "Static hostname is ${static_hostname:-unavailable}, expected ${NEW_HOSTNAME}"
    fi

    if [[ "$runtime_hostname" == "$NEW_HOSTNAME" ]]; then
        record_ok "Runtime hostname is ${NEW_HOSTNAME}"
    else
        record_fail "Runtime hostname is ${runtime_hostname:-unavailable}, expected ${NEW_HOSTNAME}"
    fi

    if awk -v expected="$expected_hosts" '
        $1 == "127.0.1.1" {
            actual=""
            for (i=2; i<=NF; i++) actual=actual (actual ? " " : "") $i
            if (actual == expected) found++
        }
        END { exit !(found == 1) }
    ' /etc/hosts; then
        record_ok "/etc/hosts has the expected 127.0.1.1 entry"
    else
        record_fail "/etc/hosts does not have exactly one expected 127.0.1.1 entry"
    fi

    if [[ "$(hostname --fqdn 2>/dev/null || true)" == "$NEW_FQDN" ]]; then
        record_ok "Resolved FQDN is ${NEW_FQDN}"
    else
        record_fail "Resolved FQDN does not match ${NEW_FQDN}"
    fi

    record_ok "Backups are stored in ${BACKUP_DIR}"

    if grep -RqsE '^[[:space:]]*preserve_hostname[[:space:]]*:[[:space:]]*(false|no|0)' \
        /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.d 2>/dev/null; then
        record_warn "Cloud-init may overwrite the hostname on a later boot"
    fi
}

[[ "$EUID" -eq 0 ]] || die "Run this script as root (for example: sudo ./set-hostname.sh)."
[[ -r /etc/os-release ]] || die "Cannot identify the operating system."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" ]] || \
    die "This script supports Debian and Ubuntu only (detected: ${ID:-unknown})."
command -v hostnamectl >/dev/null 2>&1 || die "hostnamectl is required."
[[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]] || die "A running systemd instance is required."
[[ -f /etc/hostname && -f /etc/hosts ]] || die "/etc/hostname and /etc/hosts must exist."

OLD_HOSTNAME="$(hostnamectl --static)"
print_host_report "Current host configuration"

printf '\nEnter the new short hostname. Use lowercase letters, numbers, and hyphens.\n'
read -r -p 'New hostname: ' NEW_HOSTNAME
NEW_HOSTNAME="$(trim "$NEW_HOSTNAME")"
validate_hostname "$NEW_HOSTNAME" || \
    die "Invalid hostname. Use 1-63 lowercase letters, numbers, or hyphens; do not start or end with a hyphen."

read -r -p 'New domain (leave empty for no domain): ' NEW_DOMAIN
NEW_DOMAIN="$(trim "$NEW_DOMAIN")"
validate_domain "$NEW_DOMAIN" || \
    die "Invalid domain. Use lowercase DNS labels separated by dots."

NEW_FQDN="$NEW_HOSTNAME"
[[ -z "$NEW_DOMAIN" ]] || NEW_FQDN="${NEW_HOSTNAME}.${NEW_DOMAIN}"
[[ ${#NEW_FQDN} -le 253 ]] || die "The resulting FQDN is longer than 253 characters."

printf '\n%s\n' '===================================================================='
printf ' Proposed hostname change\n'
printf '%s\n' '===================================================================='
printf ' %-24s %s\n' 'New hostname:' "$NEW_HOSTNAME"
printf ' %-24s %s\n' 'New domain:' "${NEW_DOMAIN:-none}"
printf ' %-24s %s\n' 'New FQDN:' "$NEW_FQDN"
printf '\n Operations:\n'
printf '   - Back up /etc/hostname and /etc/hosts.\n'
printf '   - Set /etc/hostname to %s.\n' "$NEW_HOSTNAME"
printf '   - Set the 127.0.1.1 entry in /etc/hosts to %s%s.\n' \
    "$NEW_FQDN" "${NEW_DOMAIN:+ ${NEW_HOSTNAME}}"
printf '   - Set the static and runtime hostname with hostnamectl.\n'
printf '\n Not modified:\n'
printf '   - DNS records, /etc/mailname, cloud-init configuration, and service-specific files.\n'
printf '%s\n' '===================================================================='

read -r -p 'Apply these changes? Type YES to continue: ' confirmation
if [[ "$confirmation" != "YES" ]]; then
    printf 'Operation cancelled. No changes were made.\n'
    exit 0
fi

CURRENT_STEP="Creating configuration backups"
BACKUP_DIR="/var/backups/server-utils/set-hostname-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p -- "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp -a -- /etc/hostname "$BACKUP_DIR/hostname"
cp -a -- /etc/hosts "$BACKUP_DIR/hosts"
CHANGES_STARTED=1

CURRENT_STEP="Updating /etc/hostname"
write_hostname_file

CURRENT_STEP="Updating /etc/hosts"
write_hosts_file

CURRENT_STEP="Applying the hostname with hostnamectl"
hostnamectl set-hostname "$NEW_HOSTNAME"

CURRENT_STEP="Verifying the hostname change"
print_host_report "Updated host configuration"
verify_changes
print_verification_summary

if [[ "$FAIL_COUNT" -ne 0 ]]; then
    exit 1
fi
