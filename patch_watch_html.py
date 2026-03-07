with open('app/templates/watch.html', 'r') as f:
    content = f.read()

old_script = """<script>
    document.addEventListener('DOMContentLoaded', () => {
        const episodeId = "{{ episode_id }}";
        const nextEpId = "{{ next_ep_id if next_ep_id else '' }}";
        const serversData = {{ servers | tojson | safe }};
        
        const player = new CustomPlayer('player-wrapper', episodeId, {
            servers: serversData,
            nextEpId: nextEpId,
            animeId: {{ anime.id | tojson }},
            animeTitle: {{ anime.name | tojson }},
            animePoster: {{ anime.poster | tojson }},
            episodeNum: {{ current_ep.number | tojson }}, 
            episodeTitle: {{ current_ep.title | tojson }}
        });
        
        player.init('sub');
        lucide.createIcons();
    });
</script>"""

new_script = """<script>
    // TOP LEVEL VARIABLES FOR HISTORY SAVING
    window.WATCH_EPISODE_ID = "{{ episode_id }}";
    window.WATCH_ANIME_ID = "{{ anime_id_from_url }}";
    window.WATCH_ANIME_TITLE = {{ anime.name | default('Unknown Anime', true) | tojson }};
    window.WATCH_ANIME_POSTER = {{ anime.poster | default('', true) | tojson }};
    window.WATCH_EPISODE_NUM = {{ current_ep.number | default(0, true) | tojson }};
    window.WATCH_EPISODE_TITLE = {{ current_ep.title | default('Episode ' ~ current_ep.number, true) | tojson }};

    document.addEventListener('DOMContentLoaded', () => {
        const nextEpId = "{{ next_ep_id if next_ep_id else '' }}";
        const serversData = {{ servers | tojson | safe }};
        
        const player = new CustomPlayer('player-wrapper', window.WATCH_EPISODE_ID, {
            servers: serversData,
            nextEpId: nextEpId,
            animeId: window.WATCH_ANIME_ID,
            animeTitle: window.WATCH_ANIME_TITLE,
            animePoster: window.WATCH_ANIME_POSTER,
            episodeNum: window.WATCH_EPISODE_NUM, 
            episodeTitle: window.WATCH_EPISODE_TITLE
        });
        
        player.init('sub');
        lucide.createIcons();
    });
</script>"""

content = content.replace(old_script, new_script)

with open('app/templates/watch.html', 'w') as f:
    f.write(content)
