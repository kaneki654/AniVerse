import abc
from typing import Dict, Any, Optional

class BaseExtractor(abc.ABC):
    @abc.abstractmethod
    def match(self, script: str) -> bool:
        """Return True if this extractor can handle the given script."""
        pass

    @abc.abstractmethod
    def extract(self, script: str) -> Dict[str, Any]:
        """Extract stream URLs from the script."""
        pass
