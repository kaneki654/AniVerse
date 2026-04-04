import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

old_bindings = """    BINDINGS = [
        ("q", "quit", "Quit"),
        ("right", "focus_next", "Next"),
        ("left", "focus_previous", "Prev"),
        ("down", "focus_down", "Down"),
        ("up", "focus_up", "Up"),
    ]
    
    def action_focus_down(self) -> None:
        # Move focus by roughly 5 items (grid size)
        for _ in range(5):
            self.screen.focus_next()
            
    def action_focus_up(self) -> None:
        for _ in range(5):
            self.screen.focus_previous()"""

new_bindings = """    BINDINGS = [
        ("q", "quit", "Quit"),
        ("right", "focus_next", "Next"),
        ("left", "focus_previous", "Prev"),
        ("down", "focus_next", "Next"),
        ("up", "focus_previous", "Prev"),
    ]"""

if old_bindings in content:
    content = content.replace(old_bindings, new_bindings)
    with open('AniVerse-cli/aniverse.py', 'w') as f:
        f.write(content)
    print("Fixed bindings to be globally safe!")
else:
    print("Could not find the bindings logic.")

