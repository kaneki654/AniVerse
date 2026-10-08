try:
    # selectolax 1.0 removed the Modest parser; Lexbor (0.3+) is its replacement.
    from selectolax.lexbor import LexborHTMLParser as HTMLParser
except ImportError:  # pragma: no cover - selectolax older than 0.3
    from selectolax.parser import HTMLParser  # type: ignore[assignment]
from typing import List

class HTMLScriptIsolator:
    @staticmethod
    def extract_scripts(html_content: str) -> List[str]:
        """
        Parses the HTML and returns a list of all <script> tag contents.
        This is Step A of the extraction pipeline.
        """
        tree = HTMLParser(html_content)
        scripts = [node.text() for node in tree.css("script") if node.text()]
        return scripts
