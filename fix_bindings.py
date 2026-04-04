import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# Replace the broken bindings with working ones that use standard focus_next and focus_previous
old_bindings = """    BINDINGS = [
        ("q", "quit", "Quit"),
        ("up", "focus_up", "Up"),
        ("down", "focus_down", "Down"),
        ("left", "focus_left", "Left"),
        ("right", "focus_right", "Right"),
    ]"""

new_bindings = """    BINDINGS = [
        ("q", "quit", "Quit"),
    ]
    
    def action_focus_up(self) -> None:
        self.screen.focus_previous()
        
    def action_focus_down(self) -> None:
        self.screen.focus_next()
        
    def action_focus_left(self) -> None:
        self.screen.focus_previous()
        
    def action_focus_right(self) -> None:
        self.screen.focus_next()"""

# I should instead just remove the broken arrow key bindings so the scroll works natively, 
# and let the user navigate via standard Tab or provide simple focus_next on left/right.
new_bindings_simple = """    BINDINGS = [
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

if old_bindings in content:
    content = content.replace(old_bindings, new_bindings_simple)
    with open('AniVerse-cli/aniverse.py', 'w') as f:
        f.write(content)
    print("Fixed bindings!")
else:
    print("Could not find the bindings block.")
