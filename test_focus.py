from textual.app import App, ComposeResult
from textual.widgets import Button

class TestApp(App):
    BINDINGS = [
        ("right", "focus_next", "Next"),
        ("left", "focus_previous", "Prev")
    ]
    def compose(self) -> ComposeResult:
        yield Button("1")
        yield Button("2")
        yield Button("3")

if __name__ == "__main__":
    pass
