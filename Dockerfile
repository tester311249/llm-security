# Multi-stage Docker build for prompt injection detector

# Stage 1: Builder
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

LABEL maintainer="your-email@example.com"
LABEL description="Prompt Injection Detection API Service"
LABEL version="1.0.0"

# Create non-root user
RUN useradd -m -u 1000 appuser

WORKDIR /app

# Copy Python dependencies from builder
COPY --from=builder /install /usr/local

# Copy application files
COPY prompt_injection_detector.py .
COPY api_service.py .

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose API port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

# Run the API service
CMD ["python", "-m", "uvicorn", "api_service:app", "--host", "0.0.0.0", "--port", "8000"]
