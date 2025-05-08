#!/bin/bash
# File: setup-keyvault.sh

# Exit on critical errors
set -e

# Variables (replace with your values)
SUBSCRIPTION_ID="96dd7bbb-5319-4ad7-93a1-ff1de8e90a9b"
RESOURCE_GROUP="keyvaultproject"
LOCATION="canadacentral"
KEY_VAULT_NAME="Vault-test-ca-cen"
WEBAPP_NAME="projet01-$(date +%s)" # Unique name to avoid conflicts
SQL_SERVER_NAME="AppDBserver-test-ca-cn"
DATABASE_NAME="testDB"
SQL_ADMIN_USER="myUser" # Replace with actual SQL admin user
SQL_ADMIN_PASSWORD="SecurePass123!" # Replace with a strong password (8+ chars, mixed case, numbers, symbols)

# Basic check for Azure CLI login
az account show >/dev/null 2>&1 || { echo "Error: Run 'az login' first."; exit 1; }

# Create Resource Group
echo "Creating resource group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Create SQL Server
echo "Creating SQL Server $SQL_SERVER_NAME..."
az sql server create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SQL_SERVER_NAME" \
  --location "$LOCATION" \
  --admin-user "$SQL_ADMIN_USER" \
  --admin-password "$SQL_ADMIN_PASSWORD"

# Create SQL Database
echo "Creating SQL Database $DATABASE_NAME..."
az sql db create \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name "$DATABASE_NAME" \
  --service-objective S0

# Configure firewall rule to allow Azure services
echo "Creating firewall rule to allow Azure services..."
az sql server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Generate and customize ODBC connection string
echo "Generating ODBC connection string..."
CONNECTION_STRING=$(az sql db show-connection-string \
  --server "$SQL_SERVER_NAME.database.windows.net" \
  --name "$DATABASE_NAME" \
  --client odbc \
  -o tsv)
CONNECTION_STRING=$(echo "$CONNECTION_STRING" | sed "s/<username>/$SQL_ADMIN_USER/" | sed "s/<password>/$SQL_ADMIN_PASSWORD/")
CONNECTION_STRING=$(echo "$CONNECTION_STRING" | sed "s/ODBC Driver 13/ODBC Driver 18/" | sed "s/\.database\.windows\.net\.database\.windows\.net/\.database\.windows\.net/")

# Check for soft-deleted Key Vault
if az keyvault list-deleted --query "[?name=='$KEY_VAULT_NAME']" | grep "$KEY_VAULT_NAME" >/dev/null; then
  echo "Purging soft-deleted Key Vault $KEY_VAULT_NAME..."
  az keyvault purge --name "$KEY_VAULT_NAME" --location "$LOCATION"
fi

# Create Key Vault
echo "Creating Key Vault $KEY_VAULT_NAME..."
az keyvault create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$KEY_VAULT_NAME" \
  --location "$LOCATION" \
  --enable-rbac-authorization false

# Store connection string in Key Vault
echo "Storing connection string in Key Vault..."
az keyvault secret set \
  --vault-name "$KEY_VAULT_NAME" \
  --name "DbConnectionString" \
  --value "$CONNECTION_STRING"

# Create App Service Plan
echo "Creating App Service Plan..."
az appservice plan create \
  --resource-group "$RESOURCE_GROUP" \
  --name "MyAppServicePlan" \
  --location "$LOCATION" \
  --sku S1 \
  --is-linux

# Check if Web App exists
if az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" >/dev/null 2>&1; then
  echo "Web App $WEBAPP_NAME already exists in $RESOURCE_GROUP, skipping creation..."
else
  echo "Creating Web App $WEBAPP_NAME..."
  az webapp create \
    --resource-group "$RESOURCE_GROUP" \
    --plan "MyAppServicePlan" \
    --name "$WEBAPP_NAME" \
    --runtime "PYTHON|3.9"
fi

# Enable Managed Identity
echo "Enabling Managed Identity..."
az webapp identity assign \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEBAPP_NAME"

# Get Managed Identity principalId
echo "Retrieving Managed Identity principalId..."
PRINCIPAL_ID=$(az webapp identity show --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --query principalId -o tsv)

# Set Key Vault access policy
echo "Setting Key Vault access policy..."
az keyvault set-policy \
  --resource-group "$RESOURCE_GROUP" \
  --name "$KEY_VAULT_NAME" \
  --object-id "$PRINCIPAL_ID" \
  --secret-permissions get list

# Output instructions
echo "Setup complete!"
echo "Key Vault URL: https://$KEY_VAULT_NAME.vault.azure.net/"
echo "Web App URL: https://$WEBAPP_NAME.azurewebsites.net/"
echo "For local development, run 'az login' and 'python app.py'."
echo "For production, ensure AZURE_ENVIRONMENT=production is set in App Service Application Settings."
echo "SQL Server access is configured with a firewall rule allowing Azure services. For production, consider restricting to specific IPs."