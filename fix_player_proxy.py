import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

old_logic = """            const source = data.data.sources[0].url;
            const referer = data.data.headers ? data.data.headers.Referer : '';
            
            this.state.intro = data.data.intro || null;
            this.state.outro = data.data.outro || null;

            let proxyUrl = `/proxy/m3u8?url=${encodeURIComponent(source)}`;
            if(referer) proxyUrl += `&referer=${encodeURIComponent(referer)}`;

            this.setupSubtitles(data.data.tracks || data.data.subtitles, referer);

            if(Hls.isSupported()) {"""

new_logic = """            const sourceObj = data.data.sources[0];
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

            this.setupSubtitles(data.data.tracks || data.data.subtitles, referer);

            if (isM3U8 && Hls.isSupported()) {"""

if old_logic in content:
    content = content.replace(old_logic, new_logic)
    with open('app/static/player.js', 'w') as f:
        f.write(content)
    print("Fixed player.js to respect isM3U8 and avoid double proxy!")
else:
    print("Could not find the logic to replace in player.js.")
