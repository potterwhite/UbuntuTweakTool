#!/usr/bin/env python3
"""Web Resources Fetcher — click-to-download approach.

Extracts all links from a web page, filters out navigation,
and attempts to download each candidate by:
  1. HEAD pre-check (if non-HTML content-type, download directly)
  2. Click the link and listen for Playwright's download event
  3. Save the file using the server-provided filename

Usage:
    python3 fetch.py <URL> [--download-dir <DIR>] [--headless]

Dependencies: playwright
"""

import argparse
import asyncio
import sys
import time
from pathlib import Path
from urllib.parse import urlparse, unquote

from playwright.async_api import async_playwright, Error


# ── Formatting ──────────────────────────────────────────────

def format_size(size: int) -> str:
    if size < 1024:
        return f"{size} B"
    elif size < 1024 ** 2:
        return f"{size / 1024:.1f} KB"
    elif size < 1024 ** 3:
        return f"{size / 1024 ** 2:.1f} MB"
    else:
        return f"{size / 1024 ** 3:.2f} GB"


def format_rate(size: int, elapsed: float) -> str:
    if elapsed <= 0:
        return ""
    rate = size / elapsed
    if rate < 1024:
        return f"{rate:.0f} B/s"
    elif rate < 1024 ** 2:
        return f"{rate / 1024:.1f} KB/s"
    else:
        return f"{rate / 1024 ** 2:.1f} MB/s"


# ── Login Detection ─────────────────────────────────────────

async def is_login_page(page) -> bool:
    url = page.url.lower()
    if any(kw in url for kw in ["login", "signin", "sign-in", "auth", "sso", "oauth", "accounts"]):
        return True
    try:
        has_form = await page.evaluate("""() => {
            const forms = document.querySelectorAll('form');
            for (const f of forms) {
                const action = (f.action || '').toLowerCase();
                const html = f.innerHTML.toLowerCase();
                if (action.includes('login') || action.includes('signin') ||
                    action.includes('auth') || html.includes('password') ||
                    html.includes('sign in') || html.includes('log in')) {
                    return true;
                }
            }
            return false;
        }""")
        return has_form
    except Exception:
        return False


async def wait_for_login(page, target_url: str):
    print()
    print("=" * 50)
    print("  Browser is open. Please log in if required.")
    print("  Auto-detecting login status...")
    print("=" * 50)
    print()

    if not await is_login_page(page):
        print("  Page loaded directly, no login required.")
        return

    print("  Login page detected. Please log in manually.")
    print("  Waiting for redirect back to target URL...\n")

    max_wait = 600
    check_interval = 2
    elapsed = 0

    while elapsed < max_wait:
        await asyncio.sleep(check_interval)
        elapsed += check_interval

        if page.url.rstrip("/") == target_url.rstrip("/") or not await is_login_page(page):
            print("  Login successful! Continuing...\n")
            await asyncio.sleep(2)
            return

    print("  Timeout waiting for login. Continuing anyway...\n")


# ── Link Extraction ─────────────────────────────────────────

async def extract_links(page) -> list[dict]:
    """Extract meaningful links from the page, excluding nav/header/footer."""
    links = await page.evaluate("""() => {
        // Strategy 1: NVIDIA-style Angular apps — look for ng-repeat result items
        // These are the actual search/download results, not page navigation
        const ngItems = document.querySelectorAll('[ng-repeat] a[href]');
        if (ngItems.length > 3) {
            const seen = new Set();
            const results = [];
            for (const a of ngItems) {
                const href = a.href;
                if (!href || seen.has(href)) continue;
                const h = href.toLowerCase();
                if (h === '#' || h.startsWith('javascript:') || h.startsWith('mailto:')) continue;
                seen.add(href);
                results.push({
                    href: href,
                    text: (a.textContent || '').trim().substring(0, 200)
                });
            }
            if (results.length > 0) return results;
        }

        // Strategy 2: Generic — find main content area
        const mainSelectors = [
            'main', '[role="main"]', '#main', '#content', '#app',
            '.main-content', '.content', '.container', '.page-content',
            '#__next', '#root', '#app-root', '.layout', '#layout'
        ];
        let main = null;
        for (const sel of mainSelectors) {
            const el = document.querySelector(sel);
            if (el && el.offsetHeight > 200) {
                main = el;
                break;
            }
        }
        const root = main || document.body;
        if (!root) return [];

        // Collect all <a> elements
        const anchors = root.querySelectorAll('a[href]');
        const seen = new Set();
        const results = [];

        for (const a of anchors) {
            const href = a.href;
            if (!href || seen.has(href)) continue;

            // Skip anchors, javascript:, mailto:
            const h = href.toLowerCase();
            if (h === '#' || h.startsWith('javascript:') || h.startsWith('mailto:')) continue;

            // Check if inside header/footer/nav
            let el = a;
            let skip = false;
            while (el && el !== root) {
                const tag = el.tagName?.toLowerCase();
                const role = (el.getAttribute('role') || '').toLowerCase();
                if (tag === 'header' || tag === 'footer' || tag === 'nav' ||
                    tag === 'aside' || role === 'navigation' || role === 'banner' ||
                    role === 'contentinfo') {
                    skip = true;
                    break;
                }
                // Check class/id for nav patterns
                const cls = (el.className || '').toLowerCase();
                const id = (el.id || '').toLowerCase();
                const combined = cls + ' ' + id;
                if (/\b(header|footer|nav|sidebar|menu|breadcrumb)\b/.test(combined)) {
                    skip = true;
                    break;
                }
                el = el.parentElement;
            }
            if (skip) continue;

            seen.add(href);
            results.push({
                href: href,
                text: (a.textContent || '').trim().substring(0, 200)
            });
        }
        return results;
    }""")

    return links


