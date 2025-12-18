"""
API Service for Prompt Injection Detection
FastAPI-based REST API for production deployment
"""

from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, List
import time
from prompt_injection_detector import (
    PromptInjectionDetector,
    PromptSanitizer,
    PromptInjectionMonitor,
    DetectionResult
)

# Initialize FastAPI app
app = FastAPI(
    title="Prompt Injection Detection API",
    description="Multi-layered detection system for LLM prompt injections",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize detector components
detector = PromptInjectionDetector()
sanitizer = PromptSanitizer()
monitor = PromptInjectionMonitor()


# Request/Response Models
class DetectionRequest(BaseModel):
    """Request model for prompt detection"""
    prompt: str = Field(..., description="The prompt to analyze", min_length=1, max_length=10000)
    policy: Optional[str] = Field("standard", description="Detection policy: strict, standard, or permissive")
    sanitize: Optional[bool] = Field(False, description="Whether to return sanitized version")
    
    class Config:
        json_schema_extra = {
            "example": {
                "prompt": "Tell me about the weather",
                "policy": "standard",
                "sanitize": False
            }
        }


class DetectionResponse(BaseModel):
    """Response model for detection results"""
    safe: bool
    threat_level: str
    risk_score: float
    confidence: float
    explanation: str
    detected_patterns: List[str]
    flagged_segments: List[dict]
    sanitized_prompt: Optional[str] = None
    processing_time_ms: float
    
    class Config:
        json_schema_extra = {
            "example": {
                "safe": False,
                "threat_level": "HIGH",
                "risk_score": 85.5,
                "confidence": 0.92,
                "explanation": "Detected instruction override attempt",
                "detected_patterns": ["instruction_override: ignore previous"],
                "flagged_segments": [{"segment": "ignore all", "category": "instruction_override"}],
                "sanitized_prompt": None,
                "processing_time_ms": 12.5
            }
        }


class StatsResponse(BaseModel):
    """Response model for statistics"""
    total_detections: int
    threat_distribution: dict
    avg_risk_score: float
    uptime_seconds: float


# API Key validation (simplified - use proper auth in production)
async def verify_api_key(x_api_key: Optional[str] = Header(None)):
    """Verify API key from header"""
    # In production, validate against database or secret manager
    if x_api_key != "demo-key-12345":  # Replace with real validation
        raise HTTPException(status_code=401, detail="Invalid API key")
    return x_api_key


# Endpoints
@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "service": "Prompt Injection Detection API",
        "status": "healthy",
        "version": "1.0.0"
    }


@app.get("/health")
async def health_check():
    """Detailed health check"""
    return {
        "status": "healthy",
        "detector": "ready",
        "timestamp": time.time()
    }


@app.post("/api/v1/detect", response_model=DetectionResponse)
async def detect_injection(
    request: DetectionRequest,
    api_key: str = Depends(verify_api_key)
):
    """
    Detect prompt injection attempts
    
    Analyzes the provided prompt for potential injection attacks and returns
    a comprehensive risk assessment.
    """
    start_time = time.time()
    
    try:
        # Run detection
        result = detector.detect(request.prompt)
        
        # Log the detection
        monitor.log_detection(request.prompt, result)
        
        # Apply policy adjustments
        if request.policy == "strict":
            # Lower thresholds for strict policy
            pass  # Could adjust risk_score here
        elif request.policy == "permissive":
            # Higher thresholds for permissive policy
            pass
        
        # Sanitize if requested
        sanitized = None
        if request.sanitize and result.threat_level.value > 1:
            sanitized = sanitizer.sanitize(request.prompt, result)
        
        # Calculate processing time
        processing_time = (time.time() - start_time) * 1000
        
        # Build response
        return DetectionResponse(
            safe=result.threat_level.value == 0,
            threat_level=result.threat_level.name,
            risk_score=result.risk_score,
            confidence=result.confidence,
            explanation=result.explanation,
            detected_patterns=result.detected_patterns[:10],  # Limit to first 10
            flagged_segments=result.flagged_segments[:10],
            sanitized_prompt=sanitized,
            processing_time_ms=round(processing_time, 2)
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Detection error: {str(e)}")


@app.post("/api/v1/batch-detect")
async def batch_detect(
    prompts: List[str] = Field(..., max_length=100),
    api_key: str = Depends(verify_api_key)
):
    """
    Batch detection for multiple prompts
    
    Efficiently processes multiple prompts in a single request.
    """
    results = []
    
    for prompt in prompts[:100]:  # Limit to 100 prompts
        result = detector.detect(prompt)
        monitor.log_detection(prompt, result)
        
        results.append({
            "prompt_preview": prompt[:50] + "..." if len(prompt) > 50 else prompt,
            "safe": result.threat_level.value == 0,
            "threat_level": result.threat_level.name,
            "risk_score": result.risk_score
        })
    
    return {"results": results, "total": len(results)}


@app.get("/api/v1/stats", response_model=StatsResponse)
async def get_statistics(api_key: str = Depends(verify_api_key)):
    """
    Get detection statistics
    
    Returns aggregated statistics about all detections performed.
    """
    stats = monitor.get_statistics()
    
    return StatsResponse(
        total_detections=stats.get('total_detections', 0),
        threat_distribution=stats.get('threat_distribution', {}),
        avg_risk_score=stats.get('avg_risk_score', 0.0),
        uptime_seconds=time.time() - app.state.start_time if hasattr(app.state, 'start_time') else 0
    )


@app.get("/api/v1/patterns")
async def get_patterns(
    category: Optional[str] = None,
    api_key: str = Depends(verify_api_key)
):
    """
    Get detection patterns
    
    Returns the patterns used for detection, optionally filtered by category.
    """
    if category:
        if category not in detector.patterns:
            raise HTTPException(status_code=404, detail=f"Category '{category}' not found")
        return {
            "category": category,
            "patterns": detector.patterns[category][:10],  # Limit output
            "weight": detector.weights[category]
        }
    
    # Return all categories summary
    return {
        "categories": list(detector.patterns.keys()),
        "total_patterns": sum(len(p) for p in detector.patterns.values())
    }


@app.on_event("startup")
async def startup_event():
    """Initialize on startup"""
    app.state.start_time = time.time()
    print("Prompt Injection Detection API started")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    print("Prompt Injection Detection API shutting down")


# Run with: uvicorn api_service:app --reload --port 8000
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
