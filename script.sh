#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

IFACE="eth0"           # attacker's only NIC (attack-net)
TARGET="10.0.2.10"     # target host behind the router
ATTACK_INTERVAL="10ms" # delay between packets (~100 packets/sec per attack)

usage() {
    cat <<'HELP'
Usage: ./script.sh <command>

Attacks:
  syn-flood          TCP SYN flood to target port 80
  udp-flood          UDP flood to target port 53
  icmp-flood         ICMP flood
  spoof-flood        Spoofed source IP flood to target port 80
  stop-attack        Stop all running attacks in the attacker container

* Attack pacing is controlled by ATTACK_INTERVAL at the top of this script.

Mitigation:
  mitigate-syn      Block TCP SYN traffic to target port 80
  mitigate-udp      Block UDP traffic to target port 53
  mitigate-icmp     Block ICMP traffic to target
  mitigate-all      Block all traffic to target
  mitigate-rate     Rate-limit TCP traffic to target port 80 (1 Mbps)

Withdrawal:
  withdraw-syn      Remove TCP SYN mitigation
  withdraw-udp      Remove UDP mitigation
  withdraw-icmp     Remove ICMP mitigation
  withdraw-all      Remove the block-all rule
  withdraw-rate     Remove the rate-limit rule

Checks:
  ping-router       Check attacker → router
  ping-target       Check router → target
  ping-through      Check attacker → target through the router
  connectivity      Run all three connectivity checks
  bgp               Show recent BGP / FlowSpec log activity
  rules             Show active FlowSpec rules

  -h, --help        Show this help

Examples:
  ./script.sh syn-flood
  ./script.sh mitigate-syn
  ./script.sh stop-attack
  ./script.sh withdraw-syn
  ./script.sh connectivity
HELP
}

ping_check() {
    local source="$1" address="$2"
    printf '%s → %s: ' "$source" "$address"
    if docker compose exec -T "$source" ping -c1 -W2 "$address" >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAIL"
        return 1
    fi
}

run_attack() {
    local type="$1"
    local -a args
    case "$type" in
        syn)   args=(--tcp -S --dst-port 80) ;;
        udp)   args=(--udp --dst-port 53) ;;
        icmp)  args=(--icmp) ;;
        spoof) args=(--tcp -S --src-ip 10.0.1.0/24 --dst-port 80) ;;
    esac
    docker compose exec -d -T attacker rping -I "$IFACE" --dst-ip "$TARGET" "${args[@]}" --interval "$ATTACK_INTERVAL" --quiet
    printf 'Started %s attack in the background (interval: %s).\n' "$type" "$ATTACK_INTERVAL"
}

stop_attack() {
    docker compose exec -T attacker sh -c '
        if pidof rping >/dev/null; then
            killall -INT rping || exit 1
            echo "Stop signal sent to all running attacks."
        else
            echo "No attacks are running."
        fi
    '
}

send_rule() {
    local action="$1" rule="$2" match effect="discard;"
    case "$rule" in
        syn)  match="protocol tcp; destination-port =80; tcp-flags syn;" ;;
        udp)  match="protocol udp; destination-port =53;" ;;
        icmp) match="protocol icmp;" ;;
        all)  match="" ;;
        rate) match="protocol tcp; destination-port =80;"; effect="rate-limit 125000;" ;;
    esac
    local cmd="$action flow route { match { destination $TARGET/32; $match } then { $effect } }"
    docker compose exec -T exabgp sh -c 'printf "%s\n" "$1" > /var/run/exabgp.cmd' sh "$cmd"
    printf 'Sent: %s\n' "$cmd"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

if [[ $# -gt 1 ]]; then
    echo "Error: expected a single command." >&2
    exit 2
fi

command="$1"

case "$command" in
    -h|--help) usage ;;
    syn-flood|udp-flood|icmp-flood|spoof-flood)
        run_attack "${command%-flood}"
        ;;
    stop-attack) stop_attack ;;
    mitigate-syn|mitigate-udp|mitigate-icmp|mitigate-all|mitigate-rate)
        send_rule announce "${command#mitigate-}"
        ;;
    withdraw-syn|withdraw-udp|withdraw-icmp|withdraw-all|withdraw-rate)
        send_rule withdraw "${command#withdraw-}"
        ;;
    ping-router) ping_check attacker 10.0.1.1 ;;
    ping-target) ping_check router "$TARGET" ;;
    ping-through) ping_check attacker "$TARGET" ;;
    connectivity)
        failed=0
        ping_check attacker 10.0.1.1 || failed=1
        ping_check router "$TARGET" || failed=1
        ping_check attacker "$TARGET" || failed=1
        exit "$failed"
        ;;
    bgp)
        logs=$(docker compose logs --no-color --tail 5 router 2>&1) || { printf '%s\n' "$logs" >&2; exit 1; }
        printf '%s\n' "$logs" | grep -E "FSM|Received|FlowSpec|Action|Applied" || echo "No recent BGP / FlowSpec activity"
        ;;
    rules)
        docker compose exec -T router nft list table inet flowspec
        ;;
    *)
        printf 'Unknown command: %s\nRun ./script.sh --help for available commands.\n' "$command" >&2
        exit 2
        ;;
esac
