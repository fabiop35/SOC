#!/usr/bin/env bash
#
# net-ip.sh - switch the Samba AD DC host between a static IPv4 address and DHCP.
#
# Usage:
#   net-ip.sh status                 Show current interface / IP / route / DNS
#   net-ip.sh static [IP [PREFIX [GATEWAY]]]
#                                    Configure a static address (defaults below)
#   net-ip.sh dhcp                   Configure the interface to use DHCP
#   net-ip.sh help                   Show this help
#
# Defaults (current DC environment):
#   IP 192.168.0.121/24  GW 192.168.0.1  DNS 127.0.0.1  search soc.smb.local
#
set -euo pipefail

NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
BACKUP_DIR="/etc/netplan/backups"
HOSTS_FILE="/etc/hosts"
RESOLV_FILE="/etc/resolv.conf"

DNS_SEARCH="soc.smb.local"
DEF_IP="192.168.0.121"
DEF_PREFIX="24"
DEF_GW="192.168.0.1"
DEF_DNS="127.0.0.1"

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "must run as root: sudo $0 $*"
}

detect_iface() {
  local iface
  iface=$(ip -4 route show default 2>/dev/null | awk '/default/{print $5; exit}')
  [[ -z "$iface" ]] && iface=$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $2; exit}')
  [[ -z "$iface" ]] && die "could not detect a network interface"
  printf '%s' "$iface"
}

detect_mac() {
  cat "/sys/class/net/$1/address" 2>/dev/null || true
}

backup_netplan() {
  mkdir -p "$BACKUP_DIR"
  if [[ -f "$NETPLAN_FILE" ]]; then
    local b="$BACKUP_DIR/$(basename "$NETPLAN_FILE").$(date +%Y%m%d-%H%M%S)"
    cp -a "$NETPLAN_FILE" "$b"
    log "netplan backup: $b"
  fi
}

collect_static() {
  local cur_prefix cur_gw iface
  iface=$(detect_iface)
  cur_prefix=$(ip -o -4 addr show "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f2 | head -1)
  cur_gw=$(ip -4 route show default 2>/dev/null | awk '/default/{print $3; exit}')
  SI_IP="${1:-$DEF_IP}"
  SI_PREFIX="${2:-${cur_prefix:-$DEF_PREFIX}}"
  SI_GW="${3:-${cur_gw:-$DEF_GW}}"
}

write_dhcp_yaml() {
  local iface=$1 mac=$2
  cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  ethernets:
    $iface:
      match:
        macaddress: $mac
      set-name: $iface
      dhcp4: true
      dhcp6: false
EOF
  chmod 600 "$NETPLAN_FILE"
}

write_static_yaml() {
  local iface=$1 mac=$2 ip=$3 prefix=$4 gw=$5 dns=$6
  cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  ethernets:
    $iface:
      match:
        macaddress: $mac
      set-name: $iface
      dhcp4: false
      dhcp6: false
      addresses:
        - $ip/$prefix
      routes:
        - to: default
          via: $gw
      nameservers:
        addresses:
          - $dns
        search:
          - $DNS_SEARCH
EOF
  chmod 600 "$NETPLAN_FILE"
}

set_resolv() {
  if [[ -L "$RESOLV_FILE" ]]; then
    warn "$RESOLV_FILE is a symlink (systemd-resolved?); leaving it alone"
    return
  fi
  printf 'nameserver %s\nsearch %s\n' "$DEF_DNS" "$DNS_SEARCH" > "$RESOLV_FILE"
}

update_hosts() {
  local ip=$1 short fqdn
  short=$(hostname -s)
  fqdn=$(hostname -f 2>/dev/null || true)
  [[ "$fqdn" == *.* ]] || fqdn="$short.$DNS_SEARCH"
  [[ -w "$HOSTS_FILE" ]] || return 0
  cp -a "$HOSTS_FILE" "$HOSTS_FILE.bak"
  sed -i -E "/[[:space:]]${short}([[:space:]]|$)/d" "$HOSTS_FILE"
  printf '%s\t%s\t%s\n' "$ip" "$fqdn" "$short" >> "$HOSTS_FILE"
  log "hosts: $ip -> $fqdn $short"
}

restart_services() {
  if systemctl list-unit-files samba-ad-dc.service >/dev/null 2>&1; then
    log "restarting samba-ad-dc ..."
    systemctl restart samba-ad-dc
    command -v samba_dnsupdate >/dev/null 2>&1 && samba_dnsupdate --verbose >/dev/null 2>&1 || true
  elif systemctl list-unit-files smbd.service >/dev/null 2>&1; then
    log "restarting smbd/nmbd ..."
    systemctl restart smbd nmbd 2>/dev/null || systemctl restart smbd
  fi
}

apply_netplan() {
  netplan generate
  netplan apply
}

ssh_warning() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    warn "you are connected over SSH; changing the address may drop the session"
  fi
}

cmd_static() {
  collect_static "${1:-}" "${2:-}" "${3:-}"
  local iface mac
  iface=$(detect_iface)
  mac=$(detect_mac "$iface")
  ssh_warning
  log "configuring STATIC $SI_IP/$SI_PREFIX gw $SI_GW on $iface ($mac)"
  backup_netplan
  write_static_yaml "$iface" "$mac" "$SI_IP" "$SI_PREFIX" "$SI_GW" "$DEF_DNS"
  set_resolv
  update_hosts "$SI_IP"
  apply_netplan
  restart_services
  log "done."
}

cmd_dhcp() {
  local iface mac
  iface=$(detect_iface)
  mac=$(detect_mac "$iface")
  ssh_warning
  log "configuring DHCP on $iface ($mac)"
  backup_netplan
  write_dhcp_yaml "$iface" "$mac"
  apply_netplan
  restart_services
  log "done. current lease:"
  ip -4 addr show "$iface" | awk '/inet /{print "  "$2}'
}

cmd_status() {
  local iface
  iface=$(detect_iface)
  log "=== interface: $iface ($(detect_mac "$iface")) ==="
  netplan get ethernets."$iface" 2>/dev/null || sed -n '1,40p' "$NETPLAN_FILE"
  log "=== addresses ==="
  ip -4 addr show "$iface" | awk '/inet /{print "  "$2}'
  log "=== routes ==="
  ip -4 route show dev "$iface"
  log "=== resolver ==="
  cat "$RESOLV_FILE"
}

main() {
  local cmd=${1:-help}; shift || true
  case "$cmd" in
    static) require_root; cmd_static "$@";;
    dhcp)   require_root; cmd_dhcp;;
    status) cmd_status;;
    help|-h|--help) usage;;
    *) die "unknown command '$cmd' (see: $0 help)";;
  esac
}

main "$@"
