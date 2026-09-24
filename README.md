# DDoS & BGP FlowSpec Mitigation Lab

Five containers simulate traffic generation, routing, FlowSpec mitigation, and
NetFlow collection. The topology is defined in [docker-compose.yml](docker-compose.yml).

## Architecture

```text
attacker                  router (AS 65001)          target
10.0.1.10 ── attack-net ── 10.0.1.1
                           10.0.2.1 ── target-net ── 10.0.2.10
                           10.0.3.1
                               │
                            mgmt-net
                  ┌────────────┴─────────────┐
               exabgp                     collector
             (AS 65002)
             10.0.3.10                  10.0.3.40
```

| Container    | Role                                                                                             |
| ------------ | ------------------------------------------------------------------------------------------------ |
| `attacker`   | Generates traffic.                                                                               |
| `router`     | Routes and filters traffic between the attacker and target; exports metrics and NetFlow records. |
| `target`     | Receives traffic                                                                                 |
| `exabgp`     | Announces FlowSpec rules to the router over BGP.                                                 |
| `collector`  | Receives NetFlow records from the router.                                                        |

## Network topology

| Docker bridge network | Subnet        | Connected containers                          |
| --------------------- | ------------- | --------------------------------------------- |
| `attack-net`          | `10.0.1.0/24` | `attacker`, `router`                          |
| `target-net`          | `10.0.2.0/24` | `router`, `target`                            |
| `mgmt-net`            | `10.0.3.0/24` | `router`, `exabgp`, `collector`               |

`attack-net` and `target-net` are internal Docker networks. The attacker uses
`10.0.1.1` as its default gateway, and the target uses `10.0.2.1`, so traffic
between them passes through the router. Docker's bridge gateways use `.254`
on each subnet.