# ── Link Filtering ──────────────────────────────────────────

SOCIAL_DOMAINS = {
    "twitter.com", "x.com", "facebook.com", "linkedin.com",
    "instagram.com", "youtube.com", "tiktok.com", "reddit.com",
}

NAV_WORDS = {
    "home", "about", "contact", "blog", "forum", "forums",
    "login", "logout", "sign in", "sign up", "register",
    "search", "faq", "help", "support", "privacy", "terms",
    "cookie", "subscribe", "newsletter", "menu", "close",
    "back", "next", "previous", "more", "see more", "view all",
}


def is_social_link(url: str) -> bool:
    try:
        return urlparse(url).netloc.lower().lstrip("www.") in SOCIAL_DOMAINS
    except Exception:
        return False


def is_nav_link(text: str) -> bool:
    t = text.strip().lower()
    if not t or len(t) < 2:
        return True
    return t in NAV_WORDS


def is_file_url(url: str) -> bool:
    """Check if URL looks like a direct file link."""
    file_exts = [
        ".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar",
        ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
        ".deb", ".rpm", ".exe", ".msi", ".dmg", ".pkg", ".appimage",
        ".iso", ".img", ".bin", ".run", ".sh", ".py", ".js",
        ".mp4", ".mp3", ".wav", ".avi", ".mkv", ".mov",
        ".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp",
        ".txt", ".csv", ".json", ".xml", ".yaml", ".yml",
    ]
    path = urlparse(url).path.lower()
    return any(path.endswith(ext) for ext in file_exts)


def filter_download_candidates(links: list[dict]) -> list[dict]:
    """Filter links to likely download candidates."""
    candidates = []
    seen = set()

    for link in links:
        url = link["href"]
        text = link["text"]

        # Skip social links
        if is_social_link(url):
            continue

        # Skip nav links
        if is_nav_link(text):
            continue

        # Deduplicate
        if url in seen:
            continue
        seen.add(url)

        candidates.append(link)

    # Sort: file URLs first, then by text length (longer = more descriptive)
    candidates.sort(key=lambda l: (not is_file_url(l["href"]), -len(l["text"])))

    return candidates


# ── Download Helpers ─────────────────────────────────────────

def filename_from_response(resp) -> str | None:
    """Extract filename from Content-Disposition header."""
    cd = resp.headers.get("content-disposition", "")
    if "filename=" in cd:
        try:
            part = cd.split("filename=")[-1].strip().strip('"').strip("'")
            return unquote(part) if part else None
        except Exception:
            pass
    return None


def filename_from_url(url: str) -> str:
    """Extract filename from URL path."""
    path = urlparse(url).path.rstrip("/")
    if path:
        name = path.split("/")[-1]
        if name and "." in name:
            return unquote(name)
    return ""


def is_html_content_type(resp) -> bool:
    """Check if response is HTML."""
    ct = resp.headers.get("content-type", "").lower()
    return "text/html" in ct


# ── Click Download ──────────────────────────────────────────

