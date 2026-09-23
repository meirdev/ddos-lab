# DDoS & BGP FlowSpec Mitigation Lab

Six containers simulate traffic generation, routing, FlowSpec mitigation, and
monitoring. The topology is defined in [docker-compose.yml](docker-compose.yml).

## Architecture

```text
attacker                  router                     target
10.0.1.10 ── attack-net ── 10.0.1.1
                           10.0.2.1 ── target-net ── 10.0.2.10
                           10.0.3.1
                               │
                            mgmt-net
                  ┌────────────┼─────────────┐
               exabgp      prometheus     collector
             10.0.3.10     10.0.3.20      10.0.3.40
```

| Container    | Role                                                                                             |
| ------------ | ------------------------------------------------------------------------------------------------ |
| `attacker`   | Generates traffic.                                                                               |
| `router`     | Routes and filters traffic between the attacker and target; exports metrics and NetFlow records. |
| `target`     | Receives traffic                                                                                 |
| `exabgp`     | Announces FlowSpec rules to the router over BGP.                                                 |
| `prometheus` | Scrapes the router's FlowSpec and network-interface metrics.                                     |
| `collector`  | Receives NetFlow records from the router.                                                        |

## Network topology

| Docker bridge network | Subnet        | Connected containers                          |
| --------------------- | ------------- | --------------------------------------------- |
| `attack-net`          | `10.0.1.0/24` | `attacker`, `router`                          |
| `target-net`          | `10.0.2.0/24` | `router`, `target`                            |
| `mgmt-net`            | `10.0.3.0/24` | `router`, `exabgp`, `prometheus`, `collector` |

`attack-net` and `target-net` are internal Docker networks. The attacker uses
`10.0.1.1` as its default gateway, and the target uses `10.0.2.1`, so traffic
between them passes through the router. Docker's bridge gateways use `.254`
on each subnet.

- **Traffic:** `attacker` → `router` → `target`, with replies routed back through
  the router. The router applies FlowSpec rules to drop or rate-limit matching
  traffic.
- **BGP:** `exabgp` (AS 65002) peers with `router` (AS 65001) at
  `10.0.3.1:179`, using IPv4 unicast and FlowSpec address families.
- **Metrics:** `prometheus` scrapes `router:9100` (FlowSpec metrics) and
  `router:9101` (network-interface metrics). Its web interface is published on host port
  `9090`.
- **NetFlow:** The router exports records to `collector:9995`. The collector
  also exposes metrics on port `9102`, which Prometheus does not currently scrape.
