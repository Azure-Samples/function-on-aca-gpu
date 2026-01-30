# GPU Image Generation - Azure Functions on Container Apps

This project demonstrates how to deploy a GPU-accelerated image generation function (using Stable Diffusion) as an Azure Function running on Azure Container Apps with GPU workload profiles.

## 🎯 Overview

This sample is inspired by the [Azure Container Apps GPU Image Generation Tutorial](https://learn.microsoft.com/en-us/azure/container-apps/gpu-image-generation), but modified to run as an **Azure Function** instead of a regular container. This provides:

- **Event-driven scaling** - Scale based on HTTP requests
- **Azure Functions programming model** - Use familiar triggers and bindings
- **GPU acceleration** - Leverage NVIDIA T4 GPUs for fast inference
- **Cost optimization** - Scale to zero when not in use

## 📁 Project Structure

```
gpu-function-image-gen/
├── function_app.py        # Main Azure Functions application code
├── host.json              # Azure Functions host configuration
├── local.settings.json    # Local development settings
├── requirements.txt       # Python dependencies
├── Dockerfile            # GPU-enabled Docker image (Azure Functions base)
├── Dockerfile.nvidia     # Alternative Dockerfile using NVIDIA base
├── deploy.sh             # Bash deployment script
├── deploy.ps1            # PowerShell deployment script
└── README.md             # This file
```

## 🚀 Quick Start

### Prerequisites

1. **Azure subscription** with access to GPU quotas
2. **Azure CLI** installed and configured
3. **Docker** (optional, for local testing)
4. **GPU quota approved** - Submit a request via Azure support for GPU workload profiles

### Deploy to Azure

#### Using PowerShell (Windows):

```powershell
cd gpu-function-image-gen

# Set your subscription ID
$env:SUBSCRIPTION_ID = "<your-subscription-id>"

# Run deployment
.\deploy.ps1
```

#### Using Bash (Linux/macOS/WSL):

```bash
cd gpu-function-image-gen

# Set your subscription ID
export SUBSCRIPTION_ID="<your-subscription-id>"

# Run deployment
chmod +x deploy.sh
./deploy.sh
```

### Manual Deployment Steps

If you prefer to deploy manually:

1. **Create Resource Group and ACR:**
   ```bash
   az group create --name gpu-functions-rg --location swedencentral
   az acr create --resource-group gpu-functions-rg --name gpufunctionsacr --sku Standard --admin-enabled true
   ```

2. **Build and push the Docker image:**
   ```bash
   az acr build --registry gpufunctionsacr --image gpu-image-gen:latest --file Dockerfile .
   ```

3. **Create Container Apps Environment with GPU:**
   ```bash
   az containerapp env create --name gpu-functions-env --resource-group gpu-functions-rg --location swedencentral --enable-workload-profiles
   
   az containerapp env workload-profile add --name gpu-functions-env --resource-group gpu-functions-rg --workload-profile-name gpu-profile --workload-profile-type Consumption-GPU-NC8as-T4
   ```

4. **Create Storage Account:**
   ```bash
   az storage account create --name gpufuncstg123 --resource-group gpu-functions-rg --location swedencentral --sku Standard_LRS
   ```

5. **Deploy Function App:**
   ```bash
   az functionapp create \
       --name gpu-image-gen-func \
       --resource-group gpu-functions-rg \
       --storage-account gpufuncstg123 \
       --environment gpu-functions-env \
       --functions-version 4 \
       --runtime python \
       --image gpufunctionsacr.azurecr.io/gpu-image-gen:latest \
       --registry-server gpufunctionsacr.azurecr.io \
       --registry-username <acr-username> \
       --registry-password <acr-password> \
       --workload-profile-name gpu-profile \
       --cpu 4 \
       --memory 28Gi
   ```

## 📡 API Endpoints

### Generate Image
**POST** `/api/generate`

Generate an image from a text prompt.

**Request Body:**
```json
{
  "prompt": "A beautiful sunset over mountains, digital art, 4k",
  "negative_prompt": "blurry, low quality",
  "num_steps": 25,
  "guidance_scale": 7.5,
  "width": 512,
  "height": 512
}
```

**Response:**
```json
{
  "success": true,
  "prompt": "A beautiful sunset over mountains...",
  "image": "<base64-encoded-png>",
  "format": "png",
  "width": 512,
  "height": 512
}
```

**Example with curl:**
```bash
curl -X POST https://<your-function-app>.azurewebsites.net/api/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "A cute cat wearing a space helmet, digital art"}'
```

### Health Check
**GET** `/api/health`

Check service health and GPU status.

**Response:**
```json
{
  "status": "healthy",
  "gpu_available": true,
  "gpu_info": {
    "name": "Tesla T4",
    "memory_total_gb": 15.0,
    "memory_allocated_gb": 2.5,
    "memory_reserved_gb": 3.0
  },
  "model_loaded": true
}
```

### Web UI
**GET** `/api/`

Access a simple web interface to generate images interactively.

## ⚙️ Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MODEL_ID` | Hugging Face model ID | `stabilityai/stable-diffusion-2-1-base` |
| `AzureWebJobsStorage` | Storage connection string | Required |
| `FUNCTIONS_WORKER_RUNTIME` | Runtime identifier | `python` |

### Supported GPU Workload Profiles

| Profile | GPU | vCPUs | Memory | Best For |
|---------|-----|-------|--------|----------|
| `Consumption-GPU-NC8as-T4` | NVIDIA T4 | 8 | 56 GB | Image generation, inference |
| `Consumption-GPU-NC16as-T4` | NVIDIA T4 | 16 | 110 GB | Larger models |
| `Consumption-GPU-NC24as-T4` | NVIDIA T4 | 24 | 220 GB | Multiple concurrent requests |

### Supported Regions

GPU workload profiles are available in:
- Sweden Central
- West US 3
- Australia East
- East US 2

Check the [official documentation](https://learn.microsoft.com/en-us/azure/container-apps/gpu-serverless-overview) for the latest supported regions.

## 🔧 Local Development

### With GPU (requires NVIDIA GPU and Docker with GPU support):

```bash
# Build the image
docker build -t gpu-image-gen:local -f Dockerfile .

# Run with GPU support
docker run --gpus all -p 7071:80 gpu-image-gen:local
```

### Without GPU (CPU-only, slower):

```bash
# Create virtual environment
python -m venv .venv
.venv\Scripts\activate  # Windows
# or: source .venv/bin/activate  # Linux/macOS

# Install dependencies (CPU-only PyTorch)
pip install -r requirements.txt

# Run locally
func start
```

## 💡 Tips for Better Performance

1. **Reduce cold start time:**
   - Uncomment the model pre-download in Dockerfile
   - Use artifact streaming (enable in Azure Portal)
   - Keep `min-replicas >= 1` for warm instances

2. **Optimize inference:**
   - Enable xFormers for memory-efficient attention
   - Use smaller image dimensions (512x512)
   - Reduce inference steps (20-30 is usually sufficient)

3. **Cost optimization:**
   - Set `min-replicas: 0` when not in use
   - Use appropriate timeout values
   - Monitor GPU utilization

## 📚 Related Resources

- [Azure Functions on Container Apps](https://learn.microsoft.com/en-us/azure/azure-functions/functions-container-apps-hosting)
- [GPU Tutorial (Original Container)](https://learn.microsoft.com/en-us/azure/container-apps/gpu-image-generation)
- [Serverless GPUs Overview](https://learn.microsoft.com/en-us/azure/container-apps/gpu-serverless-overview)
- [Stable Diffusion on Hugging Face](https://huggingface.co/stabilityai/stable-diffusion-2-1-base)

## 🧹 Clean Up

To remove all resources:

```bash
az group delete --name gpu-functions-rg --yes --no-wait
```

## 📄 License

This sample is provided under the MIT license.
