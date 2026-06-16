#!/bin/bash
# =============================================================
#  status.sh — Verify lab health and show key information
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

section() { echo -e "\n${CYAN}═══ $1 ═══${NC}"; }

# ── Container Status ──
section "Container Status"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Networks}}"

# ── Connectivity ──
section "Connectivity (attacker → router → target)"
echo -n "  attacker → router (10.0.1.1):  "
docker exec attacker ping -c1 -W2 10.0.1.1 &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
echo -n "  router   → target (10.0.2.10): "
docker exec router ping -c1 -W2 10.0.2.10 &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
echo -n "  attacker → target (10.0.2.10): "
docker exec attacker ping -c1 -W2 10.0.2.10 &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"

# ── BGP / flowspecd ──
section "flowspecd (router) — last log lines"
docker logs --tail 5 router 2>&1 | grep -E "FSM|Received|FlowSpec|Action|Applied" || echo -e "${YELLOW}No recent flowspecd activity${NC}"

# ── Active nftables rules installed by flowspecd ──
section "Active FlowSpec rules (nftables on router)"
rules=$(docker exec router nft list table inet flowspec 2>/dev/null)
if echo "$rules" | grep -qE "daddr|saddr|drop|limit"; then
    echo "$rules"
else
    echo -e "${YELLOW}None active${NC}"
fi

# ── Monitoring ──
section "Monitoring"
echo -n "  Prometheus (http://localhost:9090):     "
curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy 2>/dev/null | grep -q 200 && echo -e "${GREEN}OK${NC}" || echo -e "${RED}DOWN${NC}"
echo -n "  flowspecd metrics (router:9100):         "
docker exec router wget -qO- http://127.0.0.1:9100/metrics &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}DOWN${NC}"

echo ""
