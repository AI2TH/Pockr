#!/usr/bin/env python3
"""
FastAPI server for Docker container management inside Alpine Linux VM.
Runs on guest 127.0.0.1:7080 and is accessible from Android host via hostfwd.
"""

from fastapi import FastAPI, HTTPException, Header
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Optional
import subprocess
import uvicorn
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Docker VM API", version="1.0.0")

# TODO: Load this from a secure location seeded by Android app
API_TOKEN = "insecure-token-replace-me"


class ContainerStartRequest(BaseModel):
    image: str
    name: str
    cmd: List[str]
    env: Optional[List[dict]] = []
    ports: Optional[List[dict]] = []


class ContainerStopRequest(BaseModel):
    name: str


class ContainerInfo(BaseModel):
    name: str
    image: str
    status: str
    ports: List[str] = []


def verify_token(authorization: Optional[str] = Header(None)):
    """Simple Bearer token authentication."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")

    token = authorization.replace("Bearer ", "")
    if token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    try:
        # Check if Docker is running
        result = subprocess.run(
            ["docker", "info"],
            capture_output=True,
            text=True,
            timeout=5
        )
        runtime_available = result.returncode == 0

        # Get Docker version
        version_result = subprocess.run(
            ["docker", "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        version = version_result.stdout.strip() if version_result.returncode == 0 else "unknown"

        return {
            "status": "ok" if runtime_available else "degraded",
            "runtime": "docker",
            "version": version
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return JSONResponse(
            status_code=503,
            content={"status": "error", "message": str(e)}
        )


@app.get("/containers", response_model=List[ContainerInfo])
async def list_containers():
    """List all running containers."""
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}"],
            capture_output=True,
            text=True,
            check=True
        )

        containers = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue

            parts = line.split('|')
            if len(parts) >= 3:
                containers.append(ContainerInfo(
                    name=parts[0],
                    image=parts[1],
                    status=parts[2],
                    ports=[parts[3]] if len(parts) > 3 and parts[3] else []
                ))

        return containers
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to list containers: {e}")
        raise HTTPException(status_code=500, detail=f"Docker command failed: {e.stderr}")
    except Exception as e:
        logger.error(f"Error listing containers: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/containers/start")
async def start_container(request: ContainerStartRequest):
    """Start a new container."""
    try:
        # Build docker run command
        cmd = ["docker", "run", "-d", "--name", request.name]

        # Add environment variables
        for env in request.env:
            if 'key' in env and 'value' in env:
                cmd.extend(["-e", f"{env['key']}={env['value']}"])

        # Add port mappings
        for port in request.ports:
            if 'host' in port and 'container' in port:
                cmd.extend(["-p", f"{port['host']}:{port['container']}"])

        # Add image and command
        cmd.append(request.image)
        cmd.extend(request.cmd)

        logger.info(f"Starting container: {' '.join(cmd)}")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            timeout=30
        )

        container_id = result.stdout.strip()

        return {
            "status": "started",
            "name": request.name,
            "id": container_id
        }
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to start container: {e.stderr}")
        raise HTTPException(status_code=500, detail=f"Docker command failed: {e.stderr}")
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Container start timed out")
    except Exception as e:
        logger.error(f"Error starting container: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/containers/stop")
async def stop_container(request: ContainerStopRequest):
    """Stop a running container."""
    try:
        result = subprocess.run(
            ["docker", "stop", request.name],
            capture_output=True,
            text=True,
            check=True,
            timeout=10
        )

        return {
            "status": "stopped",
            "name": request.name
        }
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to stop container: {e.stderr}")
        raise HTTPException(status_code=500, detail=f"Docker command failed: {e.stderr}")
    except Exception as e:
        logger.error(f"Error stopping container: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/logs")
async def get_logs(name: str, tail: int = 100):
    """Get container logs."""
    try:
        result = subprocess.run(
            ["docker", "logs", "--tail", str(tail), name],
            capture_output=True,
            text=True,
            check=True
        )

        return result.stdout
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to get logs: {e.stderr}")
        raise HTTPException(status_code=500, detail=f"Docker command failed: {e.stderr}")
    except Exception as e:
        logger.error(f"Error getting logs: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/images/pull")
async def pull_image(image: str):
    """Pull a Docker image."""
    try:
        result = subprocess.run(
            ["docker", "pull", image],
            capture_output=True,
            text=True,
            check=True,
            timeout=300  # 5 minutes for large images
        )

        return {
            "status": "pulled",
            "image": image,
            "output": result.stdout
        }
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Image pull timed out")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to pull image: {e.stderr}")
        raise HTTPException(status_code=500, detail=f"Docker command failed: {e.stderr}")
    except Exception as e:
        logger.error(f"Error pulling image: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    logger.info("Starting Docker VM API server on 127.0.0.1:7080")
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=7080,
        log_level="info"
    )
