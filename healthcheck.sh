#!/usr/bin/bash


# Exit codes:
# 0 = healthy
# 1 = unhealthy

set -e

# Set default ports
SABLIER_PORT=${SABLIER_PORT:-10000}
CADDY_PORT=${CADDY_PORT:-2019}
TAILNET_PORT=${TAILNET_PORT:-2019}

# Track overall health status
HEALTHY=0

# Check Sablier health (if installed)
if [ -f /usr/bin/sablier ]; then
  echo "Checking Sablier health on port ${SABLIER_PORT}..."
  if ! curl -sf -o /dev/null http://localhost:${SABLIER_PORT}/health; then
    echo "ERROR: Sablier health check failed"
    HEALTHY=1
  else
    echo "✓ Sablier is healthy"
  fi
fi

# Check Caddy health
echo "Checking Caddy health on port ${CADDY_PORT}..."
if ! curl -sf -o /dev/null http://localhost:${CADDY_PORT}/config; then
  echo "ERROR: Caddy health check failed"
  HEALTHY=1
else
  echo "✓ Caddy is healthy"
fi

# Check Tailscale health
echo "Checking Tailscale health..."
if ! tailscale status --json | jq -e '.Self.Online == true' > /dev/null; then
  echo "ERROR: Tailscale is not online"
  HEALTHY=1
else
  echo "✓ Tailscale is online"
fi

# Exit with appropriate status
if [ $HEALTHY -eq 0 ]; then
  echo "All services are healthy"
  exit 0
else
  echo "One or more services are unhealthy"
  exit 1
fi
