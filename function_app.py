"""
Azure Functions GPU Image Generation Sample
This function uses Stable Diffusion to generate images from text prompts.
Designed to run on Azure Container Apps with GPU workload profile.
"""

import azure.functions as func
import logging
import json
import base64
import io
import os

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# Global model reference for reuse across invocations
_pipe = None


def get_pipeline():
    """
    Lazy-load the Stable Diffusion pipeline.
    The model is loaded once and cached for subsequent requests.
    """
    global _pipe
    
    if _pipe is None:
        logging.info("Loading Stable Diffusion model...")
        
        import torch
        from diffusers import StableDiffusionPipeline, DPMSolverMultistepScheduler
        
        model_id = os.environ.get("MODEL_ID", "stabilityai/stable-diffusion-2-1-base")
        
        # Check for GPU availability
        device = "cuda" if torch.cuda.is_available() else "cpu"
        logging.info(f"Using device: {device}")
        
        if device == "cuda":
            logging.info(f"GPU: {torch.cuda.get_device_name(0)}")
            logging.info(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.2f} GB")
        
        # Load the pipeline with optimizations
        _pipe = StableDiffusionPipeline.from_pretrained(
            model_id,
            torch_dtype=torch.float16 if device == "cuda" else torch.float32,
            safety_checker=None,  # Disable safety checker for performance
            requires_safety_checker=False
        )
        
        # Use DPM-Solver++ for faster inference
        _pipe.scheduler = DPMSolverMultistepScheduler.from_config(_pipe.scheduler.config)
        
        _pipe = _pipe.to(device)
        
        # Enable memory efficient attention if available
        if device == "cuda":
            try:
                _pipe.enable_xformers_memory_efficient_attention()
                logging.info("xFormers memory efficient attention enabled")
            except Exception as e:
                logging.warning(f"xFormers not available: {e}")
                # Fallback to sliced attention
                _pipe.enable_attention_slicing()
        
        logging.info("Model loaded successfully!")
    
    return _pipe


