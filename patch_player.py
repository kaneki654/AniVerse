import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

old_init = """    // Set up save triggers
    // Throttle save to every 30s
    this.lastSaveTime = 0;
    this.video.addEventListener('timeupdate', () => {
        const now = Date.now();
        if (now - this.lastSaveTime > 30000) {
            this.saveHistory();
            this.lastSaveTime = now;
        }
    });

    this.video.addEventListener('ended', () => {
        this.saveHistory(true); // Force completed
    });
    
    // Save on leave
    window.addEventListener('beforeunload', () => this.saveHistory());
    window.addEventListener('pagehide', () => this.saveHistory());
};"""

new_init = """    // Set up save triggers
    // We only want to save if currentTime >= 30, but we also want to save every 30 real seconds.
    this.lastSaveTime = Date.now();
    this.video.addEventListener('timeupdate', () => {
        const now = Date.now();
        if (now - this.lastSaveTime > 30000) { // Check every 30 real-world seconds
            if (this.video.currentTime >= 30) {
                this.saveHistory();
            }
            this.lastSaveTime = now;
        }
    });

    this.video.addEventListener('ended', () => {
        if (this.video.currentTime >= 30) {
            this.saveHistory(true); // Force completed
        }
    });
    
    // Save on leave
    window.addEventListener('beforeunload', () => {
        if (this.video.currentTime >= 30) this.saveHistory();
    });
    window.addEventListener('pagehide', () => {
        if (this.video.currentTime >= 30) this.saveHistory();
    });
};"""

old_save = """CustomPlayer.prototype.saveHistory = function(forceCompleted = false) {
    if (!this.options.animeId || !this.video || this.video.currentTime < 30) return;

    try {
        const history = JSON.parse(localStorage.getItem('aniverse_history') || '[]');
        
        // Remove existing entry for this episode
        const existingIndex = history.findIndex(item => item.episodeId === this.episodeId);
        if (existingIndex !== -1) {
            history.splice(existingIndex, 1);
        }

        const duration = this.video.duration || 0;
        const progress = this.video.currentTime;
        const isCompleted = forceCompleted || (duration > 0 && (progress / duration) > 0.95);

        const entry = {
            animeId: this.options.animeId,
            animeTitle: this.options.animeTitle || 'Unknown Anime',
            animePoster: this.options.animePoster || '',
            episodeId: this.episodeId,
            episodeNum: this.options.episodeNum || 0,
            episodeTitle: this.options.episodeTitle || `Episode ${this.options.episodeNum}`,
            timestamp: Date.now(),
            progress: progress,
            duration: duration,
            completed: isCompleted
        };

        // Add to front
        history.unshift(entry);

        // Limit to 200
        if (history.length > 200) {
            history.length = 200;
        }

        localStorage.setItem('aniverse_history', JSON.stringify(history));
    } catch (e) {
        console.error('Error saving history:', e);
    }
};"""

new_save = """CustomPlayer.prototype.saveHistory = function(forceCompleted = false) {
    if (!this.options.animeId || !this.video || this.video.currentTime < 30) return;

    try {
        const raw = localStorage.getItem('aniverse_history');
        const history = raw ? JSON.parse(raw) : [];
        
        // Remove existing entry for this episode
        const existingIndex = history.findIndex(item => item.episodeId === this.episodeId);
        if (existingIndex !== -1) {
            history.splice(existingIndex, 1);
        }

        const duration = this.video.duration && !isNaN(this.video.duration) ? this.video.duration : 1;
        const progress = this.video.currentTime;
        const isCompleted = forceCompleted || (progress / duration) > 0.95;

        const entry = {
            animeId: this.options.animeId,
            animeTitle: this.options.animeTitle || 'Unknown Anime',
            animePoster: this.options.animePoster || '',
            episodeId: this.episodeId,
            episodeNum: this.options.episodeNum || 0,
            episodeTitle: this.options.episodeTitle || `Episode ${this.options.episodeNum}`,
            timestamp: Date.now(),
            progress: progress,
            duration: duration,
            completed: isCompleted
        };

        // Add to front
        history.unshift(entry);

        // Limit to 200
        if (history.length > 200) {
            history.length = 200;
        }

        localStorage.setItem('aniverse_history', JSON.stringify(history));
    } catch (e) {
        console.error('Error saving history:', e);
    }
};"""

content = content.replace(old_init, new_init)
content = content.replace(old_save, new_save)

with open('app/static/player.js', 'w') as f:
    f.write(content)
