import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

# Fix the missing _cachedCategory issue in loadSource
old_init = """            if(this.state.servers[this.state.currentCategory] && this.state.servers[this.state.currentCategory].length > 0) {
                 this.state.currentServer = this.state.servers[this.state.currentCategory][0].serverName;
                 this.loadSource(this.state.currentServer, this.state.currentCategory, this.savedProgress);"""

new_init = """            if(this.state.servers[this.state.currentCategory] && this.state.servers[this.state.currentCategory].length > 0) {
                 this.state.currentServer = this.state.servers[this.state.currentCategory][0].serverName;
                 this._cachedCategory = null; // Force initial fetch
                 this.loadSource(this.state.currentServer, this.state.currentCategory, this.savedProgress);"""

if old_init in content:
    content = content.replace(old_init, new_init)
    with open('app/static/player.js', 'w') as f:
        f.write(content)
    print("Fixed player.js _cachedCategory init issue!")
else:
    print("Could not find init issue logic in player.js.")

# Fix missing sourceObj crash
old_source = """            // Find the requested server from cache
            sourceObj = this._cachedSources.find(s => (s.serverName || '') === serverName) || this._cachedSources[0];
            referer = this._cachedHeaders.Referer || '';
            
            const source = sourceObj.url;"""

new_source = """            // Find the requested server from cache
            if (!this._cachedSources || this._cachedSources.length === 0) {
                throw new Error("Cached sources empty.");
            }
            
            sourceObj = this._cachedSources.find(s => (s.serverName || '') === serverName) || this._cachedSources[0];
            if (!sourceObj || !sourceObj.url) {
                throw new Error("Invalid source object.");
            }
            
            referer = this._cachedHeaders.Referer || '';
            const source = sourceObj.url;"""

if old_source in content:
    content = content.replace(old_source, new_source)
    with open('app/static/player.js', 'w') as f:
        f.write(content)
    print("Fixed player.js sourceObj null issue!")
else:
    print("Could not find sourceObj issue logic in player.js.")
