import sys
from browser_vidPlay import get_player

html_content = get_player("Test", 1, "sub", {"streams": [{"url":"http://test","server":"Test-1"}], "subtitles": []})

with open("test.html", "w") as f:
    f.write(html_content)
