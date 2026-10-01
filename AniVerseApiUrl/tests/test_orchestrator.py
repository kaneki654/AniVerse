"""Resolver behaviour with stand-in providers; nothing here touches the network.

    cd AniVerseApiUrl && python3 -m pytest -q tests
"""

import asyncio
import base64
import json
import time
import unittest

from app.core.cache import cache
from app.core.orchestrator import ResolverOrchestrator
from app.providers.zokoanime import _KEY, decode_blob


class FakeProvider:
    """Answers after [delay] seconds with [streams] for its [categories]."""

    def __init__(self, name, delay, categories=("sub", "dub"), streams=None, subtitles=None):
        self.__class__ = type(name, (FakeProvider,), {})
        self.delay = delay
        self.categories = categories
        self.streams = streams
        self.subtitles = subtitles or []
        self.cancelled = False

    async def resolve(self, anilist_id, episode, category="sub"):
        try:
            await asyncio.sleep(self.delay)
        except asyncio.CancelledError:
            self.cancelled = True
            raise
        if category not in self.categories:
            return {"error": f"no {category}"}
        streams = self.streams if self.streams is not None else [
            {"url": f"https://{type(self).__name__.lower()}.test/{category}.m3u8",
             "server": type(self).__name__, "category": category}]
        return {"streams": [dict(s) for s in streams], "subtitles": list(self.subtitles)}


def resolver(*providers, settle=0.3, timeout=5.0):
    orch = ResolverOrchestrator(providers=list(providers))
    orch.SETTLE_SECONDS = settle
    orch.PROVIDER_TIMEOUT_SECONDS = timeout
    return orch


class SettleTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        cache._store.clear()

    async def test_stragglers_are_cut_off_once_a_stream_is_in(self):
        fast = FakeProvider("Fast", 0.01)
        slow = FakeProvider("Slow", 3.0)
        started = time.monotonic()
        result = await resolver(fast, slow).resolve_episode("1", 1, "sub", fresh=True)
        took = time.monotonic() - started

        self.assertLess(took, 1.5, "waited for the straggler instead of settling")
        self.assertEqual([s["server"] for s in result["streams"]], ["Fast"])
        self.assertTrue(slow.cancelled)

    async def test_a_straggler_inside_the_window_still_counts(self):
        result = await resolver(FakeProvider("Fast", 0.01), FakeProvider("Soon", 0.1),
                                settle=1.0).resolve_episode("1", 1, "sub", fresh=True)
        self.assertEqual({s["server"] for s in result["streams"]}, {"Fast", "Soon"})

    async def test_nothing_playable_still_waits_for_everyone(self):
        late = FakeProvider("Late", 0.6)
        result = await resolver(FakeProvider("Broken", 0.01, categories=()), late,
                                settle=0.1).resolve_episode("1", 1, "sub", fresh=True)
        self.assertEqual([s["server"] for s in result["streams"]], ["Late"])

    async def test_sub_streams_do_not_settle_a_dub_request(self):
        # Answers a dub request with sub streams only: must not start the clock.
        subs_only = FakeProvider("SubsOnly", 0.01, streams=[
            {"url": "https://x.test/sub.m3u8", "server": "SubsOnly", "category": "sub"}])
        dub = FakeProvider("Dub", 0.6)
        result = await resolver(subs_only, dub, settle=0.1).resolve_episode("1", 1, "dub", fresh=True)
        self.assertEqual([s["server"] for s in result["streams"]], ["Dub"])

    async def test_unfinished_dub_probe_is_unknown_not_no(self):
        fast_sub_only = FakeProvider("FastSub", 0.01, categories=("sub",))
        slow = FakeProvider("Slow", 3.0)
        result = await resolver(fast_sub_only, slow).resolve_episode("1", 1, "sub", fresh=True)
        self.assertIsNone(result["hasDub"])


class SubtitlePairingTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        cache._store.clear()

    async def test_each_stream_keeps_its_own_providers_tracks(self):
        a = FakeProvider("A", 0.01, subtitles=[{"file": "https://a.test/en.vtt", "label": "English",
                                                 "kind": "captions"}])
        b = FakeProvider("B", 0.02, subtitles=[{"file": "https://b.test/thumbs.vtt", "kind": "thumbnails"}])
        result = await resolver(a, b, settle=1.0).resolve_episode("1", 1, "sub", fresh=True)
        by_server = {s["server"]: s["subtitles"] for s in result["streams"]}

        self.assertEqual([t["file"] for t in by_server["A"]], ["https://a.test/en.vtt"])
        self.assertEqual(by_server["B"], [], "a thumbnail strip is not a subtitle track")


class ZokoBlobTests(unittest.TestCase):
    def test_decodes_the_player_config(self):
        config = {"src": "https://hls.example/master.m3u8", "subtitles": []}
        raw = json.dumps(config).encode()
        blob = base64.b64encode(bytes(b ^ _KEY[i % len(_KEY)] for i, b in enumerate(raw))).decode()
        self.assertEqual(decode_blob(blob), config)

    def test_garbage_is_none(self):
        self.assertIsNone(decode_blob("not base64 at all!"))


if __name__ == "__main__":
    unittest.main()
