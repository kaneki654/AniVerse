import random
import asyncio
from typing import List, Any

class ProviderHealthManager:
    def __init__(self, providers: List[Any]):
        self.providers = providers
        # Start all providers at 1.0 (100% health)
        self.health_scores = {p.name: 1.0 for p in providers}

    def mark_success(self, provider_name: str):
        """Increase score slightly on success, capped at 1.0"""
        current = self.health_scores.get(provider_name, 1.0)
        self.health_scores[provider_name] = min(1.0, current + 0.05)

    def mark_failure(self, provider_name: str):
        """Decrease score sharply on failure"""
        current = self.health_scores.get(provider_name, 1.0)
        self.health_scores[provider_name] = max(0.1, current - 0.2)

    def pick_provider(self):
        """
        Weighted selection to prefer healthy providers,
        but still give degraded ones a small chance (discovery).
        """
        names = [p.name for p in self.providers]
        weights = [self.health_scores[p.name] for p in self.providers]
        
        selected_name = random.choices(names, weights=weights, k=1)[0]
        for p in self.providers:
            if p.name == selected_name:
                return p
        return self.providers[0]

async def random_delay(min_sec: float = 0.3, max_sec: float = 1.2):
    """Rate Limit Evasion technique: Random Delays"""
    await asyncio.sleep(random.uniform(min_sec, max_sec))
