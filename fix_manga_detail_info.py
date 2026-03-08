import re

with open('app/main.py', 'r') as f:
    content = f.read()

# I see it's using {MANGA_API_BASE}/info/{manga_id}
# Let's verify Consumet mangadex endpoint for info. 
# It is usually /info?id=... as defined in their docs for generic providers, 
# BUT for mangadex specific it might be /manga/mangadex/info/{id} OR /manga/mangadex/info?id={id}
# The previous proxy test showed /manga/mangadex/info/f0712f04-7528-4b76-bc2e-cd4d7927cb88 worked!
# Wait, let me check the python script output:
# Keys: ['id', 'title', 'altTitles', 'description', 'genres', 'themes', 'status', 'releaseDate', 'chapters', 'image']
# It worked perfectly! So /info/{id} is correct.

# One small fix: the detail route needs to handle if "authors" or "rating" is completely missing from API.
# Wait, my python script output didn't have "authors" or "rating".
# Let's ensure the template handles missing authors.

