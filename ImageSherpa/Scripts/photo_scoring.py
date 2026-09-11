"""
Bundled query-function scripts, invoked by recipe templates via osxphotos's
--query-function flag: --query-function photo_scoring.py::top_percent

--query-function only receives the already-filtered list of PhotoInfo objects
(after any --place/--person/--year/etc. flags on the same command line have
already narrowed the set) and must return a list of PhotoInfo objects. It does
NOT accept extra CLI arguments of its own, so any user-configurable parameter
(like "top 20%" vs "top 33%") is passed in via environment variable instead,
set by the app immediately before invoking osxphotos:

    env OSXPHOTOS_TOP_PERCENT=20 osxphotos export ... --query-function photo_scoring.py::top_percent

This keeps a single script reusable across every "best photos of X" recipe
(place, person, year, keyword, album) since the percentile logic doesn't
depend on which filter narrowed the set beforehand.
"""

import os
from typing import List
from osxphotos import PhotoInfo


def _percent_threshold() -> float:
    """Reads OSXPHOTOS_TOP_PERCENT (default 20) and returns it as a 0-1 fraction."""
    raw = os.environ.get("OSXPHOTOS_TOP_PERCENT", "20")
    try:
        pct = float(raw)
    except ValueError:
        pct = 20.0
    pct = max(0.0, min(pct, 100.0))
    return pct / 100.0


def top_percent(photos: List[PhotoInfo]) -> List[PhotoInfo]:
    """
    Returns the top N% of the given photos, ranked by Apple's overall
    aesthetic score (photo.score.overall). N comes from the
    OSXPHOTOS_TOP_PERCENT environment variable, default 20.

    Important: "top N%" is relative to whatever set of photos was already
    passed in. If this runs after --place "Chicago", it returns the top N%
    of Chicago photos, not the top N% of the whole library. That's the
    intended behavior for "best photos of <city>" style recipes: chain a
    query filter with this scoring function on the same command line.

    Photos with no score data (score is None, which can happen for videos
    or photos that haven't been through Apple's on-device analysis yet)
    are excluded rather than sorted arbitrarily.
    """
    scored = [
        p for p in photos
        if p.score is not None and p.score.overall is not None
    ]
    if not scored:
        return []

    scored.sort(key=lambda p: p.score.overall, reverse=True)
    fraction = _percent_threshold()
    keep_count = max(1, round(len(scored) * fraction))
    return scored[:keep_count]
