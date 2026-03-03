class CustomPlayer {
    constructor(elementId, episodeId, options = {}) {
        this.wrapper = document.getElementById(elementId);
        this.container = this.wrapper.querySelector('.player-container');
        this.video = this.container.querySelector('video');
        this.episodeId = episodeId;
        this.hls = null;
        this.options = options;
        
        // Initial state
        this.state = {
            currentServer: null,
            currentCategory: 'sub', // sub, dub, raw
            isPlaying: false,
            volume: 1,
            muted: false,
            quality: 'auto',
            speed: 1,
            subtitle: 'off',
            intro: null,
            outro: null,
            servers: { sub: [], dub: [], raw: [] }
        };

        this.initControls();
        this.initSettings();
    }

    async init(initialCategory = 'sub') {
        try {
            if(this.options.servers) {
                this.state.servers = this.options.servers;
            }
            
            // Auto-select category
            if(this.state.servers[initialCategory] && this.state.servers[initialCategory].length > 0) {
                this.state.currentCategory = initialCategory;
            } else {
                for(const cat of ['sub', 'dub', 'raw']) {
                    if(this.state.servers[cat] && this.state.servers[cat].length > 0) {
                        this.state.currentCategory = cat;
                        break;
                    }
                }
            }
            
            // Select first server
            if(this.state.servers[this.state.currentCategory] && this.state.servers[this.state.currentCategory].length > 0) {
                 this.state.currentServer = this.state.servers[this.state.currentCategory][0].serverName;
                 this.loadSource(this.state.currentServer, this.state.currentCategory);
            } else {
                console.error("No servers found for any category");
            }

            this.updateSettingsUI();
            this.initSpeedOptions();
        } catch(e) {
            console.error("Init error", e);
        }
    }

    async loadSource(serverName, category, startTime = 0) {
        this.showLoading(true);
        console.log(`Loading source: ${serverName} (${category})`);
        try {
            const url = `/api/source?episode_id=${this.episodeId}&server=${serverName}&category=${category}`;
            const resp = await fetch(url);
            const data = await resp.json();
            
            if(!data.data || !data.data.sources) throw new Error("No sources found in API response");
            
            const source = data.data.sources[0].url;
            const referer = data.data.headers ? data.data.headers.Referer : '';
            
            // Store intro/outro
            this.state.intro = data.data.intro || null;
            this.state.outro = data.data.outro || null;

            // Prepare Proxy URL
            let proxyUrl = `/proxy/m3u8?url=${encodeURIComponent(source)}`;
            if(referer) proxyUrl += `&referer=${encodeURIComponent(referer)}`;

            // Handle Subtitles
            this.setupSubtitles(data.data.tracks || data.data.subtitles, referer);

            // Load HLS
            if(Hls.isSupported()) {
                if(this.hls) this.hls.destroy();
                this.hls = new Hls();
                this.hls.loadSource(proxyUrl);
                this.hls.attachMedia(this.video);
                
                this.hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    this.video.currentTime = startTime;
                    this.video.play().catch(e => console.log("Autoplay blocked", e));
                    this.updateQualityOptions();
                    this.showLoading(false);
                });
                
                this.hls.on(Hls.Events.LEVEL_SWITCHED, (e, data) => {
                     // Could update UI here to show active auto quality
                });
                
                this.hls.on(Hls.Events.ERROR, (event, data) => {
                    console.error("HLS Error:", data);
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR:
                                this.hls.startLoad();
                                break;
                            case Hls.ErrorTypes.MEDIA_ERROR:
                                this.hls.recoverMediaError();
                                break;
                            default:
                                this.hls.destroy();
                                break;
                        }
                    }
                });
                
            } else if (this.video.canPlayType('application/vnd.apple.mpegurl')) {
                this.video.src = proxyUrl;
                this.video.addEventListener('loadedmetadata', () => {
                    this.video.currentTime = startTime;
                    this.video.play();
                    this.showLoading(false);
                });
            }
        } catch(e) {
            console.error("Load source error", e);
            this.showLoading(false);
        }
    }

    setupSubtitles(tracks, referer) {
        // Clear old tracks from video
        const old = this.video.querySelectorAll('track');
        old.forEach(t => t.remove());

        const subsMenu = document.getElementById('settings-subs-options');
        // Reset menu to just "Off"
        subsMenu.innerHTML = `<div class="settings-item selected" data-value="off">Off <span class="check-icon">✓</span></div>`;
        subsMenu.children[0].onclick = () => this.setSubtitle('off');
        
        // Reset current selection text
        document.getElementById('current-subs').innerText = 'Off';

        if(!tracks || tracks.length === 0) {
            console.log("No subtitles found");
            return;
        }

        tracks.forEach(track => {
            if(track.kind === 'captions' || track.kind === 'subtitles') {
                 // Create track element
                 const trackElem = document.createElement('track');
                 trackElem.kind = 'subtitles';
                 trackElem.label = track.label;
                 trackElem.srclang = track.label ? track.label.toLowerCase().slice(0, 2) : 'en';
                 
                 let trackUrl = `/proxy/subtitle?url=${encodeURIComponent(track.file)}`;
                 if(referer) trackUrl += `&referer=${encodeURIComponent(referer)}`;
                 trackElem.src = trackUrl;
                 
                 this.video.appendChild(trackElem);

                 // Add to settings menu
                 const item = document.createElement('div');
                 item.className = 'settings-item';
                 item.dataset.value = track.label;
                 item.innerHTML = `${track.label} <span class="check-icon">✓</span>`;
                 item.onclick = () => this.setSubtitle(track.label);
                 subsMenu.appendChild(item);
                 
                 // Auto-select English if default needed (optional logic)
                 // if(track.label === 'English') ...
            }
        });
    }

    setSubtitle(label) {
        // Toggle tracks
        for(let i=0; i<this.video.textTracks.length; i++) {
            const track = this.video.textTracks[i];
            if(label === 'off') {
                track.mode = 'hidden';
            } else if(track.label === label) {
                track.mode = 'showing';
            } else {
                track.mode = 'hidden';
            }
        }
        
        // Update UI Selection
        const menu = document.getElementById('settings-subs-options');
        Array.from(menu.children).forEach(child => {
             if(child.dataset.value === label) child.classList.add('selected');
             else child.classList.remove('selected');
        });
        document.getElementById('current-subs').innerText = label === 'off' ? 'Off' : label;
        
        // Return to main menu
        this.showSubmenu(null); 
    }

    updateQualityOptions() {
        if(!this.hls || !this.hls.levels || this.hls.levels.length === 0) return;
        
        const qualityMenu = document.getElementById('settings-quality-options');
        // Reset to Auto
        qualityMenu.innerHTML = `<div class="settings-item selected" data-value="auto">Auto <span class="check-icon">✓</span></div>`;
        qualityMenu.children[0].onclick = () => this.setQuality(-1);
        
        // Add levels
        // HLS levels usually come sorted low to high or high to low. 
        // We can reverse if needed to show highest first.
        this.hls.levels.forEach((level, index) => {
            const item = document.createElement('div');
            item.className = 'settings-item';
            item.dataset.value = index;
            item.innerHTML = `${level.height}p <span class="check-icon">✓</span>`;
            item.onclick = () => this.setQuality(index);
            // Prepend to show higher qualities at top (if array is low->high)
            // But usually appending is safer for index matching
            qualityMenu.appendChild(item);
        });
    }

    setQuality(levelIndex) {
        if(this.hls) {
            this.hls.currentLevel = levelIndex;
            
            const menu = document.getElementById('settings-quality-options');
            Array.from(menu.children).forEach(child => {
                const val = child.dataset.value;
                if(val == levelIndex || (levelIndex === -1 && val === 'auto')) {
                    child.classList.add('selected');
                    document.getElementById('current-quality').innerText = child.innerText.replace('✓', '').trim();
                } else {
                    child.classList.remove('selected');
                }
            });
        }
        this.showSubmenu(null);
    }
    
    initSpeedOptions() {
        const speedMenu = document.getElementById('settings-speed-options');
        speedMenu.innerHTML = '';
        const speeds = [0.5, 0.75, 1, 1.25, 1.5, 2];
        
        speeds.forEach(speed => {
            const item = document.createElement('div');
            item.className = 'settings-item';
            if(speed === 1) item.classList.add('selected');
            item.innerHTML = `${speed}x <span class="check-icon">✓</span>`;
            item.onclick = () => this.setSpeed(speed);
            speedMenu.appendChild(item);
        });
    }

    setSpeed(speed) {
        this.video.playbackRate = speed;
        
        const menu = document.getElementById('settings-speed-options');
        Array.from(menu.children).forEach(child => {
            if(child.innerText.startsWith(speed + 'x')) child.classList.add('selected');
            else child.classList.remove('selected');
        });
        
        document.getElementById('current-speed').innerText = speed === 1 ? 'Normal' : speed + 'x';
        this.showSubmenu(null);
    }
    
    setAudio(category) {
        if(this.state.currentCategory === category) return;
        
        const time = this.video.currentTime;
        this.state.currentCategory = category;
        
        if(this.state.servers[category] && this.state.servers[category].length > 0) {
            this.state.currentServer = this.state.servers[category][0].serverName;
            this.loadSource(this.state.currentServer, category, time);
            
            // Update UI
            const menu = document.getElementById('settings-audio-options');
            Array.from(menu.children).forEach(child => {
                if(child.innerText.includes(category.toUpperCase())) child.classList.add('selected');
                else child.classList.remove('selected');
            });
            document.getElementById('current-audio').innerText = category.charAt(0).toUpperCase() + category.slice(1);
        }
        this.showSubmenu(null);
    }

    initControls() {
        // Play/Pause
        const playBtn = document.getElementById('play-btn');
        const playIcon = document.getElementById('play-icon');
        
        const togglePlay = () => {
            if(this.video.paused) {
                this.video.play();
                playIcon.innerText = '❚❚';
            } else {
                this.video.pause();
                playIcon.innerText = '▶';
            }
        };
        
        playBtn.onclick = togglePlay;
        this.video.addEventListener('click', togglePlay);
        
        // Progress Bar
        const progressContainer = document.querySelector('.progress-container');
        const progressBar = document.querySelector('.progress-bar');
        const timeDisplay = document.querySelector('.time-display');
        
        this.video.addEventListener('timeupdate', () => {
             if(!this.video.duration) return;
             const percent = (this.video.currentTime / this.video.duration) * 100;
             progressBar.style.width = `${percent}%`;
             timeDisplay.innerText = `${this.formatTime(this.video.currentTime)} / ${this.formatTime(this.video.duration)}`;
             
             // Check Skip
             this.checkSkip(this.state.intro, 'skip-intro');
             this.checkSkip(this.state.outro, 'skip-outro');
        });
        
        progressContainer.addEventListener('click', (e) => {
            const rect = progressContainer.getBoundingClientRect();
            const percent = (e.clientX - rect.left) / rect.width;
            this.video.currentTime = percent * this.video.duration;
        });

        // Volume
        const volSlider = document.getElementById('volume-slider');
        const muteBtn = document.getElementById('mute-btn');
        
        volSlider.addEventListener('input', (e) => {
            this.video.volume = e.target.value;
            this.video.muted = false;
            muteBtn.innerText = '🔊';
        });
        
        muteBtn.onclick = () => {
             this.video.muted = !this.video.muted;
             muteBtn.innerText = this.video.muted ? '🔇' : '🔊';
        };
        
        // Fullscreen
        document.getElementById('fullscreen-btn').onclick = () => {
            if(!document.fullscreenElement) {
                this.container.requestFullscreen();
                this.container.classList.add('fullscreen');
            } else {
                document.exitFullscreen();
                this.container.classList.remove('fullscreen');
            }
        };
        
        // Theater

        // Settings Toggle
        document.getElementById('settings-btn').onclick = (e) => {
             e.stopPropagation();
             this.toggleSettingsMenu();
        };

        // Skip Buttons
        document.getElementById('skip-intro').onclick = () => {
             if(this.state.intro) this.video.currentTime = this.state.intro.end;
        };
        document.getElementById('skip-outro').onclick = () => {
             if(this.state.outro) this.video.currentTime = this.state.outro.end;
        };
    }
    
    checkSkip(range, btnId) {
        const btn = document.getElementById(btnId);
        if(range && this.video.currentTime >= range.start && this.video.currentTime <= range.end) {
            btn.classList.add('visible');
        } else {
            btn.classList.remove('visible');
        }
    }

    formatTime(seconds) {
        if(!seconds) return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return `${m}:${s < 10 ? '0' : ''}${s}`;
    }
    
    initSettings() {
        // Main menu clicks
        document.querySelectorAll('.settings-main .settings-item').forEach(item => {
            item.onclick = (e) => {
                e.stopPropagation();
                this.showSubmenu(item.dataset.target);
            };
        });
        
        // Back buttons
        document.querySelectorAll('.settings-header').forEach(header => {
            header.onclick = (e) => {
                e.stopPropagation();
                this.showSubmenu(null); // Back to main
            };
        });
        
        // Close on click outside
        document.addEventListener('click', (e) => {
             const menu = document.getElementById('settings-menu');
             const btn = document.getElementById('settings-btn');
             if(!menu.contains(e.target) && e.target !== btn) {
                 menu.style.display = 'none';
             }
        });
    }

    toggleSettingsMenu() {
        const menu = document.getElementById('settings-menu');
        if(menu.style.display === 'flex') {
            menu.style.display = 'none';
        } else {
            menu.style.display = 'flex';
            this.showSubmenu(null);
        }
    }
    
    showSubmenu(target) {
        const main = document.querySelector('.settings-main');
        const submenus = document.querySelectorAll('.settings-submenu');
        
        if(target) {
            main.style.display = 'none';
            submenus.forEach(el => el.style.display = 'none');
            document.getElementById(`submenu-${target}`).style.display = 'flex';
        } else {
            main.style.display = 'flex';
            submenus.forEach(el => el.style.display = 'none');
        }
    }
    
    updateSettingsUI() {
        const audioMenu = document.getElementById('settings-audio-options');
        audioMenu.innerHTML = '';
        
        let hasAudio = false;
        ['sub', 'dub', 'raw'].forEach(cat => {
            if(this.state.servers[cat] && this.state.servers[cat].length > 0) {
                hasAudio = true;
                const item = document.createElement('div');
                item.className = 'settings-item';
                if(cat === this.state.currentCategory) item.classList.add('selected');
                item.innerHTML = `${cat.toUpperCase()} <span class="check-icon">✓</span>`;
                item.onclick = () => this.setAudio(cat);
                audioMenu.appendChild(item);
            }
        });
        
        if(!hasAudio) {
             audioMenu.innerHTML = '<div class="settings-item">No alternate audio available</div>';
        }
    }
    
    showLoading(show) {
        const spinner = document.querySelector('.loading-spinner');
        if(show) spinner.classList.add('active');
        else spinner.classList.remove('active');
    }
}
// Patch to ensure tracks are filtered correctly
CustomPlayer.prototype.setupSubtitles = function(tracks, referer) {
    // Clear old tracks from video
    const old = this.video.querySelectorAll('track');
    old.forEach(t => t.remove());

    const subsMenu = document.getElementById('settings-subs-options');
    // Reset menu to just "Off"
    subsMenu.innerHTML = `<div class="settings-item selected" data-value="off">Off <span class="check-icon">✓</span></div>`;
    subsMenu.children[0].onclick = () => this.setSubtitle('off');
    
    // Reset current selection text
    document.getElementById('current-subs').innerText = 'Off';

    // Check for tracks OR subtitles
    // The API might return 'tracks' or 'subtitles' depending on endpoint
    const subtitleList = tracks || []; 

    if(!subtitleList || subtitleList.length === 0) {
        console.log("No subtitles found");
        return;
    }

    subtitleList.forEach(track => {
        // Filter out thumbnails and non-subtitle kinds if specified
        // Sometimes api returns { label: 'Thumbnails', kind: 'thumbnails' }
        // Sometimes just { lang: 'Thumbnails' }
        const label = track.label || track.lang;
        const file = track.file || track.url;
        const kind = track.kind || 'subtitles';
        
        if(label === 'thumbnails' || kind === 'thumbnails') return;

        // Create track element
        const trackElem = document.createElement('track');
        trackElem.kind = 'subtitles';
        trackElem.label = label;
        trackElem.srclang = label ? label.toLowerCase().slice(0, 2) : 'en';
        
        let trackUrl = `/proxy/subtitle?url=${encodeURIComponent(file)}`;
        if(referer) trackUrl += `&referer=${encodeURIComponent(referer)}`;
        trackElem.src = trackUrl;
        
        this.video.appendChild(trackElem);

        // Add to settings menu
        const item = document.createElement('div');
        item.className = 'settings-item';
        item.dataset.value = label;
        item.innerHTML = `${label} <span class="check-icon">✓</span>`;
        item.onclick = () => this.setSubtitle(label);
        subsMenu.appendChild(item);
        
        // Auto-select English if default needed (optional logic)
        // if(label === 'English') ...
    });
};
CustomPlayer.prototype.initSettings = function() {
    // Main menu clicks
    const mainItems = document.querySelectorAll('.settings-main .settings-item');
    mainItems.forEach(item => {
        item.onclick = (e) => {
            e.stopPropagation();
            this.showSubmenu(item.dataset.target);
        };
    });
    
    // Back buttons
    const backBtns = document.querySelectorAll('.settings-header');
    backBtns.forEach(header => {
        header.onclick = (e) => {
            e.stopPropagation();
            this.showSubmenu(null); // Back to main
        };
    });
    
    // Close on click outside
    document.addEventListener('click', (e) => {
         const menu = document.getElementById('settings-menu');
         const btn = document.getElementById('settings-btn');
         if(menu && menu.style.display === 'flex' && !menu.contains(e.target) && e.target !== btn) {
             menu.style.display = 'none';
         }
    });
}

