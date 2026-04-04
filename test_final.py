import asyncio
from AniVerseApiUrl.app.providers.gogoanime import GogoAnimeProvider

async def main():
    p = GogoAnimeProvider()
    print("Testing 166531 (Oshi no Ko Season 2)")
    print("SUB:", await p.resolve("166531", 1, "sub"))
    print("DUB:", await p.resolve("166531", 1, "dub"))
    
    print("\nTesting 164172 (Amagami Sister)")
    print("SUB:", await p.resolve("164172", 1, "sub"))
    print("DUB:", await p.resolve("164172", 1, "dub"))

asyncio.run(main())
