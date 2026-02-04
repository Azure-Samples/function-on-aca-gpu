# Azure Functions GPU Image Generation - PowerShell Deployment Script
# This script deploys the function app to Azure Container Apps with GPU support

param(
    [string]$SubscriptionId = $env:SUBSCRIPTION_ID,
    [string]$ResourceGroup = "gpu-functions-rg",
    [string]$Location = "swedencentral",
    [string]$AcrName = "gpufunctionsacr",
    [string]$EnvironmentName = "gpu-functions-env",
    [string]$FunctionAppName = "gpu-image-gen-func",
    [string]$StorageAccount = "gpufuncstg$(Get-Random -Maximum 9999)",
    [string]$ImageName = "gpu-image-gen",
    [string]$ImageTag = "latest"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "GPU Function App Deployment Script" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location: $Location"
Write-Host "ACR: $AcrName"
Write-Host "Environment: $EnvironmentName"
Write-Host "Function App: $FunctionAppName"
Write-Host "============================================" -ForegroundColor Cyan

# Check Azure CLI login
Write-Host "Checking Azure login..." -ForegroundColor Yellow
try {
    az account show | Out-Null
} catch {
    Write-Host "Logging into Azure..." -ForegroundColor Yellow
    az login
}

# Set subscription
if ($SubscriptionId) {
    Write-Host "Setting subscription..." -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
}

# Create Resource Group
Write-Host "Creating resource group..." -ForegroundColor Yellow
az group create `
    --name $ResourceGroup `
    --location $Location `
    --output none

# Create Azure Container Registry
Write-Host "Creating Azure Container Registry..." -ForegroundColor Yellow
az acr create `
    --resource-group $ResourceGroup `
    --name $AcrName `
    --sku Standard `
    --admin-enabled true `
    --output none

# Get ACR credentials
$AcrLoginServer = az acr show --name $AcrName --query loginServer -o tsv
$AcrUsername = az acr credential show --name $AcrName --query username -o tsv
$AcrPassword = az acr credential show --name $AcrName --query "passwords[0].value" -o tsv

# Build and push the image
Write-Host "Building and pushing Docker image..." -ForegroundColor Yellow
az acr build `
    --registry $AcrName `
    --image "${ImageName}:${ImageTag}" `
    --file Dockerfile `
    .

# Create Storage Account (with public access disabled per Azure Policy)
Write-Host "Creating storage account..." -ForegroundColor Yellow
az storage account create `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard_LRS `
    --allow-blob-public-access false `
    --output none

$StorageConnection = az storage account show-connection-string `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --query connectionString -o tsv

# Create Container Apps Environment with GPU workload profile
Write-Host "Creating Container Apps Environment with GPU support..." -ForegroundColor Yellow
az containerapp env create `
    --name $EnvironmentName `
    --resource-group $ResourceGroup `
    --location $Location `
    --enable-workload-profiles `
    --output none

# Add GPU workload profile
Write-Host "Adding GPU workload profile..." -ForegroundColor Yellow
az containerapp env workload-profile add `
    --name $EnvironmentName `
    --resource-group $ResourceGroup `
    --workload-profile-name "gpu-profile" `
    --workload-profile-type "Consumption-GPU-NC8as-T4" `
    --output none

# Create the Function App on Container Apps with GPU
Write-Host "Creating Function App on Container Apps with GPU..." -ForegroundColor Yellow
az functionapp create `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --storage-account $StorageAccount `
    --environment $EnvironmentName `
    --functions-version 4 `
    --runtime python `
    --image "$AcrLoginServer/${ImageName}:${ImageTag}" `
    --registry-server $AcrLoginServer `
    --registry-username $AcrUsername `
    --registry-password $AcrPassword `
    --workload-profile-name "gpu-profile" `
    --cpu 4 `
    --memory 28Gi `
    --min-replicas 0 `
    --max-replicas 3 `
    --output none

# Configure app settings
Write-Host "Configuring app settings..." -ForegroundColor Yellow
az functionapp config appsettings set `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --settings `
        "MODEL_ID=stabilityai/stable-diffusion-2-1-base" `
        "FUNCTIONS_WORKER_RUNTIME=python" `
        "AzureWebJobsStorage=$StorageConnection" `
    --output none

# Get the function app URL
$FunctionUrl = az functionapp show `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --query "defaultHostName" -o tsv

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Function App URL: https://$FunctionUrl" -ForegroundColor White
Write-Host ""
Write-Host "Endpoints:" -ForegroundColor White
Write-Host "  - Web UI: https://$FunctionUrl/api/" -ForegroundColor White
Write-Host "  - Generate: https://$FunctionUrl/api/generate" -ForegroundColor White
Write-Host "  - Health: https://$FunctionUrl/api/health" -ForegroundColor White
Write-Host ""
Write-Host "Test with:" -ForegroundColor Yellow
Write-Host "  Invoke-RestMethod -Uri 'https://$FunctionUrl/api/generate' ``" -ForegroundColor Gray
Write-Host "    -Method POST ``" -ForegroundColor Gray
Write-Host "    -ContentType 'application/json' ``" -ForegroundColor Gray
Write-Host "    -Body '{`"prompt`": `"A beautiful sunset over mountains`"}'" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Green
