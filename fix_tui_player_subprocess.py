import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

old_subprocess = """                self.notify(f"Stream found on {server_name}! Launching MPV...", severity="information")
                
                mpv_args = ["mpv", stream_url, "--title=AniVerse Player", "--fs"]
                if sub_url:
                    mpv_args.append(f"--sub-file={sub_url}")
                if "Referer" in headers:
                    mpv_args.append(f"--http-header-fields=Referer: {headers['Referer']}")
                    
                subprocess.Popen(mpv_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)"""

new_subprocess = """                self.notify(f"Stream found on {server_name}! Launching {player.upper()}...", severity="information")
                
                if player == "vlc":
                    vlc_args = ["vlc", stream_url]
                    if sub_url:
                        vlc_args.append(f"--sub-file={sub_url}")
                    if "Referer" in headers:
                        vlc_args.append(f"--http-referrer={headers['Referer']}")
                    subprocess.Popen(vlc_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
                else:
                    mpv_args = ["mpv", stream_url, "--title=AniVerse Player", "--fs"]
                    if sub_url:
                        mpv_args.append(f"--sub-file={sub_url}")
                    if "Referer" in headers:
                        mpv_args.append(f"--http-header-fields=Referer: {headers['Referer']}")
                        
                    subprocess.Popen(mpv_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)"""

if old_subprocess in content:
    content = content.replace(old_subprocess, new_subprocess)
    with open('AniVerse-cli/aniverse.py', 'w') as f:
        f.write(content)
    print("Fixed subprocess logic!")
else:
    print("Could not find the subprocess logic to replace.")
