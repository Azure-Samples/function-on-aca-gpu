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
    --admin-enabled true \
    --output none

# Get ACR credentials
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query passwords[0].value -o tsv)

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

# Create the Function App on Container Apps with GPU
echo "Creating Function App on Container Apps with GPU..."
az containerapp create \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ENVIRONMENT_NAME" \
    --image "$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" \
    --registry-password "$ACR_PASSWORD" \
    --ingress external \
    --target-port 80 \
    --kind functionapp \
    --workload-profile-name "gpu-profile" \
    --cpu 4 \
    --memory 28Gi \
    --min-replicas 0 \
    --max-replicas 3 \
    --env-vars "MODEL_ID=runwayml/stable-diffusion-v1-5" "FUNCTIONS_WORKER_RUNTIME=python" "AzureWebJobsStorage=$STORAGE_CONNECTION" \
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