async def click_download(page, link: dict, download_dir: Path,
                         idx: int, total: int) -> str | None:
    """Try to download a file.

    Strategy:
      1. If URL looks like a direct file link, GET it directly via browser context
      2. Otherwise, scroll element into view, click, listen for download event
    """
    url = link["href"]
    text = link["text"][:60]

    try:
        # Phase 1: Direct GET via browser context (shares cookies/referrer)
        # This works for direct file URLs even when the element isn't visible
        try:
            fn = filename_from_url(url)
            if fn and "." in fn:
                # URL looks like a direct file link — try GET directly
                fp = download_dir / fn
                if fp.exists() and fp.stat().st_size > 1000:
                    print(f"    [{idx}/{total}] SKIP  {fn}  ({format_size(fp.stat().st_size)})")
                    return "skip"

                t0 = time.monotonic()
                resp = await page.request.get(url, timeout=120000)
                ct = resp.headers.get("content-type", "").lower()
                cd = resp.headers.get("content-disposition", "").lower()

                # If we got HTML back, it's probably a login/redirect page
                if "text/html" in ct and "attachment" not in cd:
                    raise Exception("Got HTML response, falling through to click")

                body = await resp.body()
                elapsed = time.monotonic() - t0

                if len(body) < 100:
                    raise Exception("Empty response")

                fn = filename_from_response(resp) or fn
                fp = download_dir / fn
                fp.write_bytes(body)
                print(f"    [{idx}/{total}] OK    {fn}  {format_size(len(body))}  ({format_rate(len(body), elapsed)}, {elapsed:.1f}s)")
                return "ok"
        except Exception:
            pass  # Fall through to click approach

        # Phase 2: Click and listen for download
        try:
            link_el = page.locator(f'a[href="{url}"]').first
            if not await link_el.count():
                # Try partial match
                link_el = page.locator(f'a[href*="{url.split("/")[-1]}"]').first
                if not await link_el.count():
                    return None

            # Scroll element into view (needed for virtual-scrolling pages like NVIDIA)
            try:
                await link_el.scroll_into_view_if_needed(timeout=3000)
                await asyncio.sleep(0.3)
            except Exception:
                pass
        except Exception:
            return None

        download_event = asyncio.Event()
        nav_event = asyncio.Event()
        popup_event = asyncio.Event()
        download_obj = [None]
        popup_obj = [None]

        def on_download(dl):
            download_obj[0] = dl
            download_event.set()

        def on_nav(frame):
            if frame == page.main_frame:
                nav_event.set()

        def on_popup(popup):
            popup_obj[0] = popup
            popup_event.set()

        page.on("download", on_download)
        page.on("framenavigated", on_nav)
        page.on("popup", on_popup)

        try:
            await link_el.click(timeout=5000)

            # Wait for download, navigation, or popup
            tasks = [
                asyncio.create_task(download_event.wait()),
                asyncio.create_task(nav_event.wait()),
                asyncio.create_task(popup_event.wait()),
            ]
            done, pending = await asyncio.wait(
                tasks, timeout=8, return_when=asyncio.FIRST_COMPLETED
            )

            # Cancel pending tasks
            for t in pending:
                t.cancel()
                try:
                    await t
                except asyncio.CancelledError:
                    pass

            if download_event.is_set():
                # Download triggered directly
                dl = download_obj[0]
                fn = dl.suggested_filename or f"file_{idx}"
                fp = download_dir / fn

                if fp.exists() and fp.stat().st_size > 1000:
                    print(f"    [{idx}/{total}] SKIP  {fn}  ({format_size(fp.stat().st_size)})")
                    return "skip"

                t0 = time.monotonic()
                await dl.save_as(str(fp))
                elapsed = time.monotonic() - t0
                size = fp.stat().st_size
                print(f"    [{idx}/{total}] OK    {fn}  {format_size(size)}  ({format_rate(size, elapsed)}, {elapsed:.1f}s)")
                return "ok"

            elif popup_event.is_set():
                # New tab opened — wait for download in new tab
                popup = popup_obj[0]
                try:
                    popup_dl_event = asyncio.Event()
                    popup_dl_obj = [None]

                    def on_popup_download(dl):
                        popup_dl_obj[0] = dl
                        popup_dl_event.set()

                    popup.on("download", on_popup_download)

                    # Wait up to 15s for download in popup
                    try:
                        await asyncio.wait_for(popup_dl_event.wait(), timeout=15)
                        dl = popup_dl_obj[0]
                        fn = dl.suggested_filename or f"file_{idx}"
                        fp = download_dir / fn

                        if fp.exists() and fp.stat().st_size > 1000:
                            print(f"    [{idx}/{total}] SKIP  {fn}  ({format_size(fp.stat().st_size)})")
                            return "skip"

                        t0 = time.monotonic()
                        await dl.save_as(str(fp))
                        elapsed = time.monotonic() - t0
                        size = fp.stat().st_size
                        print(f"    [{idx}/{total}] OK    {fn}  {format_size(size)}  ({format_rate(size, elapsed)}, {elapsed:.1f}s)")
                        return "ok"
                    except asyncio.TimeoutError:
                        # No download in popup — close it
                        try:
                            await popup.close()
                        except Exception:
                            pass
                        return "skip"
                    finally:
                        popup.remove_listener("download", on_popup_download)
                except Exception:
                    try:
                        await popup.close()
                    except Exception:
                        pass
                    return "skip"

            elif nav_event.is_set():
                # Page navigated — go back
                await asyncio.sleep(1)
                try:
                    if page.url != url:
                        await page.go_back(timeout=10000, wait_until="domcontentloaded")
                        await asyncio.sleep(1)
                    else:
                        await page.go_back(timeout=10000, wait_until="domcontentloaded")
                        await asyncio.sleep(1)
                except Exception:
                    try:
                        await page.goto(url, timeout=15000, wait_until="domcontentloaded")
                    except Exception:
                        pass
                return "nav"

            else:
                # Timeout — nothing happened
                return "skip"

        finally:
            page.remove_listener("download", on_download)
            page.remove_listener("framenavigated", on_nav)
            page.remove_listener("popup", on_popup)

    except Exception as e:
        print(f"    [{idx}/{total}] ERROR {text}  ({e})")
        return None


