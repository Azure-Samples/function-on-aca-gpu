#!/bin/bash
# Azure Functions GPU Image Generation - Deployment Script
# This script deploys the function app to Azure Container Apps with GPU support

set -e

# Configuration - Update these values
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-<your-subscription-id>}"
RESOURCE_GROUP="${RESOURCE_GROUP:-gpu-functions-rg}"
LOCATION="${LOCATION:-swedencentral}"
ACR_NAME="${ACR_NAME:-gpufunctionsacr}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-gpu-functions-env}"
FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-gpu-image-gen-func}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-gpufuncstg$RANDOM}"
IMAGE_NAME="gpu-image-gen"
IMAGE_TAG="latest"

echo "============================================"
echo "GPU Function App Deployment Script"
echo "============================================"
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "ACR: $ACR_NAME"
echo "Environment: $ENVIRONMENT_NAME"
echo "Function App: $FUNCTION_APP_NAME"
echo "============================================"

# Login to Azure (if not already logged in)
echo "Checking Azure login..."
az account show > /dev/null 2>&1 || az login

# Ensure the containerapp extension is up to date (required for --kind functionapp)
echo "Updating Azure CLI containerapp extension..."
az extension add --name containerapp --upgrade --allow-preview true

# Set subscription
echo "Setting subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

# Create Resource Group
echo "Creating resource group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

# Create Azure Container Registry
echo "Creating Azure Container Registry..."
az acr create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ACR_NAME" \
    --sku Standard \
    --admin-enabled false \
    --output none

# Get ACR details
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
ACR_ID=$(az acr show --name "$ACR_NAME" --query id -o tsv)

# Build and push the image
echo "Building and pushing Docker image..."
az acr build \
    --registry "$ACR_NAME" \
    --image "$IMAGE_NAME:$IMAGE_TAG" \
    --file Dockerfile \
    .

# Create Storage Account
echo "Creating storage account..."
az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --output none

STORAGE_CONNECTION=$(az storage account show-connection-string \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query connectionString -o tsv)

# Create Container Apps Environment with GPU workload profile
echo "Creating Container Apps Environment with GPU support..."
az containerapp env create \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --enable-workload-profiles \
    --output none

# Add GPU workload profile
echo "Adding GPU workload profile..."
az containerapp env workload-profile add \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --workload-profile-name "gpu-profile" \
    --workload-profile-type "Consumption-GPU-NC8as-T4" \
    --output none

# Create the Function App on Container Apps with GPU (with system-assigned identity)
echo "Creating Function App on Container Apps with GPU..."
az containerapp create \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ENVIRONMENT_NAME" \
    --image "mcr.microsoft.com/azure-functions/dotnet8-quickstart-demo:1.0" \
    --ingress external \
    --target-port 80 \
    --kind functionapp \
    --workload-profile-name "gpu-profile" \
    --cpu 4 \
    --memory 28Gi \
    --min-replicas 0 \
    --max-replicas 3 \
    --system-assigned \
    --env-vars "MODEL_ID=runwayml/stable-diffusion-v1-5" "FUNCTIONS_WORKER_RUNTIME=python" "AzureWebJobsStorage=$STORAGE_CONNECTION" \
    --output none

# Get the system-assigned identity principal ID
echo "Configuring system-assigned managed identity for ACR access..."
SYSTEM_IDENTITY_PRINCIPAL_ID=$(az containerapp show \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "identity.principalId" -o tsv)

# Assign AcrPull role to system-assigned identity
az role assignment create \
    --assignee "$SYSTEM_IDENTITY_PRINCIPAL_ID" \
    --role "AcrPull" \
    --scope "$ACR_ID" \
    --output none

# Wait for role assignment to propagate
echo "Waiting for role assignment to propagate..."
sleep 30

# Update the container app to use the ACR image with system identity
echo "Updating container app with ACR image..."
az containerapp registry set \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --server "$ACR_LOGIN_SERVER" \
    --identity system \
    --output none

az containerapp update \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --image "$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG" \
    --set-env-vars "MODEL_ID=runwayml/stable-diffusion-v1-5" "FUNCTIONS_WORKER_RUNTIME=python" "AzureWebJobsStorage=$STORAGE_CONNECTION" \
    --output none

# Get the function app URL
FUNCTION_URL=$(az containerapp show \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "properties.configuration.ingress.fqdn" -o tsv)

echo ""
echo "============================================"
echo "Deployment Complete!"
echo "============================================"
echo "Function App URL: https://$FUNCTION_URL"
echo ""
echo "Endpoints:"
echo "  - Web UI: https://$FUNCTION_URL/api/"
echo "  - Generate: https://$FUNCTION_URL/api/generate"
echo "  - Health: https://$FUNCTION_URL/api/health"
echo ""
echo "Test with:"
echo "  curl -X POST https://$FUNCTION_URL/api/generate \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"prompt\": \"A beautiful sunset over mountains\"}'"
echo "============================================"
