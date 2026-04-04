from .base import BaseExtractor
from typing import Dict, Any
from Crypto.Cipher import AES
import base64
import json

class EncryptedExtractor(BaseExtractor):
    def match(self, script: str) -> bool:
        return "CryptoJS.AES.decrypt" in script

    def extract(self, script: str, key: str = "", iv: str = "") -> Dict[str, Any]:
        """
        Extract streams by decrypting AES payload.
        In a real scenario, key and iv might be extracted dynamically from the script.
        """
        # Pseudo extraction of encrypted payload
        # enc = ... regex to find encrypted string
        enc = "..." # placeholder
        
        if not key:
            raise ValueError("Decryption key required")
            
        cipher = AES.new(key.encode(), AES.MODE_CBC, iv.encode() if iv else key.encode())
        decrypted = cipher.decrypt(base64.b64decode(enc))
        
        # Remove padding (PKCS7)
        padding_len = decrypted[-1]
        decrypted = decrypted[:-padding_len]
        
        try:
            data = json.loads(decrypted.decode())
            return {"streams": data.get("sources", [])}
        except Exception:
            return {"raw_decrypted": decrypted.decode()}
