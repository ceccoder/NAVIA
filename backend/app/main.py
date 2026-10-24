"""FastAPI application entrypoint for the NAVIA Indoor Navigation Backend."""
from typing import List, Dict, Any
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

from app.models import (
    RouteRequest,
    RouteResponse,
    NodeInfo,
    BuildingSummary
)
from app.graph_engine import IndoorGraphEngine

app = FastAPI(
    title="NAVIA Indoor Navigation Graph API",
    description="High-precision routing engine with accessibility pruning and wearable haptic directions",
    version="1.0.0"
)

import os

# Enable CORS for Flutter mobile apps and web tools (configurable via environment)
cors_origins_env = os.getenv("CORS_ORIGINS", "*")
allowed_origins = [orig.strip() for orig in cors_origins_env.split(",") if orig.strip()] if cors_origins_env != "*" else ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize indoor graph engine
graph_engine = IndoorGraphEngine()


@app.get("/health", tags=["System"])
def health_check() -> Dict[str, Any]:
    """Liveness probe verifying service availability."""
    return {
        "status": "healthy",
        "service": "NAVIA-Backend",
        "version": "1.0.0",
        "building_loaded": graph_engine.building_id
    }


@app.get("/api/v1/buildings", response_model=List[BuildingSummary], tags=["Metadata"])
def get_buildings() -> List[BuildingSummary]:
    """Lists indexed building models."""
    return [graph_engine.get_building_summary()]


@app.get("/api/v1/nodes", response_model=List[NodeInfo], tags=["Metadata"])
def get_nodes() -> List[NodeInfo]:
    """Returns available destination rooms, landmarks, and OCR sign markers."""
    return graph_engine.list_nodes()


@app.post(
    "/api/v1/route",
    response_model=RouteResponse,
    status_code=status.HTTP_200_OK,
    tags=["Navigation"]
)
def calculate_route(request: RouteRequest) -> RouteResponse:
    """Calculates an accessible indoor route and step-by-step guidance.

    - Filters stairs and narrow passages for wheelchair users
    - Computes relative turns ('L', 'R', 'F') and stops ('S') for wearable BLE haptics
    """
    if request.building_id != graph_engine.building_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Building '{request.building_id}' not found."
        )

    try:
        route = graph_engine.compute_route(
            start_query=request.start_node_id,
            dest_query=request.destination_label,
            profile=request.user_profile
        )
        return route
    except ValueError as err:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(err)
        )
    except RuntimeError as err:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY if hasattr(status, "HTTP_422_UNPROCESSABLE_CONTENT") else 422,
            detail=str(err)
        )
