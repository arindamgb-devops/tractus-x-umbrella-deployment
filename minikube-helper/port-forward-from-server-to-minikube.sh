#!/usr/bin/env bash
set -euo pipefail

# Minikube profile name (change if needed)
PROFILE="${MINIKUBE_PROFILE:-tractus}"

echo "Detecting Minikube IP for profile '$PROFILE'..."
MINIKUBE_IP="$(minikube ip -p "$PROFILE")"

echo "Using Minikube IP: $MINIKUBE_IP"

# Forward host ports 80 and 443 to Minikube node
sudo socat TCP-LISTEN:80,fork TCP:"$MINIKUBE_IP":80 &
sudo socat TCP-LISTEN:443,fork TCP:"$MINIKUBE_IP":443 &

echo "Started socat forwarders:"
echo "  Host :80  -> $MINIKUBE_IP:80"
echo "  Host :443 -> $MINIKUBE_IP:443"

