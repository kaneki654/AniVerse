with open('app/static/player.js', 'r') as f:
    content = f.read()

old_save = """    saveHistory() {
        if (!this.episodeId || this.video.currentTime < 30) return;
        
        const now = Date.now();
        // Throttle: save every 30s unless forced
        if (now - this.lastSaveTime < 30000 && !this.video.ended && !this.forceSave) return;
        
        this.lastSaveTime = now;
        this.forceSave = false;

        let history = JSON.parse(localStorage.getItem('aniverse_history') || '[]');
        
        // Remove existing entry for this episode
        history = history.filter(e => e.episodeId !== this.episodeId);
        
        const duration = this.video.duration || 0;
        const progress = this.video.currentTime;
        const completed = (duration > 0 && (progress / duration) > 0.95);
        
        const entry = {
            animeId: this.animeId,
            animeTitle: this.animeTitle,
            animePoster: this.animePoster,
            episodeId: this.episodeId,
            episodeNum: this.episodeNum,
            episodeTitle: this.episodeTitle,
            timestamp: now,
            progress: progress,
            duration: duration,
            completed: completed
        };
        
        // Add to front
        history.unshift(entry);
        
        // Trim to 200
        if(history.length > 200) history = history.slice(0, 200);
        
        localStorage.setItem('aniverse_history', JSON.stringify(history));
    }"""

new_save = """    saveHistory() {
        if (!this.episodeId || !this.animeId || this.video.currentTime < 30) return;
        
        const now = Date.now();
        // Throttle: save every 30s unless forced
        if (now - this.lastSaveTime < 30000 && !this.video.ended && !this.forceSave) return;
        
        this.lastSaveTime = now;
        this.forceSave = false;

        let history = [];
        try {
            const raw = localStorage.getItem('aniverse_history');
            history = raw ? JSON.parse(raw) : [];
            if (!Array.isArray(history)) history = [];
        } catch(e) {
            history = [];
        }
        
        // Remove existing entry for this episode
        history = history.filter(e => e.episodeId !== this.episodeId);
        
        // Fallback for missing duration
        const duration = this.video.duration && !isNaN(this.video.duration) ? this.video.duration : 1;
        const progress = this.video.currentTime;
        const completed = (progress / duration) > 0.95;
        
        const entry = {
            animeId: this.animeId,
            animeTitle: this.animeTitle || "Unknown Anime",
            animePoster: this.animePoster || "",
            episodeId: this.episodeId,
            episodeNum: this.episodeNum || 0,
            episodeTitle: this.episodeTitle || `Episode ${this.episodeNum}`,
            timestamp: now,
            progress: progress,
            duration: duration,
            completed: completed
        };
        
        // Add to front
        history.unshift(entry);
        
        // Trim to 200
        if(history.length > 200) history = history.slice(0, 200);
        
        try {
            localStorage.setItem('aniverse_history', JSON.stringify(history));
        } catch(e) {
            console.error('Failed to save history', e);
        }
    }"""

content = content.replace(old_save, new_save)
with open('app/static/player.js', 'w') as f:
    f.write(content)
