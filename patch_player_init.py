with open('app/static/player.js', 'r') as f:
    content = f.read()

old_init = """    initHistory() {
        const history = JSON.parse(localStorage.getItem('aniverse_history') || '[]');
        const entry = history.find(e => e.episodeId === this.episodeId);"""

new_init = """    initHistory() {
        let history = [];
        try {
            const raw = localStorage.getItem('aniverse_history');
            history = raw ? JSON.parse(raw) : [];
            if (!Array.isArray(history)) history = [];
        } catch(e) { history = []; }
        const entry = history.find(e => e.episodeId === this.episodeId);"""

content = content.replace(old_init, new_init)
with open('app/static/player.js', 'w') as f:
    f.write(content)
