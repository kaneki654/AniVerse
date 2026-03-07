with open('app/static/player.js', 'r') as f:
    content = f.read()

# I will replace the entirety of initHistory and saveHistory
import re

history_pattern = re.compile(r'initHistory\(\)\s*\{.*?showResumeToast\(\)\s*\{', re.DOTALL)

new_history_methods = """initHistory() {
        // Find existing history for this episode
        let history = [];
        try {
            const raw = localStorage.getItem('aniverse_history');
            history = raw ? JSON.parse(raw) : [];
            if (!Array.isArray(history)) history = [];
        } catch(e) { history = []; }
        
        const entry = history.find(e => e.episodeId === this.episodeId);
        
        // Auto Resume
        if (entry && entry.progress > 0) {
            this.savedProgress = entry.progress;
            
            const handleCanPlay = () => {
                // Seek to saved position if we have progress
                if(this.savedProgress > 0 && Math.abs(this.video.currentTime - this.savedProgress) > 5) {
                    this.video.currentTime = this.savedProgress;
                    this.showResumeToast();
                }
                this.video.removeEventListener('canplay', handleCanPlay);
                this.video.removeEventListener('playing', handleCanPlay);
            };
            
            this.video.addEventListener('canplay', handleCanPlay);
            this.video.addEventListener('playing', handleCanPlay);
        }

        // --- Save Triggers via Events ---
        
        // Event 1: Play -> Start 30s interval
        this.video.addEventListener('play', () => {
            if (this.saveInterval) clearInterval(this.saveInterval);
            this.saveInterval = setInterval(() => {
                this.saveHistory();
            }, 30000);
        });
        
        // Event 2: Pause -> Clear interval & save immediately
        this.video.addEventListener('pause', () => {
            if (this.saveInterval) clearInterval(this.saveInterval);
            this.saveHistory();
        });
        
        // Event 3: Ended -> Clear interval & save as completed
        this.video.addEventListener('ended', () => {
            if (this.saveInterval) clearInterval(this.saveInterval);
            this.saveHistory(true);
        });
        
        // Event 4: Window unload/hide -> Final save
        window.addEventListener('beforeunload', () => {
             this.saveHistory();
        });
        window.addEventListener('pagehide', () => {
             this.saveHistory();
        });
    }

    saveHistory(forceCompleted = false) {
        // Must use Top Level variables to guarantee data is present
        const animeId = window.WATCH_ANIME_ID || this.options.animeId;
        const epId = window.WATCH_EPISODE_ID || this.episodeId;
        
        // Threshold check: 30 seconds minimum
        if (!animeId || !epId || !this.video) return;
        if (this.video.currentTime < 30) return;
        
        let history = [];
        try {
            const raw = localStorage.getItem('aniverse_history');
            history = raw ? JSON.parse(raw) : [];
            if (!Array.isArray(history)) history = [];
        } catch(e) {
            history = [];
        }
        
        // Remove existing entry for this episode
        history = history.filter(e => e.episodeId !== epId);
        
        const duration = this.video.duration && !isNaN(this.video.duration) ? this.video.duration : 1;
        const progress = this.video.currentTime;
        const completed = forceCompleted || (progress / duration) > 0.95;
        
        const entry = {
            animeId: animeId,
            animeTitle: window.WATCH_ANIME_TITLE || this.options.animeTitle || 'Unknown Anime',
            animePoster: window.WATCH_ANIME_POSTER || this.options.animePoster || '',
            episodeId: epId,
            episodeNum: window.WATCH_EPISODE_NUM || this.options.episodeNum || 0,
            episodeTitle: window.WATCH_EPISODE_TITLE || this.options.episodeTitle || `Episode ${window.WATCH_EPISODE_NUM || this.options.episodeNum}`,
            timestamp: Date.now(),
            progress: progress,
            duration: duration,
            completed: completed
        };
        
        // Add to front of history
        history.unshift(entry);
        
        // Trim to max 200 entries
        if(history.length > 200) history = history.slice(0, 200);
        
        try {
            localStorage.setItem('aniverse_history', JSON.stringify(history));
        } catch(e) {
            console.error('Failed to save history', e);
        }
    }

    showResumeToast() {"""

content = history_pattern.sub(new_history_methods, content)

with open('app/static/player.js', 'w') as f:
    f.write(content)
