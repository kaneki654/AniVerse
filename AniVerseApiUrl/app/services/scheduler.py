import os
from datetime import datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.services import skip_times
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

    # 3. Skip intro/outro: in quiet hours, get the next episodes of shows
    # people are watching ready, so nobody waits for a detection. The hours
    # are local time, "start-end" (default 2-6), and can be turned off with "".
    @scheduler.scheduled_job('interval', minutes=20)
    async def predetect_skip_times_job():
        window = os.getenv("SKIP_QUIET_HOURS", "2-6").strip()
        if not window:
            return
        try:
            start, end = (int(x) for x in window.split("-"))
        except ValueError:
            return
        hour = datetime.now().hour
        if not (start <= hour < end if start <= end else hour >= start or hour < end):
            return
        ran = await skip_times.predetect(max_jobs=2)
        if ran:
            logger.info("Pre-detected skip times for %d episode(s)", ran)

    @scheduler.scheduled_job('interval', minutes=5)
    def save_health_job():
        # The status page's history survives a restart (app/core/health.py).
        from app.core import health
        try:
            health.save()
        except OSError as e:
            print(f"Could not save health history: {e}")

    scheduler.start()
    logger.info("Background workers started successfully.")