/* Ensure updateSettingsUI and other methods use the new HTML structure if needed */
/* The previous JS logic targets elements by ID or class which are preserved. */
/* Just need to ensure dynamic items follow new structure */

// Override updateQualityOptions to use span separation
CustomPlayer.prototype.updateQualityOptions = function() {
    if(!this.hls || !this.hls.levels || this.hls.levels.length === 0) return;
    
    const qualityMenu = document.getElementById('settings-quality-options');
    qualityMenu.innerHTML = `<div class="settings-item selected" data-value="auto"><span>Auto</span> <span class="check-icon">✓</span></div>`;
    qualityMenu.children[0].onclick = () => this.setQuality(-1);
    
    this.hls.levels.forEach((level, index) => {
        const item = document.createElement('div');
        item.className = 'settings-item';
        item.dataset.value = index;
        item.innerHTML = `<span>${level.height}p</span> <span class="check-icon">✓</span>`;
        item.onclick = () => this.setQuality(index);
        qualityMenu.appendChild(item);
    });
};

// Override updateSettingsUI for Audio
CustomPlayer.prototype.updateSettingsUI = function() {
    const audioMenu = document.getElementById('settings-audio-options');
    audioMenu.innerHTML = '';
    
    let hasAudio = false;
    ['sub', 'dub', 'raw'].forEach(cat => {
        if(this.state.servers[cat] && this.state.servers[cat].length > 0) {
            hasAudio = true;
            const item = document.createElement('div');
            item.className = 'settings-item';
            if(cat === this.state.currentCategory) item.classList.add('selected');
            item.innerHTML = `<span>${cat.toUpperCase()}</span> <span class="check-icon">✓</span>`;
            item.onclick = () => this.setAudio(cat);
            audioMenu.appendChild(item);
        }
    });
    
    if(!hasAudio) {
         audioMenu.innerHTML = '<div class="settings-item"><span>No alternate audio</span></div>';
    }
};

