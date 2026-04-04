import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# Make sure subprocess.Popen doesn't freeze the TUI when playing
old_subprocess = """                subprocess.Popen(mpv_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)"""

new_subprocess = """                # We run mpv asynchronously without blocking the TUI event loop
                self.notify("Playing in MPV...", severity="information")
                import subprocess
                subprocess.Popen(mpv_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)"""

if old_subprocess in content:
    content = content.replace(old_subprocess, new_subprocess)
    with open('AniVerse-cli/aniverse.py', 'w') as f:
        f.write(content)
    print("Fixed MPV spawning to be non-blocking.")
else:
    print("Could not find the subprocess logic.")
