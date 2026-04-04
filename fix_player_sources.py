import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

# Replace loadSource
old_loadsource = """    async loadSource(serverName, category, startTime = 0) {
        this.showLoading(true);
        this.hideError();
        try {
            const url = `/api/source?episode_id=${this.episodeId}&server=${serverName}&category=${category}`;
            const resp = await fetch(url);
            if (!resp.ok) throw new Error(`HTTP error! status: ${resp.status}`);
            const data = await resp.json();
            
            if(!data.data || !data.data.sources) throw new Error("No sources found");
            
            const sourceObj = data.data.sources[0];
            const source = sourceObj.url;
            const isM3U8 = sourceObj.isM3U8 !== false; // true by default
            const referer = data.data.headers ? data.data.headers.Referer : '';
            
            this.state.intro = data.data.intro || null;
            this.state.outro = data.data.outro || null;

            // Don't proxy if it's already a proxy URL
            let proxyUrl = source;
            if (isM3U8 && !source.startsWith('/proxy/')) {
                proxyUrl = `/proxy/m3u8?url=${encodeURIComponent(source)}`;
                if(referer) proxyUrl += `&referer=${encodeURIComponent(referer)}`;
            }

            this.setupSubtitles(data.data.tracks || data.data.subtitles, referer);"""

new_loadsource = """    async loadSource(serverName, category, startTime = 0) {
        this.showLoading(true);
        this.hideError();
        try {
            // Only fetch if we haven't cached sources for this category, or if we are explicitly fetching "Auto"
            let sourceObj = null;
            let referer = '';
            
            if (!this._cachedSources || this._cachedCategory !== category) {
                const url = `/api/source?episode_id=${this.episodeId}&server=Auto&category=${category}`;
                const resp = await fetch(url);
                if (!resp.ok) throw new Error(`HTTP error! status: ${resp.status}`);
                const data = await resp.json();
                
                if(!data.data || !data.data.sources || data.data.sources.length === 0) throw new Error("No sources found");
                
                // Cache them so we can switch quickly
                this._cachedSources = data.data.sources;
                this._cachedCategory = category;
                this._cachedHeaders = data.data.headers || {};
                this._cachedSubtitles = data.data.tracks || data.data.subtitles || [];
                this.state.intro = data.data.intro || null;
                this.state.outro = data.data.outro || null;
                
                // Update the UI Servers list dynamically with names!
                this.state.servers[category] = this._cachedSources.map((s, idx) => ({
                    serverName: s.serverName || `Server ${idx + 1}`,
                    category: category
                }));
                // Select the first one natively
                if (serverName === 'Auto') {
                    this.state.currentServer = this.state.servers[category][0].serverName;
                    serverName = this.state.currentServer;
                    const qualEl = document.getElementById('current-source');
                    if(qualEl) qualEl.innerText = serverName;
                }
                this.updateSettingsUI();
            }
            
            // Find the requested server from cache
            sourceObj = this._cachedSources.find(s => (s.serverName || '') === serverName) || this._cachedSources[0];
            referer = this._cachedHeaders.Referer || '';
            
            const source = sourceObj.url;
            const isM3U8 = sourceObj.isM3U8 !== false; // true by default

            // Don't proxy if it's already a proxy URL
            let proxyUrl = source;
            if (isM3U8 && !source.startsWith('/proxy/')) {
                proxyUrl = `/proxy/m3u8?url=${encodeURIComponent(source)}`;
                if(referer) proxyUrl += `&referer=${encodeURIComponent(referer)}`;
            }

            this.setupSubtitles(this._cachedSubtitles, referer);"""

content = content.replace(old_loadsource, new_loadsource)

with open('app/static/player.js', 'w') as f:
    f.write(content)
print("Replaced loadSource in player.js!")