// Override setupSubtitles to use span separation
CustomPlayer.prototype.setupSubtitles = function(tracks, referer) {
    const old = this.video.querySelectorAll('track');
    old.forEach(t => t.remove());

    const subsMenu = document.getElementById('settings-subs-options');
    subsMenu.innerHTML = `<div class="settings-item selected" data-value="off"><span>Off</span> <span class="check-icon">✓</span></div>`;
    subsMenu.children[0].onclick = () => this.setSubtitle('off');
    
    document.getElementById('current-subs').innerText = 'Off';

    const subtitleList = tracks || []; 

    if(!subtitleList || subtitleList.length === 0) return;

    subtitleList.forEach(track => {
        const label = track.label || track.lang;
        const file = track.file || track.url;
        const kind = track.kind || 'subtitles';
        
        if(label === 'thumbnails' || kind === 'thumbnails') return;

        const trackElem = document.createElement('track');
        trackElem.kind = 'subtitles';
        trackElem.label = label;
        trackElem.srclang = label ? label.toLowerCase().slice(0, 2) : 'en';
        
        let trackUrl = `/proxy/subtitle?url=${encodeURIComponent(file)}`;
        if(referer) trackUrl += `&referer=${encodeURIComponent(referer)}`;
        trackElem.src = trackUrl;
        
        this.video.appendChild(trackElem);

        const item = document.createElement('div');
        item.className = 'settings-item';
        item.dataset.value = label;
        item.innerHTML = `<span>${label}</span> <span class="check-icon">✓</span>`;
        item.onclick = () => this.setSubtitle(label);
        subsMenu.appendChild(item);
    });
};

