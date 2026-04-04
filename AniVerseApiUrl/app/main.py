from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from contextlib import asynccontextmanager

from app.api.router import router as anime_router
from app.api.proxy import router as global_proxy_router
from app.services.scheduler import start_scheduler

@asynccontextmanager
async def lifespan(app: FastAPI):
    start_scheduler()
    yield

app = FastAPI(
    title="AniVerse API",
    description="Aggregated multi-provider Anime Streaming API",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(anime_router)
app.include_router(global_proxy_router)

# Mount the static directory
app.mount("/static", StaticFiles(directory="app/static"), name="static")

@app.get("/")
async def serve_player():
    """Serve the Web Player interface on the root path"""
    return FileResponse("app/static/index.html")

@app.get("/health")
async def health_check():
    return {"status": "ok", "message": "AniVerse API is running smoothly!"}
