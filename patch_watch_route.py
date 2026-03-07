import re

with open('app/main.py', 'r') as f:
    content = f.read()

# I want to add anime_id to the template context
old_context = """        context={
            "episode_id": full_episode_id,
            "servers": servers_data,
            "anime": anime_info,
            "current_ep": current_ep,
            "next_ep_id": next_ep_id, "episodes": episodes_data.get("episodes", [])
        }"""

new_context = """        context={
            "episode_id": full_episode_id,
            "anime_id_from_url": anime_id,  # Guaranteed to exist
            "servers": servers_data,
            "anime": anime_info,
            "current_ep": current_ep,
            "next_ep_id": next_ep_id, 
            "episodes": episodes_data.get("episodes", [])
        }"""

content = content.replace(old_context, new_context)

with open('app/main.py', 'w') as f:
    f.write(content)
