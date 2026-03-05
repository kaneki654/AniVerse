class CustomPlayer {
    constructor(elementId, episodeId, options = {}) {
        this.wrapper = document.getElementById(elementId);
        if (!this.wrapper) return;
        this.container = this.wrapper.querySelector('.player-container');
        this.video = this.container.querySelector('video');
        this.episodeId = episodeId;
        this.hls = null;
        this.options = options;
        this.nextEpId = options.nextEpId || null;
        
        this.state = {
            currentServer: null,
            currentCategory: 'sub',
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
        this.initMobileGestures();
        this.initSettings();
        
        this.updateVolumeUI(); 
        this.updatePlayPauseUI();
        
        if (window.lucide) {
            window.lucide.createIcons();
        }

        // Initial Mobile Setup
        setTimeout(() => {
            if (this.container) {
                this.container.classList.add('paused');
                this.container.classList.remove('playing');
                this.container.setAttribute('data-volume', 'high');
                this.container.classList.add('show-controls');
                if(this.resetControlsTimeout) this.resetControlsTimeout();
            }
        }, 100);
    }

    async init(initialCategory = 'sub') {
        try {
            if(this.options.servers) {
                this.state.servers = this.options.servers;
            }
            
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
            
            if(this.state.servers[this.state.currentCategory] && this.state.servers[this.state.currentCategory].length > 0) {
                 this.state.currentServer = this.state.servers[this.state.currentCategory][0].serverName;
                 this.loadSource(this.state.currentServer, this.state.currentCategory);
            } else {
                this.showError("No servers available for this episode.");
            }
            
            this.updateSettingsUI();
            this.initSpeedOptions();
        } catch(e) {
            console.error("Init error", e);
            this.showError("Failed to initialize player.");
        }
    }

    async loadSource(serverName, category, startTime = 0) {
        this.showLoading(true);
        this.hideError();
        try {
            const url = `/api/source?episode_id=${this.episodeId}&server=${serverName}&category=${category}`;
            const resp = await fetch(url);
            if (!resp.ok) throw new Error(`HTTP error! status: ${resp.status}`);
            const data = await resp.json();
            
            if(!data.data || !data.data.sources) throw new Error("No sources found");
            
            const source = data.data.sources[0].url;
            const referer = data.data.headers ? data.data.headers.Referer : '';
            
            this.state.intro = data.data.intro || null;
            this.state.outro = data.data.outro || null;

            let proxyUrl = `/proxy/m3u8?url=${encodeURIComponent(source)}`;
            if(referer) proxyUrl += `&referer=${encodeURIComponent(referer)}`;

            this.setupSubtitles(data.data.tracks || data.data.subtitles, referer);

            if(Hls.isSupported()) {
                if(this.hls) this.hls.destroy();
                this.hls = new Hls();
                this.hls.loadSource(proxyUrl);
                this.hls.attachMedia(this.video);
                
                this.hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    this.video.currentTime = startTime;
                    this.video.play().catch(() => {
                        this.state.isPlaying = false;
                        this.updatePlayPauseUI();
                    });
                    this.updateQualityOptions();
                    this.showLoading(false);
                });
                
                this.hls.on(Hls.Events.ERROR, (event, data) => {
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR:
                                console.log("HLS Network error, trying to recover");
                                this.hls.startLoad();
                                break;
                            case Hls.ErrorTypes.MEDIA_ERROR:
                                console.log("HLS Media error, trying to recover");
                                this.hls.recoverMediaError();
                                break;
                            default:
                                console.error("HLS Fatal error", data);
                                this.hls.destroy();
                                this.showError("Video playback error. Please try another server.");
                                break;
                        }
                    }
                });
            } else if (this.video.canPlayType('application/vnd.apple.mpegurl')) {
                this.video.src = proxyUrl;
                this.video.addEventListener('loadedmetadata', () => {
                    this.video.currentTime = startTime;
                    this.video.play().catch(() => {});
                    this.showLoading(false);
                });
                this.video.addEventListener('error', (e) => {
                     this.showError("Video playback error. Please try another server.");
                });
            }
        } catch(e) {
            console.error(e);
            this.showLoading(false);
            this.showError("Failed to load video source. Please try another server.");
        }
    }

    updatePlayPauseUI() {
        if (this.video.paused) {
            this.container.classList.add('paused');
            this.container.classList.remove('playing');
            this.container.classList.add('show-controls');
            if (this.controlsTimeout) clearTimeout(this.controlsTimeout);
        } else {
            this.container.classList.remove('paused');
            this.container.classList.add('playing');
            if(this.resetControlsTimeout) this.resetControlsTimeout();
        }
    }

    updateVolumeUI() {
        const vol = this.video.volume;
        const isMuted = this.video.muted;
        
        let state = 'high';
        
        if (isMuted || vol === 0) {
            state = 'mute';
        } else if (vol <= 0.5) {
            state = 'low';
        } else {
            state = 'high';
        }
        
        this.container.setAttribute('data-volume', state);
    }

    initControls() {
        this.controlsTimeout = null;

        const togglePlay = () => {
            if (this.video.paused) {
                this.video.play().catch(() => {});
                this.showFeedback('play');
            } else {
                this.video.pause();
                this.showFeedback('pause');
            }
        };

        const playBtn = document.getElementById('play-btn');
        if(playBtn) playBtn.onclick = (e) => {
            e.stopPropagation();
            togglePlay();
        };
        
        this.resetControlsTimeout = () => {
            if (this.controlsTimeout) clearTimeout(this.controlsTimeout);
            this.container.classList.add('show-controls');
            
            if (!this.video.paused) {
                this.controlsTimeout = setTimeout(() => {
                    // Don't hide if settings menu is open
                    const menu = document.getElementById('settings-menu');
                    if(menu && menu.style.display === 'flex') return;
                    
                    this.container.classList.remove('show-controls');
                }, 3000);
            }
        };

        this.container.addEventListener('mousemove', () => this.resetControlsTimeout());
        this.container.addEventListener('touchstart', () => this.resetControlsTimeout());
        this.container.addEventListener('click', (e) => {
            if (e.target.closest('.controls-overlay') || 
                e.target.closest('.settings-menu') || 
                e.target.closest('.shortcut-overlay')) {
                this.resetControlsTimeout();
                return;
            }
            togglePlay();
            this.resetControlsTimeout();
        });

        this.video.addEventListener('play', () => this.updatePlayPauseUI());
        this.video.addEventListener('pause', () => this.updatePlayPauseUI());

        const seek = (sec) => {
            this.video.currentTime += sec;
            this.showRipple(sec > 0 ? 'right' : 'left', sec);
            this.resetControlsTimeout();
        };
        
        const prev10 = document.getElementById('prev-10s-btn');
        if(prev10) prev10.onclick = (e) => { e.stopPropagation(); seek(-10); };
        
        const next10 = document.getElementById('next-10s-btn');
        if(next10) next10.onclick = (e) => { e.stopPropagation(); seek(10); };

        const nextBtn = document.getElementById('next-ep-btn');
        if(nextBtn) {
            if(this.nextEpId) {
                nextBtn.onclick = (e) => { e.stopPropagation(); window.location.href = `/watch/${this.nextEpId}`; };
            } else {
                nextBtn.classList.add('disabled');
                nextBtn.style.opacity = '0.5';
            }
        }

        const volSlider = document.getElementById('volume-slider');
        const muteBtn = document.getElementById('mute-btn');
        
        if(volSlider) {
            volSlider.oninput = (e) => {
                this.video.volume = e.target.value;
                this.video.muted = false;
                this.updateVolumeUI();
                this.resetControlsTimeout();
            };
            volSlider.onclick = (e) => e.stopPropagation();
        }

        if(muteBtn) {
            muteBtn.onclick = (e) => {
                e.stopPropagation();
                this.video.muted = !this.video.muted;
                this.updateVolumeUI();
                this.showFeedback(this.video.muted ? 'vol-mute' : 'vol-up');
            };
        }

        const fsBtn = document.getElementById('fullscreen-btn');
        if(fsBtn) {
            fsBtn.onclick = (e) => {
                e.stopPropagation();
                if (!document.fullscreenElement) {
                    this.container.requestFullscreen();
                    this.container.classList.add('fullscreen');
                } else {
                    document.exitFullscreen();
                    this.container.classList.remove('fullscreen');
                }
            };
        }

        const setBtn = document.getElementById('settings-btn');
        if(setBtn) {
            setBtn.onclick = (e) => {
                e.stopPropagation();
                this.toggleSettingsMenu();
                this.resetControlsTimeout();
            };
        }

        const checkSkip = () => {
            const t = this.video.currentTime;
            const intro = document.getElementById('skip-intro');
            const outro = document.getElementById('skip-outro');
            
            if (this.state.intro && t >= this.state.intro.start && t <= this.state.intro.end) {
                intro.classList.add('visible');
                intro.onclick = (e) => { e.stopPropagation(); this.video.currentTime = this.state.intro.end; };
            } else {
                intro.classList.remove('visible');
            }
            
            if (this.state.outro && t >= this.state.outro.start && t <= this.state.outro.end) {
                outro.classList.add('visible');
                outro.onclick = (e) => { e.stopPropagation(); this.video.currentTime = this.state.outro.end; };
            } else {
                outro.classList.remove('visible');
            }
        };

        const bar = document.querySelector('.progress-bar');
        const timeDisplay = document.querySelector('.time-display');
        
        this.video.ontimeupdate = () => {
            const pct = (this.video.currentTime / this.video.duration) * 100 || 0;
            if(bar) bar.style.width = `${pct}%`;
            if(timeDisplay) timeDisplay.innerText = `${this.formatTime(this.video.currentTime)} / ${this.formatTime(this.video.duration)}`;
            checkSkip();
        };
        
        const progContainer = document.querySelector('.progress-container');
        if(progContainer) {
            progContainer.onclick = (e) => {
                e.stopPropagation();
                const rect = e.target.getBoundingClientRect();
                const pos = (e.clientX - rect.left) / rect.width;
                this.video.currentTime = pos * this.video.duration;
            };
        }

        const fwdBtn = document.getElementById('next-10s-btn');
        let pressTimer;
        if(fwdBtn) {
            fwdBtn.onmousedown = () => {
                pressTimer = setTimeout(() => {
                    this.video.playbackRate = 2.0;
                    const fb = document.getElementById('fb-speed');
                    if(fb) fb.classList.add('visible');
                }, 500);
            };
            const releaseSpeed = () => {
                clearTimeout(pressTimer);
                this.video.playbackRate = this.state.speed;
                const fb = document.getElementById('fb-speed');
                if(fb) fb.classList.remove('visible');
            };
            fwdBtn.onmouseup = releaseSpeed;
            fwdBtn.onmouseleave = releaseSpeed;
            fwdBtn.addEventListener('touchstart', (e) => {
                e.preventDefault();
                pressTimer = setTimeout(() => {
                    this.video.playbackRate = 2.0;
                    const fb = document.getElementById('fb-speed');
                    if(fb) fb.classList.add('visible');
                }, 500);
            });
            fwdBtn.addEventListener('touchend', releaseSpeed);
        }

        document.addEventListener('keydown', (e) => {
            if (['INPUT', 'TEXTAREA'].includes(e.target.tagName)) return;
            if (e.ctrlKey || e.altKey || e.metaKey) return;

            switch(e.key.toLowerCase()) {
                case ' ':
                case 'k':
                    e.preventDefault();
                    togglePlay();
                    break;
                case 'arrowright':
                case 'l':
                    e.preventDefault();
                    seek(10);
                    break;
                case 'arrowleft':
                case 'j':
                    e.preventDefault();
                    seek(-10);
                    break;
                case 'f':
                    e.preventDefault();
                    if(fsBtn) fsBtn.click();
                    break;
                case 'm':
                    e.preventDefault();
                    if(muteBtn) muteBtn.click();
                    break;
                case 'arrowup':
                    e.preventDefault();
                    this.video.volume = Math.min(1, this.video.volume + 0.1);
                    this.showToast(`Volume: ${Math.round(this.video.volume*100)}%`);
                    this.updateVolumeUI();
                    break;
                case 'arrowdown':
                    e.preventDefault();
                    this.video.volume = Math.max(0, this.video.volume - 0.1);
                    this.showToast(`Volume: ${Math.round(this.video.volume*100)}%`);
                    this.updateVolumeUI();
                    break;
                case 'n':
                    if (this.nextEpId) window.location.href = `/watch/${this.nextEpId}`;
                    break;
                case '?':
                case '/':
                    if (e.shiftKey || e.key === '?') {
                        const overlay = document.getElementById('shortcut-overlay');
                        if(overlay) overlay.classList.toggle('active');
                    }
                    break;
                case 'escape':
                    const overlay = document.getElementById('shortcut-overlay');
                    if(overlay) overlay.classList.remove('active');
                    const menu = document.getElementById('settings-menu');
                    if(menu) menu.style.display = 'none';
                    break;
            }
            this.resetControlsTimeout();
        });
        
        const closeShortcuts = document.querySelector('.close-shortcuts');
        if(closeShortcuts) {
            closeShortcuts.onclick = (e) => {
                e.stopPropagation();
                document.getElementById('shortcut-overlay').classList.remove('active');
            };
        }
    }

    initMobileGestures() {
        let lastTap = 0;
        let touchStartX = 0;
        let touchStartY = 0;
        
        const container = this.container;
        
        container.addEventListener('touchstart', (e) => {
            touchStartX = e.touches[0].clientX;
            touchStartY = e.touches[0].clientY;
            
            const currentTime = Date.now();
            const tapLength = currentTime - lastTap;
            
            // Double Tap Detection
            if (tapLength < 300 && tapLength > 0) {
                e.preventDefault();
                const rect = container.getBoundingClientRect();
                const relX = touchStartX - rect.left;
                
                if (relX < rect.width * 0.35) {
                    this.video.currentTime -= 10;
                    this.showRipple('left', 10);
                } else if (relX > rect.width * 0.65) {
                    this.video.currentTime += 10;
                    this.showRipple('right', 10);
                }
            }
            lastTap = currentTime;
        }, { passive: false });
        
        // Swipe Volume
        container.addEventListener('touchmove', (e) => {
            const touchX = e.touches[0].clientX;
            const touchY = e.touches[0].clientY;
            const deltaX = touchX - touchStartX;
            const deltaY = touchY - touchStartY;
            
            // Vertical Swipe Check
            if (Math.abs(deltaY) > Math.abs(deltaX) && Math.abs(deltaY) > 20) {
                e.preventDefault();
                
                const sensitivity = 0.005; // Finer control
                // Swipe Up (Negative Y) -> Increase Volume
                let newVol = this.video.volume - (deltaY * sensitivity);
                newVol = Math.max(0, Math.min(1, newVol));
                
                this.video.volume = newVol;
                this.video.muted = false;
                this.updateVolumeUI();
                
                // Only show toast occasionally or update it
                // this.showToast(`Volume: ${Math.round(newVol * 100)}%`);
                
                // Update start point
                // touchStartY = touchY; 
            }
        }, { passive: false });
        
        // Volume toast on end
        container.addEventListener('touchend', (e) => {
             const touchY = e.changedTouches[0].clientY;
             if (Math.abs(touchY - touchStartY) > 20) {
                 this.showToast(`Volume: ${Math.round(this.video.volume * 100)}%`);
             }
        });
    }

    showFeedback(type) {
        const id = `fb-${type}`;
        const el = document.getElementById(id);
        if (el) {
            el.classList.remove('animate');
            void el.offsetWidth;
            el.classList.add('animate');
        }
    }

    showRipple(side, seconds) {
        const ripple = document.getElementById(`ripple-${side}`);
        if (ripple) {
            ripple.classList.add('active');
            setTimeout(() => ripple.classList.remove('active'), 500);
        }
    }

    showToast(msg) {
        const container = document.getElementById('toast-container');
        if(!container) return;
        const toast = document.createElement('div');
        toast.className = 'toast';
        toast.innerText = msg;
        container.appendChild(toast);
        setTimeout(() => toast.remove(), 2000);
    }
    
    showError(msg) {
        this.showToast("Error: " + msg);
        console.error(msg);
    }
    
    hideError() { }

    formatTime(s) {
        if (!s || isNaN(s)) return '0:00';
        const m = Math.floor(s / 60);
        const sec = Math.floor(s % 60);
        return `${m}:${sec < 10 ? '0' : ''}${sec}`;
    }

    showLoading(show) {
        const spinner = document.querySelector('.loading-spinner');
        if(spinner) {
            if(show) spinner.classList.add('active');
            else spinner.classList.remove('active');
        }
    }

    initSettings() {
        document.querySelectorAll('.settings-item').forEach(item => {
            item.onclick = (e) => {
                e.stopPropagation();
                const target = item.dataset.target;
                if(target) this.showSubmenu(target);
            };
        });
        
        document.querySelectorAll('.settings-header').forEach(h => {
            h.onclick = (e) => {
                e.stopPropagation();
                this.showSubmenu(null);
            }
        });
        
        document.addEventListener('click', (e) => {
            const menu = document.getElementById('settings-menu');
            if(menu && menu.style.display === 'flex' && !menu.contains(e.target)) {
                menu.style.display = 'none';
            }
        });
    }

    toggleSettingsMenu() {
        const menu = document.getElementById('settings-menu');
        if(!menu) return;
        menu.style.display = menu.style.display === 'flex' ? 'none' : 'flex';
        this.showSubmenu(null);
    }

    showSubmenu(id) {
        document.querySelector('.settings-main').style.display = id ? 'none' : 'flex';
        document.querySelectorAll('.settings-submenu').forEach(el => el.style.display = 'none');
        if(id) {
            const sub = document.getElementById(`submenu-${id}`);
            if(sub) sub.style.display = 'flex';
        }
    }

    setupSubtitles(tracks, referer) {
        const menu = document.getElementById('settings-subs-options');
        if(!menu) return;
        menu.innerHTML = `<div class="settings-item selected" onclick="player.setSubtitle('off')">Off <i data-lucide="check" class="check-icon"></i></div>`;
        
        (tracks || []).forEach(t => {
            if(t.kind !== 'subtitles') return;
            const track = document.createElement('track');
            track.kind = 'subtitles';
            track.label = t.label;
            track.src = `/proxy/subtitle?url=${encodeURIComponent(t.file)}&referer=${encodeURIComponent(referer)}`;
            this.video.appendChild(track);
            
            const item = document.createElement('div');
            item.className = 'settings-item';
            item.innerHTML = `${t.label} <i data-lucide="check" class="check-icon"></i>`;
            item.onclick = () => this.setSubtitle(t.label);
            menu.appendChild(item);
        });
        if(window.lucide) window.lucide.createIcons();
    }

    setSubtitle(label) {
        Array.from(this.video.textTracks).forEach(t => {
            t.mode = t.label === label ? 'showing' : 'hidden';
        });
        const current = document.getElementById('current-subs');
        if(current) current.innerText = label;
        this.showSubmenu(null);
    }
    
    initSpeedOptions() {
        const menu = document.getElementById('settings-speed-options');
        if(!menu) return;
        menu.innerHTML = '';
        [0.5, 1, 1.5, 2].forEach(s => {
            const item = document.createElement('div');
            item.className = 'settings-item';
            item.innerHTML = `${s}x <i data-lucide="check" class="check-icon"></i>`;
            item.onclick = () => {
                this.state.speed = s;
                this.video.playbackRate = s;
                document.getElementById('current-speed').innerText = s + 'x';
                this.showSubmenu(null);
            };
            menu.appendChild(item);
        });
        if(window.lucide) window.lucide.createIcons();
    }
    
    updateSettingsUI() {
        const audioMenu = document.getElementById('settings-audio-options');
        const sourceMenu = document.getElementById('settings-source-options');
        
        if(audioMenu) {
            audioMenu.innerHTML = '';
            let hasAudio = false;
            ['sub', 'dub', 'raw'].forEach(cat => {
                if(this.state.servers[cat] && this.state.servers[cat].length > 0) {
                    hasAudio = true;
                    const item = document.createElement('div');
                    item.className = 'settings-item';
                    if(cat === this.state.currentCategory) item.classList.add('selected');
                    item.innerHTML = `<span>${cat.toUpperCase()}</span> <i data-lucide="check" class="check-icon"></i>`;
                    item.onclick = () => this.setAudio(cat);
                    audioMenu.appendChild(item);
                }
            });
            if(!hasAudio) audioMenu.innerHTML = '<div class="settings-item"><span>No alternate audio</span></div>';
        }

        if(sourceMenu) {
            sourceMenu.innerHTML = '';
            const currentServers = this.state.servers[this.state.currentCategory] || [];
            if(currentServers.length > 0) {
                currentServers.forEach(server => {
                    const item = document.createElement('div');
                    item.className = 'settings-item';
                    if(server.serverName === this.state.currentServer) item.classList.add('selected');
                    item.innerHTML = `<span>${server.serverName}</span> <i data-lucide="check" class="check-icon"></i>`;
                    item.onclick = () => this.setSource(server.serverName);
                    sourceMenu.appendChild(item);
                });
                const currentSourceEl = document.getElementById('current-source');
                if(currentSourceEl) currentSourceEl.innerText = this.state.currentServer || 'None';
            } else {
                sourceMenu.innerHTML = '<div class="settings-item"><span>No sources</span></div>';
                const currentSourceEl = document.getElementById('current-source');
                if(currentSourceEl) currentSourceEl.innerText = 'None';
            }
        }
        if(window.lucide) window.lucide.createIcons();
    }

    setAudio(category) {
        if(this.state.currentCategory === category) return;
        const time = this.video.currentTime;
        this.state.currentCategory = category;
        if(this.state.servers[category] && this.state.servers[category].length > 0) {
            this.state.currentServer = this.state.servers[category][0].serverName;
            this.loadSource(this.state.currentServer, category, time);
            document.getElementById('current-audio').innerText = category.charAt(0).toUpperCase() + category.slice(1);
            this.updateSettingsUI();
        }
        this.showSubmenu(null);
    }

    setSource(serverName) {
        if(this.state.currentServer === serverName) return;
        const time = this.video.currentTime;
        this.state.currentServer = serverName;
        this.loadSource(this.state.currentServer, this.state.currentCategory, time);
        document.getElementById('current-source').innerText = serverName;
        this.showSubmenu(null);
        this.updateSettingsUI();
    }
    
    updateQualityOptions() {
        if(!this.hls || !this.hls.levels || this.hls.levels.length === 0) return;
        const qualityMenu = document.getElementById('settings-quality-options');
        if(!qualityMenu) return;
        qualityMenu.innerHTML = `<div class="settings-item selected" data-value="auto"><span>Auto</span> <i data-lucide="check" class="check-icon"></i></div>`;
        qualityMenu.children[0].onclick = () => this.setQuality(-1);
        
        this.hls.levels.forEach((level, index) => {
            const item = document.createElement('div');
            item.className = 'settings-item';
            item.dataset.value = index;
            item.innerHTML = `<span>${level.height}p</span> <i data-lucide="check" class="check-icon"></i>`;
            item.onclick = () => this.setQuality(index);
            qualityMenu.appendChild(item);
        });
        if(window.lucide) window.lucide.createIcons();
    }

    setQuality(levelIndex) {
        if(this.hls) {
            this.hls.currentLevel = levelIndex;
            const menu = document.getElementById('settings-quality-options');
            if(menu) {
                Array.from(menu.children).forEach(child => {
                    const val = child.dataset.value;
                    if(val == levelIndex || (levelIndex === -1 && val === 'auto')) {
                        child.classList.add('selected');
                        const qualEl = document.getElementById('current-quality');
                        if(qualEl) qualEl.innerText = child.innerText.trim();
                    } else {
                        child.classList.remove('selected');
                    }
                });
            }
        }
        this.showSubmenu(null);
    }
}
