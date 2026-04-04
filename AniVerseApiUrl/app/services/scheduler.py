from apscheduler.schedulers.asyncio import AsyncIOScheduler
from app.core.cache import cache
import logging

logger = logging.getLogger(__name__)
scheduler = AsyncIOScheduler()

def start_scheduler():
    """Start the background workers."""
    
    # 1. Background worker: Cleanup Cache
    @scheduler.scheduled_job('interval', minutes=10)
    def cleanup_cache_job():
        logger.info("Running background job: Cache cleanup")
        cache.cleanup()
        
    # 2. Background worker: Health check (Mock)
    @scheduler.scheduled_job('interval', minutes=30)
    async def validate_streams_job():
        logger.info("Running background job: Validating stream health...")
        # In a real app, this would pick random cached streams and send a HEAD request
        # to ensure they are still returning 200 OK, otherwise evict them.
        pass

    scheduler.start()
    logger.info("Background workers started successfully.")
