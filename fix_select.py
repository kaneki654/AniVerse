import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# Import Select
content = content.replace('from textual.widgets import Header, Footer, Input, Static, Label, Button',
                          'from textual.widgets import Header, Footer, Input, Static, Label, Button, Select')

# Replace Inputs with Selects in detail screen
old_inputs = """                    Horizontal(
                        Label("Ep:", classes="detail-label"),
                        Input(placeholder="1", id="ep-input", restrict=r"^[0-9]+$"),
                        Label("Aud:", classes="detail-label"),
                        Input(placeholder="sub/dub", id="audio-input", value="sub"),"""

new_inputs = """                    Horizontal(
                        Label("Ep:", classes="detail-label"),
                        Select(((str(i), str(i)) for i in range(1, (int(ep_count) if str(ep_count).isdigit() else 12) + 1)), value="1", id="ep-input"),
                        Label("Aud:", classes="detail-label"),
                        Select((("Sub", "sub"), ("Dub", "dub")), value="sub", id="audio-input"),"""

if old_inputs in content:
    content = content.replace(old_inputs, new_inputs)
    print("Replaced inputs with selects!")
else:
    print("Could not find the inputs.")

# Replace query in button press
old_query = """            ep = self.query_one("#ep-input", Input).value
            audio = self.query_one("#audio-input", Input).value"""

new_query = """            ep = self.query_one("#ep-input", Select).value
            audio = self.query_one("#audio-input", Select).value"""

if old_query in content:
    content = content.replace(old_query, new_query)
    print("Updated query logic to read Select!")
else:
    print("Could not find query logic.")

with open('AniVerse-cli/aniverse.py', 'w') as f:
    f.write(content)
