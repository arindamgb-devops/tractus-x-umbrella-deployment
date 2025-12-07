#!/usr/bin/env bash

set -e

# Must run as root because we edit /etc/hosts
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo:"
  echo "  sudo $0 [MINIKUBE_IP]"
  exit 1
fi

PROFILE="tractus"   # keep in sync with var.minikube_profile, or make it an env var if you want

IP="$1"

if [ -z "$IP" ]; then
  echo "No IP provided, detecting Minikube IP for profile '$PROFILE'..."
  IP=$(minikube ip -p "$PROFILE")
fi

echo "Using Minikube IP: $IP"
echo

TMP=$(mktemp)

cat <<EOF_HOSTS > "$TMP"
### BEGIN TRACTUS HOSTS
$IP centralidp.tx.test
$IP sharedidp.tx.test
$IP portal.tx.test
$IP portal-backend.tx.test
$IP semantics.tx.test
$IP sdfactory.tx.test
$IP ssi-credential-issuer.tx.test
$IP dataconsumer-1-dataplane.tx.test
$IP dataconsumer-1-controlplane.tx.test
$IP dataprovider-dataplane.tx.test
$IP dataprovider-controlplane.tx.test
$IP dataprovider-submodelserver.tx.test
$IP dataconsumer-2-dataplane.tx.test
$IP dataconsumer-2-controlplane.tx.test
$IP bdrs-server.tx.test
$IP business-partners.tx.test
$IP pgadmin4.tx.test
$IP ssi-dim-wallet-stub.tx.test
$IP smtp.tx.test
$IP dataprovider-registry.tx.test
$IP managed-identity-wallets
$IP dataprovider-dtr.tx.test
$IP dataconsumer-1-submodelserver.tx.test
$IP dataconsumer-1-dtr.tx.test
$IP dataconsumer-2-submodelserver.tx.test
$IP dataconsumer-2-dtr.tx.test
$IP standalone-edc-controlplane.tx.test
$IP standalone-edc-dataplane.tx.test
$IP vault.tx.test
$IP argo.tx.test
### END TRACTUS HOSTS
EOF_HOSTS

# Remove existing managed block if present
sed -i '/^### BEGIN TRACTUS HOSTS$/,/^### END TRACTUS HOSTS$/d' /etc/hosts

# Append new block
cat "$TMP" >> /etc/hosts
rm "$TMP"

echo "Updated /etc/hosts. Current tx.test entries:"
grep 'tx.test' /etc/hosts || true
