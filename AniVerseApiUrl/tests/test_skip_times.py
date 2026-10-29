"""Skip-time matching and AniSkip selection; no network, no ffmpeg.

    cd AniVerseApiUrl && python3 -m pytest -q tests
"""

import asyncio
import unittest

import httpx
import numpy as np

from app.services import skip_times
from app.services.skip_times import POINT, _longest_shared


def fingerprints(n: int, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).integers(0, 2**32, size=n, dtype=np.uint64).astype("<u4")


class SharedAudioTests(unittest.TestCase):
    def test_finds_the_opening_both_episodes_share(self):
        song = fingerprints(int(90 / POINT), 1)  # a 90 s opening
        a = fingerprints(2900, 2)
        b = fingerprints(2900, 3)
        at_a, at_b = int(212 / POINT), int(31 / POINT)
        a[at_a:at_a + len(song)] = song
        b[at_b:at_b + len(song)] = song
        # Encoding noise: a couple of bits off here and there still matches.
        b[at_b + 10] ^= np.uint32(0b11)

        hit = _longest_shared(a, b, 15, 150)
        self.assertIsNotNone(hit)
        assert hit is not None
        start_a, start_b, length = hit

        self.assertAlmostEqual(start_a, 212, delta=0.5)
        self.assertAlmostEqual(start_b, 31, delta=0.5)
        self.assertAlmostEqual(length, 90, delta=1)

    def test_nothing_shared_is_none(self):
        self.assertIsNone(_longest_shared(fingerprints(2000, 4), fingerprints(2000, 5), 15, 150))

    def test_a_short_jingle_is_not_an_opening(self):
        jingle = fingerprints(int(5 / POINT), 6)
        a, b = fingerprints(2000, 7), fingerprints(2000, 8)
        a[100:100 + len(jingle)] = jingle
        b[400:400 + len(jingle)] = jingle
        self.assertIsNone(_longest_shared(a, b, 15, 150))


class AniSkipChoiceTests(unittest.TestCase):
    def setUp(self):
        skip_times._aniskip_cache[(1, 1)] = (9e18, [
            {"skipType": "op", "episodeLength": 1559.9, "interval": {"startTime": 3.2, "endTime": 93.2}},
            {"skipType": "mixed-op", "episodeLength": 1470.0, "interval": {"startTime": 58.7, "endTime": 148.7}},
            {"skipType": "ed", "episodeLength": 1559.0, "interval": {"startTime": 1417.1, "endTime": 1507.1}},
        ])

    def tearDown(self):
        skip_times._aniskip_cache.pop((1, 1), None)

    def found(self, duration):
        async def go():
            async with httpx.AsyncClient() as client:  # the answer is cached: never used
                return await skip_times._aniskip(client, 1, 1, duration)
        return asyncio.run(go())

    def test_takes_the_entry_for_this_cut(self):
        self.assertEqual(self.found(1471.2), {"intro": {"start": 59, "end": 149}})

    def test_no_entry_for_another_length(self):
        self.assertEqual(self.found(1400.0), {})

    def test_both_when_the_length_matches(self):
        self.assertEqual(self.found(1560.0), {"intro": {"start": 3, "end": 93}, "outro": {"start": 1417, "end": 1507}})


    def test_recap_for_the_same_cut(self):
        skip_times._aniskip_cache[(1, 1)][1].append(
            {"skipType": "recap", "episodeLength": 1560.4, "interval": {"startTime": 0.0, "endTime": 61.5}})
        self.assertEqual(self.found(1560.0)["recap"], {"start": 0, "end": 62})
        self.assertNotIn("recap", self.found(1471.2))


if __name__ == "__main__":
    unittest.main()