// Override initSpeedOptions
CustomPlayer.prototype.initSpeedOptions = function() {
    const speedMenu = document.getElementById('settings-speed-options');
    speedMenu.innerHTML = '';
    const speeds = [0.5, 0.75, 1, 1.25, 1.5, 2];
    
    speeds.forEach(speed => {
        const item = document.createElement('div');
        item.className = 'settings-item';
        if(speed === 1) item.classList.add('selected');
        item.innerHTML = `<span>${speed}x</span> <span class="check-icon">✓</span>`;
        item.onclick = () => this.setSpeed(speed);
        speedMenu.appendChild(item);
    });
}

/* Add Source Switching Logic */

// Append to CustomPlayer prototype
CustomPlayer.prototype.setSource = function(serverName) {
    if(this.state.currentServer === serverName) return;
    
    const time = this.video.currentTime;
    this.state.currentServer = serverName;
    this.loadSource(this.state.currentServer, this.state.currentCategory, time);
    
    // Update UI
    const menu = document.getElementById('settings-source-options');
    Array.from(menu.children).forEach(child => {
        if(child.innerText.includes(serverName)) child.classList.add('selected');
        else child.classList.remove('selected');
    });
    document.getElementById('current-source').innerText = serverName;
    
    this.showSubmenu(null);
};

