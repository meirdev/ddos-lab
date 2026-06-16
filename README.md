# DDoS & BGP FlowSpec Mitigation Lab

A self-contained Docker lab for learning about DDoS attacks and BGP FlowSpec
mitigation on a **plain Linux router**.

Attacks are generated with [`rping`](https://github.com/meirdev/rping) and
mitigated by [`flowspecd`](https://github.com/meirdev/flowspecd) — a BGP FlowSpec
daemon that listens for FlowSpec routes over BGP and translates them into
**nftables** rules in real time. A NetFlow + Prometheus stack lets you watch the
traffic before and after mitigation.

## Architecture

```
┌──────────┐   attack-net     ┌─────────────────┐   target-net    ┌──────────┐
│ Attacker │  10.0.1.0/24     │   Linux Router  │  10.0.2.0/24    │  Target  │
│ (rping)  │──────────────────│    flowspecd    │─────────────────│  .2.10   │
│  .1.10   │      .1.1        │  + nftables     │     .2.1        │ tcpdump  │
└──────────┘                  └───┬──────┬──────┘                 └──────────┘
                          .3.1 │ mgmt-net (10.0.3.0/24)
            ┌──────────────────┼──────┴────────────────┬─────────────────┐
       ┌────┴─────┐      ┌─────┴──────┐         ┌──────┴─────┐    ┌──────┴─────┐
       │  ExaBGP  │      │ Prometheus │         │ Collector  │    │  (router   │
       │  .3.10   │      │   .3.20    │         │   .3.40    │    │  exporters)│
       │ AS 65002 │      │  :9090     │         │ NetFlow    │    └────────────┘
       └──────────┘      └────────────┘         └────────────┘

 BGP AS 65001 (Router/flowspecd) ◄── eBGP ──► BGP AS 65002 (ExaBGP)
                            (IPv4 Unicast + FlowSpec)
```

**Traffic (data) path:** Attacker `10.0.1.10` → Router → Target `10.0.2.10`

**Control plane:** ExaBGP announces FlowSpec rules over BGP to `flowspecd` on the
router. `flowspecd` installs them as nftables rules in `table inet flowspec`
(chain `filter`, hooked at `forward`), dropping or rate-limiting the matching
attack traffic.

**Observability:**
- `flowspecd` exposes Prometheus metrics on the router at `:9100`.
- `node_exporter` exposes host/NIC metrics on the router at `:9101`.
- `rustflow_exporter` (router) sends NetFlow records to the `rustflow_collector`
  (`collector`, `:9995`).
- `prometheus` (`:9090`, published to the host) scrapes the router exporters.

## Components

| Container    | Address     | Role |
|--------------|-------------|------|
| `attacker`   | 10.0.1.10   | Generates attack traffic with `rping` |
| `router`     | .1.1 / .2.1 / .3.1 | Linux router running `flowspecd` (nftables) + exporters |
| `target`     | 10.0.2.10   | Victim host (runs `tcpdump`; no services) |
| `exabgp`     | 10.0.3.10   | BGP speaker (AS 65002) announcing FlowSpec rules |
| `collector`  | 10.0.3.40   | `rustflow_collector` — receives NetFlow |
| `prometheus` | 10.0.3.20   | Scrapes router metrics (host port 9090) |

## Quick Start

```bash
# 1. Build and start the lab
docker compose up -d --build

# 2. Wait ~20s for BGP to establish, then check health
./scripts/status.sh
```

`status.sh` should show all containers up, connectivity OK, and (once a rule is
applied) the active nftables rules.

## Step-by-Step Walkthrough

### Step 1 — Verify connectivity

```bash
# Attacker can reach the target through the router
docker exec attacker ping -c3 10.0.2.10
```

### Step 2 — Confirm the BGP session

```bash
# flowspecd logs the BGP FSM; look for an established session + keepalives
docker logs --tail 20 router

# ExaBGP side
docker logs --tail 20 exabgp
```

### Step 3 — Watch traffic on the target

In a **separate terminal**:

```bash
docker exec target tcpdump -i eth0 -n
```

### Step 4 — Launch a DDoS attack

```bash
# TCP SYN flood to 10.0.2.10:80
./scripts/attack.sh syn-flood

# Other types:
./scripts/attack.sh udp-flood
./scripts/attack.sh icmp-flood
./scripts/attack.sh spoof-flood        # randomized source IPs

# Or call rping directly:
docker exec attacker rping -I eth0 --tcp -S --dst-ip 10.0.2.10 --dst-port 80 --flood
```

You should see a flood of packets in the tcpdump output. Press Ctrl-C to stop
(or append `--duration 10s` / `-c 1000` to the attack command).

### Step 5 — Apply FlowSpec mitigation

```bash
./scripts/mitigate.sh block-syn      # drop SYN floods to :80
./scripts/mitigate.sh block-udp      # drop UDP floods to :53
./scripts/mitigate.sh block-icmp     # drop ICMP to target
./scripts/mitigate.sh block-all      # drop ALL traffic to target
./scripts/mitigate.sh rate-limit     # rate-limit traffic to :80
```

### Step 6 — Verify the rule was installed as nftables

```bash
# flowspecd translated the BGP FlowSpec route into an nft rule
docker exec router nft list table inet flowspec

# flowspecd's own log of the received route + action
docker logs --tail 10 router
```

Example installed rule for `block-syn`:

```
table inet flowspec {
    chain filter {
        type filter hook forward priority filter - 10; policy accept;
        ip daddr 10.0.2.10 tcp dport 80 tcp flags syn counter ... drop comment "d10.0.2.10/32p6dp80"
    }
}
```

`rate-limit` produces a `limit rate over <N> bytes/second ... drop` rule instead.

### Step 7 — Observe mitigation working

The tcpdump on the target should drop off (block rules) or throttle
(rate-limit) once the rule is installed. The packet/byte counters in
`nft list table inet flowspec` increment as traffic is matched.

### Step 8 — Remove mitigation

```bash
./scripts/withdraw.sh block-syn
```

The matching nftables rule disappears from `table inet flowspec`.

## Available Scripts

| Script | Description |
|--------|-------------|
| `scripts/attack.sh <type> [args]` | Launch attack with rping: `syn-flood`, `udp-flood`, `icmp-flood`, `spoof-flood`, or `custom` |
| `scripts/mitigate.sh <rule>` | Announce a FlowSpec rule: `block-syn`, `block-udp`, `block-icmp`, `block-all`, `rate-limit`, `custom` |
| `scripts/withdraw.sh <rule>` | Withdraw a previously announced FlowSpec rule |
| `scripts/status.sh` | Lab health: containers, connectivity, active nft rules, monitoring |

## Sending Custom FlowSpec Rules

Mitigation rules are sent to ExaBGP through its command pipe
(`/var/run/exabgp.cmd`); ExaBGP announces them over BGP to `flowspecd`.

```bash
# Block a specific source + destination + port
./scripts/mitigate.sh custom 'announce flow route { match { source 10.0.1.10/32; destination 10.0.2.10/32; protocol tcp; destination-port =80; } then { discard; } }'

# Rate-limit UDP (bytes/sec)
./scripts/mitigate.sh custom 'announce flow route { match { destination 10.0.2.10/32; protocol udp; } then { rate-limit 62500; } }'

# Or write straight to the ExaBGP pipe
docker exec exabgp bash -c 'echo "announce flow route { match { destination 10.0.2.10/32; protocol icmp; } then { discard; } }" > /var/run/exabgp.cmd'
```

## FlowSpec Rule Syntax Reference (ExaBGP)

```
announce flow route {
    match {
        source <prefix>;            # e.g. 10.0.1.0/24
        destination <prefix>;       # e.g. 10.0.2.10/32
        protocol [tcp|udp|icmp];
        source-port <op> <port>;    # e.g. =53, >1024
        destination-port <op> <port>;
        tcp-flags [syn|ack|fin|rst|...];
        packet-length <op> <len>;
    }
    then {
        discard;                    # Drop matching traffic
        rate-limit <bytes/sec>;     # Rate-limit (e.g. 125000 = 1 Mbps)
    }
}
```

`flowspecd` implements RFC 8955 IPv4 FlowSpec. `discard` becomes an nft `drop`;
`rate-limit` becomes an nft `limit rate over` + `drop`.

## rping Cheat Sheet

`rping` runs inside the `attacker` container (interface `eth0`). Common forms:

```bash
docker exec attacker rping -I eth0 --tcp -S --dst-ip 10.0.2.10 --dst-port 80 --flood   # SYN flood
docker exec attacker rping -I eth0 --udp --dst-ip 10.0.2.10 --dst-port 53 --flood       # UDP flood
docker exec attacker rping -I eth0 --icmp --dst-ip 10.0.2.10 --flood                    # ICMP flood
docker exec attacker rping -I eth0 --tcp -S --src-ip 10.0.1.0/24 --dst-ip 10.0.2.10 --flood  # spoofed sources
```

Useful flags: `-c/--count`, `--duration 10s`, `-i/--interval`, `--flood`,
`--dst-port 1-1024` (ranges), `-d/--data` (payload size). See
`docker exec attacker rping --help`.

## Monitoring

```bash
# Prometheus UI (scrapes router:9100 flowspecd + router:9101 node_exporter)
open http://localhost:9090

# Raw metrics
docker exec router wget -qO- http://127.0.0.1:9100/metrics    # flowspecd
docker exec router wget -qO- http://127.0.0.1:9101/metrics    # node_exporter
```

NetFlow records from the router's `eth0` are exported to the `collector`
container; the collector exposes its own metrics on `:9102`.

## Useful Debug Commands

```bash
# Active FlowSpec-derived nftables rules + counters
docker exec router nft list table inet flowspec
docker exec router nft list ruleset

# flowspecd / ExaBGP logs
docker logs -f router        # BGP FSM, received FlowSpec routes, nft actions
docker logs -f exabgp        # announcements + "[flowspec-api] Sending:" lines

# Packet captures
docker exec router tcpdump -i any -n port 179         # BGP control traffic
docker exec router tcpdump -i any -n host 10.0.2.10   # data plane to target
docker exec target tcpdump -i eth0 -n                 # what reaches the victim
```

## Cleanup

```bash
docker compose down -v
```

## Troubleshooting

**BGP session not establishing:**
- Wait 20–60s after startup.
- `docker logs router` — look for the FSM reaching established / keepalives.
- `docker logs exabgp` — look for `connected to peer-1` and no config errors.
- Connectivity: `docker exec exabgp ping -c1 10.0.3.1`.

**FlowSpec rules not appearing as nft rules:**
- Confirm the BGP session is up first.
- `docker logs exabgp` — confirm `[flowspec-api] Sending:` shows your rule.
- `docker logs router` — confirm `Received UPDATE` / `FlowSpec ADD` / `Applied to nftables`.
- `docker exec router nft list table inet flowspec`.

**Attacker can't reach target:**
- Routes: `docker exec attacker ip route` (default should be via 10.0.1.1).
- Forwarding: `docker exec router sysctl net.ipv4.ip_forward` (should be 1).
- Check no `block-all` rule is still active in `table inet flowspec`.
