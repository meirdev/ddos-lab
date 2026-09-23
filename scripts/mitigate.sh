#!/bin/bash
# =============================================================
#  mitigate.sh — Send FlowSpec rules via ExaBGP to the router
# =============================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <rule>"
    echo ""
    echo "Predefined rules:"
    echo "  block-syn       Drop SYN floods to target port 80"
    echo "  block-udp       Drop UDP floods to target port 53"
    echo "  block-icmp      Drop all ICMP to target"
    echo "  block-all       Drop ALL traffic to target"
    echo "  rate-limit      Rate-limit traffic to target"
    echo ""
    echo "Custom rule:"
    echo "  custom \"<exabgp flowspec command>\""
    echo ""
    echo "Examples:"
    echo "  $0 block-syn"
    echo "  $0 custom 'announce flow route { match { destination 10.0.2.10/32; protocol tcp; destination-port =80; } then { discard; } }'"
    exit 1
}

send_flowspec() {
    local cmd="$1"
    echo -e "${GREEN}[+] Sending FlowSpec rule:${NC}"
    echo "    $cmd"
    docker exec exabgp sh -c "echo '$cmd' > /var/run/exabgp.cmd"
    echo -e "${GREEN}[+] Rule sent. flowspecd should install an nftables rule:${NC}"
    echo "    docker exec router nft list table inet flowspec"
    echo "    docker logs --tail 10 router"
}

[[ $# -lt 1 ]] && usage

rule="$1"

case "$rule" in

    block-syn)
        echo -e "${YELLOW}[*] Blocking SYN floods to 10.0.2.10:80${NC}"
        send_flowspec "announce flow route { match { destination 10.0.2.10/32; protocol tcp; destination-port =80; tcp-flags syn; } then { discard; } }"
        ;;

    block-udp)
        echo -e "${YELLOW}[*] Blocking UDP floods to 10.0.2.10:53${NC}"
        send_flowspec "announce flow route { match { destination 10.0.2.10/32; protocol udp; destination-port =53; } then { discard; } }"
        ;;

    block-icmp)
        echo -e "${YELLOW}[*] Blocking ICMP to 10.0.2.10${NC}"
        send_flowspec "announce flow route { match { destination 10.0.2.10/32; protocol icmp; } then { discard; } }"
        ;;

    block-all)
        echo -e "${YELLOW}[*] Blocking ALL traffic to 10.0.2.10${NC}"
        send_flowspec "announce flow route { match { destination 10.0.2.10/32; } then { discard; } }"
        ;;

    rate-limit)
        echo -e "${YELLOW}[*] Rate-limiting traffic to 10.0.2.10 (1 Mbps)${NC}"
        send_flowspec "announce flow route { match { destination 10.0.2.10/32; protocol tcp; destination-port =80; } then { rate-limit 125000; } }"
        ;;

    custom)
        [[ $# -lt 2 ]] && { echo "Error: custom rule requires a command string"; usage; }
        send_flowspec "$2"
        ;;

    *)
        echo "Unknown rule: $rule"
        usage
        ;;
esac