// Update updateSettingsUI to populate Source list
const originalUpdateSettingsUI = CustomPlayer.prototype.updateSettingsUI;
CustomPlayer.prototype.updateSettingsUI = function() {
    // Call original for Audio
    const audioMenu = document.getElementById('settings-audio-options');
    audioMenu.innerHTML = '';
    
    let hasAudio = false;
    ['sub', 'dub', 'raw'].forEach(cat => {
        if(this.state.servers[cat] && this.state.servers[cat].length > 0) {
            hasAudio = true;
            const item = document.createElement('div');
            item.className = 'settings-item';
            if(cat === this.state.currentCategory) item.classList.add('selected');
            item.innerHTML = `<span>${cat.toUpperCase()}</span> <span class="check-icon">✓</span>`;
            item.onclick = () => this.setAudio(cat);
            audioMenu.appendChild(item);
        }
    });
    
    if(!hasAudio) {
         audioMenu.innerHTML = '<div class="settings-item"><span>No alternate audio</span></div>';
    }

    // Populate Sources based on current category
    const sourceMenu = document.getElementById('settings-source-options');
    sourceMenu.innerHTML = '';
    
    const currentServers = this.state.servers[this.state.currentCategory] || [];
    
    if(currentServers.length > 0) {
        currentServers.forEach(server => {
            const item = document.createElement('div');
            item.className = 'settings-item';
            if(server.serverName === this.state.currentServer) item.classList.add('selected');
            item.innerHTML = `<span>${server.serverName}</span> <span class="check-icon">✓</span>`;
            item.onclick = () => this.setSource(server.serverName);
            sourceMenu.appendChild(item);
        });
        document.getElementById('current-source').innerText = this.state.currentServer || 'None';
    } else {
        sourceMenu.innerHTML = '<div class="settings-item"><span>No sources</span></div>';
        document.getElementById('current-source').innerText = 'None';
    }
};

