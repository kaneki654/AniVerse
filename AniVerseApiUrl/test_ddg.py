import urllib.request
import re

url = "https://html.duckduckgo.com/html/?q=site:anitaku.to+attack+on+titan+dub"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    html = urllib.request.urlopen(req).read().decode('utf-8')
    links = re.findall(r'href="(.*?)"', html)
    for link in links:
        if 'category' in link and 'anitaku' in link:
            print(link)
except Exception as e:
    print(e)
