#!/bin/bash
# =============================================================
#  withdraw.sh — Remove FlowSpec rules via ExaBGP
# =============================================================
set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <rule>"
    echo ""
    echo "Rules (mirrors mitigate.sh):"
    echo "  block-syn       Withdraw SYN block rule"
    echo "  block-udp       Withdraw UDP block rule"
    echo "  block-icmp      Withdraw ICMP block rule"
    echo "  block-all       Withdraw block-all rule"
    echo "  rate-limit      Withdraw rate-limit rule"
    echo ""
    exit 1
}

withdraw_flowspec() {
    local cmd="$1"
    echo -e "${YELLOW}[-] Withdrawing FlowSpec rule:${NC}"
    echo "    $cmd"
    docker exec exabgp bash -c "echo '$cmd' > /var/run/exabgp.cmd"
    echo -e "${GREEN}[+] Withdrawal sent.${NC}"
}

[[ $# -lt 1 ]] && usage

case "$1" in

    block-syn)
        withdraw_flowspec "withdraw flow route { match { destination 10.0.2.10/32; protocol tcp; destination-port =80; tcp-flags syn; } then { discard; } }"
        ;;
    block-udp)
        withdraw_flowspec "withdraw flow route { match { destination 10.0.2.10/32; protocol udp; destination-port =53; } then { discard; } }"
        ;;
    block-icmp)
        withdraw_flowspec "withdraw flow route { match { destination 10.0.2.10/32; protocol icmp; } then { discard; } }"
        ;;
    block-all)
        withdraw_flowspec "withdraw flow route { match { destination 10.0.2.10/32; } then { discard; } }"
        ;;
    rate-limit)
        withdraw_flowspec "withdraw flow route { match { destination 10.0.2.10/32; protocol tcp; destination-port =80; } then { rate-limit 125000; } }"
        ;;
    *)
        echo "Unknown rule: $1"
        usage
        ;;
esac