@app.route(route="generate", methods=["POST", "GET"])
def generate_image(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP trigger function to generate images from text prompts.
    
    POST /api/generate
    Body: {"prompt": "your text prompt", "negative_prompt": "optional", "num_steps": 25, "guidance_scale": 7.5}
    
    GET /api/generate?prompt=your+text+prompt
    
    Returns: JSON with base64-encoded image
    """
    logging.info('Image generation request received.')
    
    try:
        # Parse request parameters
        if req.method == "POST":
            try:
                req_body = req.get_json()
            except ValueError:
                req_body = {}
            
            prompt = req_body.get('prompt', '')
            negative_prompt = req_body.get('negative_prompt', '')
            num_inference_steps = req_body.get('num_steps', 25)
            guidance_scale = req_body.get('guidance_scale', 7.5)
            width = req_body.get('width', 512)
            height = req_body.get('height', 512)
        else:
            prompt = req.params.get('prompt', '')
            negative_prompt = req.params.get('negative_prompt', '')
            num_inference_steps = int(req.params.get('num_steps', 25))
            guidance_scale = float(req.params.get('guidance_scale', 7.5))
            width = int(req.params.get('width', 512))
            height = int(req.params.get('height', 512))
        
        if not prompt:
            return func.HttpResponse(
                json.dumps({"error": "Please provide a 'prompt' parameter"}),
                status_code=400,
                mimetype="application/json"
            )
        
        logging.info(f"Generating image for prompt: {prompt[:100]}...")
        
        # Get the pipeline and generate image
        pipe = get_pipeline()
        
        import torch
        
        # Generate the image
        with torch.inference_mode():
            result = pipe(
                prompt=prompt,
                negative_prompt=negative_prompt if negative_prompt else None,
                num_inference_steps=num_inference_steps,
                guidance_scale=guidance_scale,
                width=width,
                height=height
            )
        
        image = result.images[0]
        
        # Convert to base64
        buffered = io.BytesIO()
        image.save(buffered, format="PNG")
        img_str = base64.b64encode(buffered.getvalue()).decode()
        
        logging.info("Image generated successfully!")
        
        return func.HttpResponse(
            json.dumps({
                "success": True,
                "prompt": prompt,
                "image": img_str,
                "format": "png",
                "width": width,
                "height": height
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f"Error generating image: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """
    Health check endpoint to verify the function is running.
    """
    import torch
    
    gpu_available = torch.cuda.is_available()
    gpu_info = {}
    
    if gpu_available:
        gpu_info = {
            "name": torch.cuda.get_device_name(0),
            "memory_total_gb": round(torch.cuda.get_device_properties(0).total_memory / 1024**3, 2),
            "memory_allocated_gb": round(torch.cuda.memory_allocated(0) / 1024**3, 2),
            "memory_reserved_gb": round(torch.cuda.memory_reserved(0) / 1024**3, 2)
        }
    
    return func.HttpResponse(
        json.dumps({
            "status": "healthy",
            "gpu_available": gpu_available,
            "gpu_info": gpu_info,
            "model_loaded": _pipe is not None
        }),
        status_code=200,
        mimetype="application/json"
    )


@app.route(route="", methods=["GET"])
def index(req: func.HttpRequest) -> func.HttpResponse:
    """
    Root endpoint - returns a simple HTML page with usage instructions.
    """
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>GPU Image Generation - Azure Functions</title>
        <style>
            body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
            h1 { color: #0078d4; }
            .endpoint { background: #f4f4f4; padding: 15px; border-radius: 5px; margin: 10px 0; }
            code { background: #e0e0e0; padding: 2px 6px; border-radius: 3px; }
            textarea { width: 100%; height: 100px; margin: 10px 0; }
            button { background: #0078d4; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }
            button:hover { background: #005a9e; }
            #result { margin-top: 20px; }
            #generatedImage { max-width: 100%; margin-top: 10px; }
        </style>
    </head>
    <body>
        <h1>🎨 GPU Image Generation</h1>
        <p>Powered by Azure Functions on Azure Container Apps with GPU</p>
        
        <h2>Try it out</h2>
        <div>
            <label for="prompt">Enter your prompt:</label>
            <textarea id="prompt" placeholder="A beautiful sunset over mountains, digital art, 4k, highly detailed">A beautiful sunset over mountains, digital art, 4k, highly detailed</textarea>
            <button onclick="generateImage()">Generate Image</button>
            <span id="loading" style="display:none;"> Generating... (this may take 10-30 seconds)</span>
        </div>
        <div id="result"></div>
        
        <h2>API Endpoints</h2>
        <div class="endpoint">
            <h3>POST /api/generate</h3>
            <p>Generate an image from a text prompt</p>
            <pre>
curl -X POST {BASE_URL}/api/generate \\
  -H "Content-Type: application/json" \\
  -d '{"prompt": "A beautiful sunset over mountains"}'
            </pre>
        </div>
        
        <div class="endpoint">
            <h3>GET /api/health</h3>
            <p>Check service health and GPU status</p>
        </div>
        
        <script>
            async function generateImage() {
                const prompt = document.getElementById('prompt').value;
                const loading = document.getElementById('loading');
                const result = document.getElementById('result');
                
                loading.style.display = 'inline';
                result.innerHTML = '';
                
                try {
                    const response = await fetch('/api/generate', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ prompt: prompt })
                    });
                    
                    const data = await response.json();
                    
                    if (data.success) {
                        result.innerHTML = '<h3>Generated Image:</h3><img id="generatedImage" src="data:image/png;base64,' + data.image + '" />';
                    } else {
                        result.innerHTML = '<p style="color:red;">Error: ' + data.error + '</p>';
                    }
                } catch (error) {
                    result.innerHTML = '<p style="color:red;">Error: ' + error.message + '</p>';
                }
                
                loading.style.display = 'none';
            }
        </script>
    </body>
    </html>
    """
    return func.HttpResponse(html_content, mimetype="text/html")
