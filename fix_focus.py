import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# Make the app automatically focus the first card when data loads
old_focus = """                        grid.mount_all(cards)
                        self.notify("Data loaded successfully!", severity="information")
                        # Focus the first card
                        cards[0].focus()"""

new_focus = """                        await grid.mount_all(cards)
                        self.notify("Data loaded successfully!", severity="information")
                        # Force focus to the first card so keyboard navigation works immediately
                        if cards:
                            cards[0].focus()"""

if old_focus in content:
    content = content.replace(old_focus, new_focus)
    with open('AniVerse-cli/aniverse.py', 'w') as f:
        f.write(content)
    print("Fixed autofocus logic!")
else:
    print("Could not find the autofocus logic.")
