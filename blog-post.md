# Build Your Own AI Image Generator with Azure Functions and GPUs 🎨

Ever wanted to create your own AI-powered image generator? In this tutorial, I'll show you how to build one using Azure Functions and serverless GPUs. The best part? You don't need to worry about managing servers or installing GPU drivers - Azure handles all of that for you!

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
Your App  →  Azure Function  →  Stable Diffusion (on GPU)  →  Image!
   📱            ⚡                    🎨                      🖼️
```

The magic happens inside an Azure Function running on a container with GPU access. When a request comes in:

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

Or if you want to build from scratch, here's what's in the project:

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

This is the fun part! We'll use a script that does everything for you.

**On Windows (PowerShell):**

```powershell
cd gpu-function-image-gen
.\deploy.ps1
```

**On Mac/Linux:**

```bash
cd gpu-function-image-gen
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

### Step 4: Test Your Image Generator!

Let's make sure everything works. First, check the health endpoint:

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

🎉 **GPU detected!** Now let's generate an image:

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

Good news - this can be very affordable! Here's the breakdown:

| What | Cost |
|------|------|
| **GPU compute** | ~$0.75/hour when running |
| **Scale to zero** | $0 when idle (if min-replicas=0) |
| **Container Registry** | ~$5/month for storage |
| **Storage Account** | A few cents/month |

**My tip:** Set `min-replicas` to 0 during development. You'll wait a bit for cold starts, but you won't pay when you're not using it!

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
