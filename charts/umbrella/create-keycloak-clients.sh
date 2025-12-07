#!/bin/bash

# ----------------------------
# Configuration
# ----------------------------
KEYCLOAK_URL="http://centralidp.tx.test/auth/"
REALM="CX-Central"
USERNAME="admin"
PASSWORD="adminconsolepwcentralidp"

# Kubernetes namespace
K8S_NAMESPACE="tractus-x"

# ----------------------------
# Helper: Get Admin Access Token
# ----------------------------
TOKEN=$(curl -s \
  -d "client_id=admin-cli" \
  -d "username=${USERNAME}" \
  -d "password=${PASSWORD}" \
  -d "grant_type=password" \
  "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
  echo "❌ Failed to get admin token"
  exit 1
fi
echo "✔ Logged in to Keycloak"

# ----------------------------
# Function: Create Client
# ----------------------------
create_client() {
  CLIENT_ID="$1"
  REDIRECT_URI="$2"
  WEB_ORIGIN="$3"

  echo "➡ Creating client: $CLIENT_ID"

  CREATE_PAYLOAD=$(jq -n \
    --arg clientId "$CLIENT_ID" \
    --arg redirect "$REDIRECT_URI" \
    --arg origin "$WEB_ORIGIN" \
    '{
      clientId: $clientId,
      protocol: "openid-connect",
      publicClient: false,
      serviceAccountsEnabled: true,
      redirectUris: [$redirect],
      webOrigins: [$origin]
    }')

  curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CREATE_PAYLOAD" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients"  
}

# ----------------------------
# Function: Get Client Secret
# ----------------------------
get_client_secret() {
  CLIENT_ID="$1"

  echo "➡ Retrieving secret for: $CLIENT_ID"

  # Get internal Keycloak client UUID
  ID=$(curl -s \
    -H "Authorization: Bearer $TOKEN" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}" \
    | jq -r '.[0].id')

  if [[ -z "$ID" || "$ID" == "null" ]]; then
    echo "❌ Failed to fetch client ID"
    exit 1
  fi

  # Get secret
  SECRET=$(curl -s \
    -H "Authorization: Bearer $TOKEN" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${ID}/client-secret" \
    | jq -r '.value')

  echo "$SECRET"
}

# ----------------------------
# Create Clients
# ----------------------------

create_client "Cl8-CX-DataProvider" \
  "http://dataprovider-controlplane.tx.test/*" \
  "http://dataprovider-controlplane.tx.test"

create_client "Cl9-CX-DataConsumer1" \
  "http://dataconsumer-1-controlplane.tx.test/*" \
  "http://dataconsumer-1-controlplane.tx.test"

# ----------------------------
# Get Secrets
# ----------------------------
DATA_PROVIDER_SECRET=$(get_client_secret "Cl8-CX-DataProvider")
DATA_CONSUMER1_SECRET=$(get_client_secret "Cl9-CX-DataConsumer1")

echo "✔ Data Provider Secret = $DATA_PROVIDER_SECRET"
echo "✔ Data Consumer 1 Secret = $DATA_CONSUMER1_SECRET"

# ----------------------------
# Create Kubernetes Secrets
# ----------------------------

echo "➡ Creating Kubernetes secrets..."

kubectl create secret generic dataprovider-client-secret \
  --from-literal=client-secret="$DATA_PROVIDER_SECRET" \
  -n "$K8S_NAMESPACE"

kubectl create secret generic dataconsumer1-client-secret \
  --from-literal=client-secret="$DATA_CONSUMER1_SECRET" \
  -n "$K8S_NAMESPACE"

echo "✔ Kubernetes secrets created successfully!"

