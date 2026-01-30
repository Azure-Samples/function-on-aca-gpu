# GPU-enabled Azure Functions Dockerfile
# Based on Azure Functions Python base image
# GPU drivers are provided by the Azure Container Apps GPU workload profile

# Use standard Azure Functions Python image
# GPU support comes from the ACA GPU workload profile (NC8as-T4)
FROM mcr.microsoft.com/azure-functions/python:4-python3.11

# Set environment variables for GPU (provided by ACA GPU workload profile)
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Set environment variables for Azure Functions
ENV AzureWebJobsScriptRoot=/home/site/wwwroot
ENV AzureFunctionsJobHost__Logging__Console__IsEnabled=true
ENV FUNCTIONS_WORKER_RUNTIME=python

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    wget \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /home/site/wwwroot

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy function app code
COPY . .

# Pre-download the model during build (optional - makes cold start faster)
# Uncomment the following lines to include the model in the image
# This increases image size but reduces cold start time
# RUN python -c "from diffusers import StableDiffusionPipeline; StableDiffusionPipeline.from_pretrained('stabilityai/stable-diffusion-2-1-base')"

# Expose the default Azure Functions port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:80/api/health || exit 1
