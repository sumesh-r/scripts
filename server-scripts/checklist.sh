#!/bin/bash

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

FAILED=0

echo "===================================="
echo "  Production Server Validation"
echo "===================================="
echo ""

mark_fail() {
  FAILED=1
}

# -----------------------------
# Node.js
# -----------------------------
if command -v node >/dev/null 2>&1; then
  echo -e "Node.js: ${GREEN}✔ Installed ($(node -v))${NC}"
else
  echo -e "Node.js: ${RED}✘ Not Installed${NC}"
  mark_fail
fi

# -----------------------------
# PM2
# -----------------------------
if command -v pm2 >/dev/null 2>&1; then
  echo -e "PM2: ${GREEN}✔ Installed (v$(pm2 -v))${NC}"
else
  echo -e "PM2: ${RED}✘ Not Installed${NC}"
  mark_fail
fi

# -----------------------------
# Apache
# -----------------------------
if systemctl list-unit-files | grep -qE "apache2.service|httpd.service"; then
  if systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet httpd 2>/dev/null; then
    echo -e "Apache: ${GREEN}✔ Installed & Running${NC}"
  else
    echo -e "Apache: ${YELLOW}⚠ Installed but NOT Running${NC}"
    mark_fail
  fi
else
  echo -e "Apache: ${RED}✘ Not Installed${NC}"
  mark_fail
fi

# -----------------------------
# Domain Mapping
# -----------------------------
# -----------------------------
# Domain Mapping (IPv4 Only)
# -----------------------------
read -p "Enter domain to validate: " DOMAIN

