from .base import BaseExtractor
from typing import Dict, Any
import re
try:
    from py_mini_racer import MiniRacer
except ImportError:
    MiniRacer = None

class PackedExtractor(BaseExtractor):
    def match(self, script: str) -> bool:
        return "eval(function(p,a,c,k,e,d)" in script

    def extract(self, script: str) -> Dict[str, Any]:
        if not MiniRacer:
            raise RuntimeError("py_mini_racer is required for PackedExtractor")
            
        modified_script = script.replace("eval(function", "return (function")
        wrapper = f"function unpack() {{ {modified_script} }}"
        
        ctx = MiniRacer()
        ctx.eval(wrapper)
        unpacked = ctx.eval("unpack()")
        
        sources = []
        # Look for url: "https://..." or file: "https://..."
        match = re.search(r'(?:url|file):\s*["\'](https?://[^"\']+)["\']', unpacked)
        if match:
            sources.append({"url": match.group(1)})
            
        return {"streams": sources, "raw": unpacked}
