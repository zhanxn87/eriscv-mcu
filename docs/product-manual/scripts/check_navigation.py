#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Verify that every product-manual HTML page uses the canonical global navigation."""

from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
NAV_ITEMS = (
    ("Family Guide", "index.html"),
    ("Architecture", "architecture.html"),
    ("Software", "software.html"),
    ("Performance", "performance.html"),
    ("Verification", "verification.html"),
    ("FPGA", "fpga-evaluation.html"),
    ("Board/JTAG", "board-jtag-debug.html"),
)
NAV_RE = re.compile(r'<nav\b[^>]*class="[^"]*\bmain-nav\b[^"]*"[^>]*>(.*?)</nav>', re.DOTALL)
PROFILE_NAV_RE = re.compile(r'<nav\b[^>]*class="[^"]*\bprofile-switcher\b[^"]*"[^>]*>(.*?)</nav>', re.DOTALL)
LINK_RE = re.compile(r'<a\b([^>]*)>(.*?)</a>', re.DOTALL)
HREF_RE = re.compile(r'\bhref="([^"]+)"')
CURRENT_RE = re.compile(r'\baria-current="page"')
TAG_RE = re.compile(r'<[^>]+>')


def normalized_target(page: Path, href: str) -> Path:
    parsed = urlparse(href)
    if parsed.scheme or parsed.netloc or parsed.fragment:
        raise ValueError(f"navigation href must be a local page: {href}")
    return (page.parent / parsed.path).resolve()


def main() -> None:
    expected = [(label, (ROOT / path).resolve()) for label, path in NAV_ITEMS]
    profile_pages = tuple(sorted((ROOT / "products").glob("eriscv-m?.html")))
    expected_profiles = [(page.stem.removeprefix("eriscv-").upper(), page.resolve()) for page in profile_pages]
    errors: list[str] = []
    for page in sorted(ROOT.rglob("*.html")):
        text = page.read_text(encoding="utf-8")
        navs = NAV_RE.findall(text)
        if len(navs) != 1:
            errors.append(f"{page}: expected exactly one .main-nav, found {len(navs)}")
            continue
        actual: list[tuple[str, Path, bool]] = []
        for attrs, content in LINK_RE.findall(navs[0]):
            href_match = HREF_RE.search(attrs)
            if href_match is None:
                errors.append(f"{page}: navigation item without href")
                continue
            label = TAG_RE.sub("", content).strip()
            try:
                target = normalized_target(page, href_match.group(1))
            except ValueError as exc:
                errors.append(f"{page}: {exc}")
                continue
            actual.append((label, target, bool(CURRENT_RE.search(attrs))))
        if [(label, target) for label, target, _ in actual] != expected:
            errors.append(f"{page}: navigation labels or targets differ from canonical order")
            continue
        current = [target for _, target, selected in actual if selected]
        expected_current = page.resolve() if page.resolve() in {target for _, target in expected} else None
        if current != ([] if expected_current is None else [expected_current]):
            errors.append(f"{page}: incorrect aria-current navigation state")
        profile_navs = PROFILE_NAV_RE.findall(text)
        if page in profile_pages:
            if len(profile_navs) != 1:
                errors.append(f"{page}: expected exactly one .profile-switcher, found {len(profile_navs)}")
                continue
            profile_links: list[tuple[str, Path, bool]] = []
            for attrs, content in LINK_RE.findall(profile_navs[0]):
                href_match = HREF_RE.search(attrs)
                if href_match is None:
                    continue
                profile_links.append((TAG_RE.sub("", content).strip(), normalized_target(page, href_match.group(1)), bool(CURRENT_RE.search(attrs))))
            if [(label, target) for label, target, _ in profile_links] != expected_profiles:
                errors.append(f"{page}: product-datasheet navigation labels or targets differ from canonical order")
                continue
            if [target for _, target, selected in profile_links if selected] != [page.resolve()]:
                errors.append(f"{page}: incorrect product-profile aria-current state")
        elif profile_navs:
            errors.append(f"{page}: .profile-switcher is only valid on product datasheets")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Navigation OK: {len(list(ROOT.rglob('*.html')))} HTML pages")


if __name__ == "__main__":
    main()