# Get server public IPv4
SERVER_IP=$(curl -4 -s https://ifconfig.me)

# Get domain IPv4 (A record only)
DOMAIN_IP=$(dig +short A $DOMAIN | tail -n1)

echo ""
echo "Checking domain mapping (IPv4)..."

if [ -z "$DOMAIN_IP" ]; then
  echo -e "Domain: ${RED}✘ Does not resolve to IPv4 (A record missing)${NC}"
  mark_fail
elif [ "$SERVER_IP" == "$DOMAIN_IP" ]; then
  echo -e "Domain: ${GREEN}✔ Points to this server ($SERVER_IP)${NC}"
else
  echo -e "Domain: ${YELLOW}⚠ Resolves to $DOMAIN_IP (Server IPv4: $SERVER_IP)${NC}"
  mark_fail
fi


# -----------------------------
# Port Check
# -----------------------------
echo ""
echo "Checking open ports..."

if nc -z -w3 $DOMAIN 80 >/dev/null 2>&1; then
  echo -e "Port 80: ${GREEN}✔ Open${NC}"
else
  echo -e "Port 80: ${RED}✘ Closed${NC}"
  mark_fail
fi

if nc -z -w3 $DOMAIN 443 >/dev/null 2>&1; then
  echo -e "Port 443: ${GREEN}✔ Open${NC}"
else
  echo -e "Port 443: ${RED}✘ Closed${NC}"
  mark_fail
fi

# -----------------------------
# HTTP → HTTPS Redirect
# -----------------------------
echo ""
echo "Checking HTTP → HTTPS redirect..."

if curl -s -I http://$DOMAIN | grep -q "Location: https://"; then
  echo -e "Redirect: ${GREEN}✔ HTTP redirects to HTTPS${NC}"
else
  echo -e "Redirect: ${YELLOW}⚠ No HTTPS redirect detected${NC}"
  mark_fail
fi

# -----------------------------
# SSL Check
# -----------------------------
echo ""
echo "Checking SSL certificate..."

SSL_OUTPUT=$(echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null)

if [ -z "$SSL_OUTPUT" ]; then
  echo -e "SSL: ${RED}✘ No certificate found${NC}"
  mark_fail
else
  CERT_INFO=$(echo "$SSL_OUTPUT" | openssl x509 -noout -issuer -dates 2>/dev/null)

  EXPIRY_DATE=$(echo "$CERT_INFO" | grep notAfter | cut -d= -f2)
  EXPIRY_TIMESTAMP=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
  CURRENT_TIMESTAMP=$(date +%s)

  if [ -n "$EXPIRY_TIMESTAMP" ]; then
    DAYS_LEFT=$(( ($EXPIRY_TIMESTAMP - $CURRENT_TIMESTAMP) / 86400 ))

    if [ "$DAYS_LEFT" -gt 30 ]; then
      echo -e "SSL Validity: ${GREEN}✔ Valid ($DAYS_LEFT days left)${NC}"
    elif [ "$DAYS_LEFT" -gt 0 ]; then
      echo -e "SSL Validity: ${YELLOW}⚠ Expiring soon ($DAYS_LEFT days)${NC}"
      mark_fail
    else
      echo -e "SSL Validity: ${RED}✘ Expired${NC}"
      mark_fail
    fi
  else
    echo -e "SSL: ${RED}✘ Unable to determine expiry${NC}"
    mark_fail
  fi

  if echo "$CERT_INFO" | grep -q "Let's Encrypt"; then
    echo -e "SSL Provider: ${GREEN}✔ Let's Encrypt${NC}"
  else
    echo -e "SSL Provider: ${YELLOW}⚠ Custom / Other CA${NC}"
  fi

  if echo "$SSL_OUTPUT" | grep -q "Verify return code: 0 (ok)"; then
    echo -e "SSL Chain: ${GREEN}✔ Certificate chain valid${NC}"
  else
    echo -e "SSL Chain: ${RED}✘ Certificate chain invalid${NC}"
    mark_fail
  fi
fi

# -----------------------------
# SSH Security Check
# -----------------------------
echo ""
echo "Checking SSH configuration..."

SSHD_CONFIG="/etc/ssh/sshd_config"

if grep -q "^PasswordAuthentication no" $SSHD_CONFIG; then
  echo -e "SSH Password Login: ${GREEN}✔ Disabled${NC}"
else
  echo -e "SSH Password Login: ${RED}✘ Enabled${NC}"
  mark_fail
fi

if grep -q "^PermitRootLogin no" $SSHD_CONFIG; then
  echo -e "Root Login: ${GREEN}✔ Disabled${NC}"
else
  echo -e "Root Login: ${RED}✘ Enabled${NC}"
  mark_fail
fi


# -----------------------------
# Disk Usage
# -----------------------------
echo ""
echo "Checking disk usage..."

DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$DISK_USAGE" -lt 80 ]; then
  echo -e "Disk Usage: ${GREEN}✔ Healthy (${DISK_USAGE}% used)${NC}"
else
  echo -e "Disk Usage: ${RED}✘ High usage (${DISK_USAGE}% used)${NC}"
  mark_fail
fi

# -----------------------------
# Local Port Check
# -----------------------------
echo ""
echo "Checking listening ports..."

if ss -tuln | grep -q ":22 "; then
  echo -e "Port 22 (SSH): ${GREEN}✔ Listening${NC}"
else
  echo -e "Port 22 (SSH): ${RED}✘ Not listening${NC}"
  mark_fail
fi

if ss -tuln | grep -q ":80 "; then
  echo -e "Port 80: ${GREEN}✔ Listening${NC}"
else
  echo -e "Port 80: ${RED}✘ Not listening${NC}"
  mark_fail
fi

if ss -tuln | grep -q ":443 "; then
  echo -e "Port 443: ${GREEN}✔ Listening${NC}"
else
  echo -e "Port 443: ${RED}✘ Not listening${NC}"
  mark_fail
fi

# -----------------------------
# Database Port Exposure
# -----------------------------
echo ""
echo "Checking database port exposure..."

if ss -tuln | grep -q ":5432 "; then
  echo -e "PostgreSQL (5432): ${YELLOW}⚠ Listening locally${NC}"
fi

if ss -tuln | grep -q ":1433 "; then
  echo -e "MSSQL (1433): ${YELLOW}⚠ Listening locally${NC}"
fi

# Check if bound to 0.0.0.0 (public)
if ss -tuln | grep -q "0.0.0.0:5432"; then
  echo -e "PostgreSQL Public Exposure: ${RED}✘ Exposed to public network${NC}"
  mark_fail
fi

if ss -tuln | grep -q "0.0.0.0:1433"; then
  echo -e "MSSQL Public Exposure: ${RED}✘ Exposed to public network${NC}"
  mark_fail
fi

# -----------------------------
# Apache Proxy Modules
# -----------------------------
echo ""
echo "Checking Apache proxy modules..."

if apachectl -M 2>/dev/null | grep -q "proxy_module"; then
  echo -e "proxy_module: ${GREEN}✔ Enabled${NC}"
else
  echo -e "proxy_module: ${RED}✘ Not enabled${NC}"
  mark_fail
fi

if apachectl -M 2>/dev/null | grep -q "proxy_http_module"; then
  echo -e "proxy_http_module: ${GREEN}✔ Enabled${NC}"
else
  echo -e "proxy_http_module: ${RED}✘ Not enabled${NC}"
  mark_fail
fi


# -----------------------------
# Final Summary
# -----------------------------
echo ""
echo "===================================="

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}✔ All checks passed successfully.${NC}"
  EXIT_CODE=0
else
  echo -e "${RED}✘ Some checks failed. Please review warnings above.${NC}"
  EXIT_CODE=1
fi

echo "===================================="

exit $EXIT_CODE
