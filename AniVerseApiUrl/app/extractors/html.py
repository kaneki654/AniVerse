from selectolax.parser import HTMLParser
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
