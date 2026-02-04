# Build Your Own AI Image Generator with Azure Functions on Container Apps and GPUs 🎨

Ever wanted to create your own AI-powered image generator? In this tutorial, I'll show you how to build one using Azure Functions running on Azure Container Apps with serverless GPUs. The best part? You don't need to worry about managing servers or installing GPU drivers - Azure handles all of that for you!

## What We're Building

We're going to create an API that turns text descriptions into images using Stable Diffusion. Send it a prompt like "a cute robot painting a sunset" and get back a unique AI-generated image!

**Why Azure Functions + GPUs?**

- 🚀 **Fast** - NVIDIA T4 GPUs generate images in seconds
- 💰 **Cost-effective** - Only pay when generating images (scales to zero!)
- 🔧 **Simple** - No GPU drivers or infrastructure to manage
- 📈 **Scalable** - Handles multiple requests automatically

Here's what the final result looks like:

```
POST /api/generate
{
    "prompt": "A friendly robot chef cooking pasta in a cozy kitchen"
}

Response: { "success": true, "image": "base64-encoded-image..." }
```

## Before You Start

You'll need a few things ready:

| What You Need | Why |
|---------------|-----|
| **Azure account** | [Create a free account](https://azure.microsoft.com/free/) if you don't have one |
| **GPU access** | GPUs require special quota approval. [Request access here](https://learn.microsoft.com/en-us/azure/container-apps/gpu-serverless-overview#request-access) - it usually takes a day or two |
| **Azure CLI** | [Download here](https://docs.microsoft.com/cli/azure/install-azure-cli) - this is how we'll deploy everything |

> 💡 **Tip:** Request GPU access first since it takes time to approve. You can read through this tutorial while waiting!

## How It Works

Here's the simple flow:

```
Your App  →  Azure Function on Container Apps  →  Stable Diffusion (on GPU)  →  Image!
   📱                   ⚡                              🎨                       🖼️
```

The magic happens inside an Azure Function running on Azure Container Apps with GPU access. When a request comes in:

1. The function receives your text prompt
2. Stable Diffusion (running on a Tesla T4 GPU) generates the image
3. You get back a base64-encoded PNG image

## Let's Build It! 🛠️

### Step 1: Get the Code

First, grab the sample code from GitHub:

```bash
git clone https://github.com/Azure-Samples/function-on-aca-gpu.git
cd function-on-aca-gpu
```

Here's what's in the project:

```
gpu-function-image-gen/
├── function_app.py      # The main code - handles requests and generates images
├── requirements.txt     # Python packages we need
├── Dockerfile          # Packages everything into a container
├── host.json           # Azure Functions settings
└── deploy.ps1          # One-click deployment script!
```

### Step 2: Understand the Code

Let's look at the key parts. Don't worry - it's simpler than it looks!

**The image generation function** (`function_app.py`):

```python
@app.route(route="generate", methods=["POST"])
def generate_image(req: func.HttpRequest) -> func.HttpResponse:
    # Get the prompt from the request
    req_body = req.get_json()
    prompt = req_body.get('prompt', '')
    
    # Load our AI model (only happens once, then it's cached)
    pipe = get_pipeline()
    
    # Generate the image - this is where the GPU magic happens!
    result = pipe(prompt=prompt, num_inference_steps=25)
    
    # Convert to base64 and send back
    image = result.images[0]
    # ... encoding logic ...
    
    return func.HttpResponse(json.dumps({"success": True, "image": img_base64}))
```

That's it! The heavy lifting is done by the `diffusers` library and the GPU.

### Step 3: Deploy to Azure

You have two options: **command line scripts** (faster, recommended) or the **Azure Portal** (great for learning).

---

#### Option A: Deploy using Command Line 💻

Use our one-click deployment script - it does everything for you!

**On Windows (PowerShell):**

```powershell
cd function-on-aca-gpu
.\deploy.ps1
```

**On Mac/Linux:**

```bash
cd function-on-aca-gpu
chmod +x deploy.sh
./deploy.sh
```

☕ Grab a coffee - this takes about 10-15 minutes. The script will:

1. Create a resource group for all our stuff
2. Set up a container registry to store our Docker image
3. Build and upload the Docker image (no Docker Desktop needed!)
4. Create a Container Apps environment with GPU support
5. Deploy the function app
6. Give you the URL when it's done!

When it finishes, you'll see something like:

```
============================================
🎉 Deployment Complete!
============================================
Function App URL: https://gpu-image-gen-func.jollybay-xxx.swedencentral.azurecontainerapps.io

Endpoints:
  - Generate: https://gpu-image-gen-func.../api/generate
  - Health:   https://gpu-image-gen-func.../api/health
============================================
```

---

#### Option B: Deploy using Azure Portal 🖱️

If you prefer clicking through a UI, follow these steps:

**Part 1: Create a Container Registry**

1. Go to the [Azure Portal](https://portal.azure.com) and search for **Container Registries**
2. Click **+ Create**
3. Fill in the details:

   | Setting | Value |
   |---------|-------|
   | Subscription | Select your subscription |
   | Resource group | Create new → `gpu-functions-rg` |
   | Registry name | `gpufunctionsacr` (must be globally unique) |
   | Location | `Sweden Central` |
   | SKU | `Standard` |

4. Click **Review + create** → **Create**
5. Once created, go to the registry → **Settings** → **Access keys**
6. Enable **Admin user** and note the **Login server**, **Username**, and **Password**

**Part 2: Build and Push the Docker Image**

Since we can't build Docker images directly in the portal, use Azure Cloud Shell:

1. Click the **Cloud Shell** icon (>_) in the top navigation bar
2. Choose **Bash**
3. Navigate to your cloned repo folder (from Step 1) and run:

```bash
cd function-on-aca-gpu

# Build and push to your registry
az acr build --registry gpufunctionsacr --image gpu-image-gen:latest --file Dockerfile .
```

**Part 3: Create a Container Apps Environment with GPU**

1. Search for **Container Apps Environments** and click **+ Create**
2. Fill in the **Basics** tab:

   | Setting | Value |
   |---------|-------|
   | Subscription | Select your subscription |
   | Resource group | `gpu-functions-rg` |
   | Environment name | `gpu-functions-env` |
   | Region | `Sweden Central` |
   | Environment type | `Workload profiles` |

3. Click **Workload profiles** tab → **+ Add workload profile**
4. Configure the GPU profile:

   | Setting | Value |
   |---------|-------|
   | Workload profile name | `gpu-profile` |
   | Workload profile size | `Consumption - GPU NC8as-T4` |

5. Click **Add** → **Review + create** → **Create**

**Part 4: Create the Container App with Azure Functions**

1. Search for **Container Apps** and click **+ Create** → **Container App**
2. Fill in the **Basics** tab:

   | Setting | Value |
   |---------|-------|
   | Subscription | Select your subscription |
   | Resource group | `gpu-functions-rg` |
   | Container app name | `gpu-image-gen-func` |
   | **Optimize for Azure Functions** | ✅ **Check this box!** (This is important - it enables Azure Functions support) |
   | Region | `Sweden Central` |
   | Container Apps Environment | Select `gpu-functions-env` |

3. Click **Next: Container >** and fill in:

   | Setting | Value |
   |---------|-------|
   | Use quickstart image | ❌ Uncheck |
   | Name | `gpu-image-gen-container` |
   | Image source | `Azure Container Registry` |
   | Registry | `gpufunctionsacr` |
   | Image | `gpu-image-gen` |
   | Image tag | `latest` |
   | Workload profile | `gpu-profile` |
   | GPU | ✅ Check this box |

4. Add environment variables at the bottom of the Container tab:

   | Name | Value |
   |------|-------|
   | `MODEL_ID` | `runwayml/stable-diffusion-v1-5` |
   | `FUNCTIONS_WORKER_RUNTIME` | `python` |

5. Click **Next: Ingress >** and configure:

   | Setting | Value |
   |---------|-------|
   | Ingress | ✅ Enabled |
   | Ingress traffic | `Accepting traffic from anywhere` |
   | Target port | `80` |

6. Click **Review + create** → **Create**

🎉 **Done!** Once deployed, find your function URL under **Overview** → **Application Url**

## Test Your Image Generator! 🧪

Now that your function is deployed, let's make sure everything works!

### Check the Health Endpoint

First, verify the GPU is available:

```powershell
Invoke-RestMethod -Uri "https://YOUR-FUNCTION-URL/api/health"
```

You should see:
```json
{
    "status": "healthy",
    "gpu_available": true,
    "gpu_info": {
        "name": "Tesla T4",
        "memory_total_gb": 15.56
    }
}
```

🎉 **GPU detected!** Now let's generate an image.

### Generate Your First Image

```powershell
# Create the request
$body = @{
    prompt = "A happy corgi astronaut floating in space, digital art"
    num_steps = 25
} | ConvertTo-Json

# Call the API
$response = Invoke-RestMethod -Uri "https://YOUR-FUNCTION-URL/api/generate" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body

# Save the image to a file
$imageBytes = [Convert]::FromBase64String($response.image)
[IO.File]::WriteAllBytes("corgi-astronaut.png", $imageBytes)

# Open it!
Start-Process "corgi-astronaut.png"
```

> ⏱️ **First request is slow** (1-2 minutes) because it downloads the AI model (~5GB). After that, images generate in just a few seconds!

## Customize Your Prompts 🎨

Play around with different prompts! Here are some ideas:

| Prompt | What You Get |
|--------|--------------|
| `"A cozy cabin in a snowy forest, warm lighting"` | Peaceful winter scene |
| `"Cyberpunk city at night with neon signs"` | Futuristic cityscape |
| `"Watercolor painting of a cat reading a book"` | Artistic cat portrait |
| `"Steampunk robot serving tea, detailed"` | Victorian-style robot |

**Pro tips for better results:**
- Be specific: "golden retriever" works better than just "dog"
- Add style hints: "digital art", "oil painting", "photograph"
- Describe lighting: "sunset", "dramatic lighting", "soft glow"

## API Reference

Here's everything you can send to the `/api/generate` endpoint:

| Parameter | Type | Default | What It Does |
|-----------|------|---------|--------------|
| `prompt` | string | *required* | Describe what you want to see |
| `negative_prompt` | string | `""` | What to avoid (e.g., "blurry, ugly") |
| `num_steps` | int | `25` | More steps = better quality but slower |
| `guidance_scale` | float | `7.5` | Higher = follows prompt more strictly |
| `width` | int | `512` | Image width (keep at 512 for best results) |
| `height` | int | `512` | Image height |

**Example with all options:**

```json
{
    "prompt": "A magical library with floating books",
    "negative_prompt": "blurry, low quality, distorted",
    "num_steps": 30,
    "guidance_scale": 8.0,
    "width": 512,
    "height": 512
}
```

## Making It Faster ⚡

The first request is slow because of "cold start" - the container needs to start up and load the AI model. Here's how to speed things up:

### Option 1: Keep One Instance Warm

Tell Azure to always keep one container running:

```bash
az functionapp config set \
    --name gpu-image-gen-func \
    --resource-group gpu-functions-rg \
    --min-replicas 1
```

⚠️ **Heads up:** This keeps the GPU running 24/7, which costs more. Great for production, but maybe not for testing.

### Option 2: Enable Artifact Streaming

This makes the container start faster:

```bash
az acr artifact-streaming update \
    --name gpufunctionsacr \
    --repository gpu-image-gen \
    --enable
```

## What About Costs? 💰

Good news - this can be very affordable! Here's where to find pricing for each resource:

| Resource | Pricing Info |
|----------|-------------|
| **Azure Container Apps (GPU)** | [Container Apps Pricing](https://azure.microsoft.com/pricing/details/container-apps/) - GPU workload profiles section |
| **Azure Container Registry** | [ACR Pricing](https://azure.microsoft.com/pricing/details/container-registry/) |
| **Azure Functions** | [Functions Pricing](https://azure.microsoft.com/pricing/details/functions/) - Container Apps hosting |

**Key cost-saving tips:**

- 💡 Set `min-replicas` to **0** during development - you only pay when the function is running!
- 💡 GPU billing is per-second when containers are active
- 💡 Scale to zero means $0 when idle (just wait for cold starts)
- 💡 Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) to estimate your monthly costs

## Clean Up When Done 🧹

Don't want to keep paying? Delete everything with one command:

```bash
az group delete --name gpu-functions-rg --yes
```

This removes all the resources we created. You can always redeploy later!

## Troubleshooting 🔧

**"Model failed to load" error?**
- Some models require a Hugging Face account. We use `runwayml/stable-diffusion-v1-5` which works without authentication.

**Images look weird?**
- Try adding `"blurry, distorted, low quality"` to `negative_prompt`
- Increase `num_steps` to 30 or 40

**Function times out?**
- First request can take 2+ minutes. Be patient!
- Check GPU is available with the `/api/health` endpoint

**GPU not detected?**
- Make sure GPU quota was approved
- Verify `gpu-profile` workload profile was created

## What's Next? 🚀

Now that you have a working image generator, here are some ideas:

- **Build a web UI** - Create a simple HTML page to call your API
- **Try different models** - Swap to SDXL for higher quality images
- **Add image-to-image** - Modify existing images with AI
- **Create a Discord bot** - Let your friends generate images!

## Wrapping Up

You just built your own AI image generator! 🎉 

Here's what we accomplished:
- ✅ Deployed an Azure Function with GPU support
- ✅ Set up Stable Diffusion for image generation  
- ✅ Created a simple API anyone can call
- ✅ Learned how to optimize costs and performance

The full source code is available at: **[github.com/Azure-Samples/function-on-aca-gpu](https://github.com/Azure-Samples/function-on-aca-gpu)**

Have questions or built something cool? I'd love to hear about it!

---

## Resources

- 📚 [Azure Container Apps GPU docs](https://learn.microsoft.com/en-us/azure/container-apps/gpu-serverless-overview)
- 📚 [Azure Functions on Container Apps](https://learn.microsoft.com/en-us/azure/azure-functions/functions-container-apps-hosting)
- 📚 [Stable Diffusion guide](https://huggingface.co/docs/diffusers/using-diffusers/sdxl)
- 💻 [Sample code on GitHub](https://github.com/Azure-Samples/function-on-aca-gpu)