// Hook into setAudio to update Source list when audio changes
const originalSetAudio = CustomPlayer.prototype.setAudio;
CustomPlayer.prototype.setAudio = function(category) {
    if(this.state.currentCategory === category) return;
    
    const time = this.video.currentTime;
    this.state.currentCategory = category;
    
    if(this.state.servers[category] && this.state.servers[category].length > 0) {
        // Pick first server of new category
        this.state.currentServer = this.state.servers[category][0].serverName;
        this.loadSource(this.state.currentServer, category, time);
        
        // Update Audio UI
        const audioMenu = document.getElementById('settings-audio-options');
        Array.from(audioMenu.children).forEach(child => {
            if(child.innerText.includes(category.toUpperCase())) child.classList.add('selected');
            else child.classList.remove('selected');
        });
        document.getElementById('current-audio').innerText = category.charAt(0).toUpperCase() + category.slice(1);
        
        // Refresh Settings UI to update Source list
        this.updateSettingsUI();
    }
    this.showSubmenu(null);
};

/* Override togglePlay to swap SVG icons */
const originalInitControls = CustomPlayer.prototype.initControls;
CustomPlayer.prototype.initControls = function() {
    // Play/Pause
    const playBtn = document.getElementById('play-btn');
    const playIcon = document.getElementById('play-icon');
    
    // SVG Icons
    const iconPlay = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
    const iconPause = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>';
    
    const togglePlay = () => {
        if(this.video.paused) {
            this.video.play();
            playIcon.innerHTML = iconPause;
        } else {
            this.video.pause();
            playIcon.innerHTML = iconPlay;
        }
    };
    
    playBtn.onclick = togglePlay;
    this.video.addEventListener('click', togglePlay);
    
    // Sync external events (e.g. buffering finished)
    this.video.addEventListener('play', () => { playIcon.innerHTML = iconPause; });
    this.video.addEventListener('pause', () => { playIcon.innerHTML = iconPlay; });
    
    // Progress Bar
    const progressContainer = document.querySelector('.progress-container');
    const progressBar = document.querySelector('.progress-bar');
    const timeDisplay = document.querySelector('.time-display');
    
    this.video.addEventListener('timeupdate', () => {
         if(!this.video.duration) return;
         const percent = (this.video.currentTime / this.video.duration) * 100;
         progressBar.style.width = `${percent}%`;
         timeDisplay.innerText = `${this.formatTime(this.video.currentTime)} / ${this.formatTime(this.video.duration)}`;
         
         this.checkSkip(this.state.intro, 'skip-intro');
         this.checkSkip(this.state.outro, 'skip-outro');
    });
    
    progressContainer.addEventListener('click', (e) => {
        const rect = progressContainer.getBoundingClientRect();
        const percent = (e.clientX - rect.left) / rect.width;
        this.video.currentTime = percent * this.video.duration;
    });

    // Volume
    const volSlider = document.getElementById('volume-slider');
    const muteBtn = document.getElementById('mute-btn');
    const iconVol = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>';
    const iconMute = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/></svg>';
    
    volSlider.addEventListener('input', (e) => {
        this.video.volume = e.target.value;
        this.video.muted = false;
        muteBtn.innerHTML = iconVol;
    });
    
    muteBtn.onclick = () => {
         this.video.muted = !this.video.muted;
         muteBtn.innerHTML = this.video.muted ? iconMute : iconVol;
    };
    
    // Fullscreen
    document.getElementById('fullscreen-btn').onclick = () => {
        if(!document.fullscreenElement) {
            this.container.requestFullscreen();
            this.container.classList.add('fullscreen');
        } else {
            document.exitFullscreen();
            this.container.classList.remove('fullscreen');
        }
    };
    
    // Settings Toggle
    document.getElementById('settings-btn').onclick = (e) => {
         e.stopPropagation();
         this.toggleSettingsMenu();
    };

    // Skip Buttons
    document.getElementById('skip-intro').onclick = () => {
         if(this.state.intro) this.video.currentTime = this.state.intro.end;
    };
    document.getElementById('skip-outro').onclick = () => {
         if(this.state.outro) this.video.currentTime = this.state.outro.end;
    };
};