# ── Main ────────────────────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser(description="Web Resources Fetcher — click-to-download")
    parser.add_argument("url", help="URL to fetch resources from")
    parser.add_argument("--download-dir", "-d", default="./downloads", help="Download directory")
    parser.add_argument("--headless", action="store_true", help="Run in headless mode")
    args = parser.parse_args()

    download_dir = Path(args.download_dir).resolve()
    download_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n[INFO] Fetching: {args.url}")

    async with async_playwright() as p:
        context = await p.chromium.launch_persistent_context(
            user_data_dir=str(Path.home() / ".cache" / "fetcher-browser-data"),
            headless=args.headless,
            accept_downloads=True,
        )
        page = context.pages[0] if context.pages else await context.new_page()

        await page.goto(args.url, wait_until="domcontentloaded", timeout=30000)
        await page.wait_for_load_state("networkidle", timeout=15000)

        await wait_for_login(page, args.url)

        print("  Scrolling page to load all content...")
        for i in range(20):
            try:
                await page.evaluate("window.scrollBy(0, window.innerHeight)")
            except Error as e:
                if "Execution context was destroyed" in str(e) or "navigation" in str(e).lower():
                    await page.wait_for_load_state("domcontentloaded", timeout=10000)
                    await asyncio.sleep(1)
                else:
                    raise
            await asyncio.sleep(0.3)

        print("  Extracting links...")
        links = await extract_links(page)
        print(f"\n  Found {len(links)} links on page (after filtering):")

        for i, link in enumerate(links, 1):
            text = link["text"][:80] or "(no text)"
            print(f"    {i}. {text}")

        candidates = filter_download_candidates(links)
        print(f"\n  {len(candidates)} download candidates to try:")
        for i, c in enumerate(candidates, 1):
            print(f"    {i}. {c['text'][:80]}")

        print(f"\n  Downloading to: {download_dir}\n")

        downloaded = 0
        seen_files = set()

        for i, link in enumerate(candidates, 1):
            # Deduplicate by filename
            url = link["href"]
            fn = filename_from_url(url)
            if fn and fn in seen_files:
                print(f"    [{i}/{len(candidates)}] SKIP  {fn}  (duplicate)")
                continue
            if fn:
                seen_files.add(fn)

            result = await click_download(page, link, download_dir, i, len(candidates))
            if result == "ok":
                downloaded += 1

        print(f"\n{'=' * 50}")
        print(f"  Done! {downloaded}/{len(candidates)} files downloaded.")
        print(f"  Saved to: {download_dir}")
        print(f"{'=' * 50}\n")

    await context.close()


if __name__ == "__main__":
    asyncio.run(main())
