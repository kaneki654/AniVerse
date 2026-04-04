import httpx
import asyncio

async def test():
    url = "https://tmstr1.cloudnestra.com/pl/H4sIAAAAAAAAAw3OS3KCMAAA0Csl_CrdFQSklmBCPpBdSFCEKIwyHeD07TvBc5TfKvDRHYLgCtTVA1C1EAa.73UwdK_upxhIXiYWV47pK.CDMktzceIXbQluGbyc4TzhcS6Zi94mDh8stW.aLKlmyYtB.0IDQQWAPYXfS3uMYu6SeyfWjddRbqgkzYhcxCZYid5vwGJRnRLNfIDouDVPo9R2.G2TMChShNsHb5idA53h1bAVdYm00umRHmGhKU.K.rbxI8.xsAmH6CzSuSFb.Fs43kqyMMbstrcnvHVPNFE.7_.nntXIoyC1P_vXWokJljUPpFgzDfxNDoaqeJnV2DeMo7vco6oZ.qg8yUAerTQ7CP8AeaRjmkEBAAA-/master.m3u8"
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0", "Referer": "https://cloudnestra.com/"})
            print(resp.status_code)
            print(resp.text[:500])
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
