#!/usr/bin/env python3
"""
Web Resources Fetcher
- Opens a browser for login if the site requires authentication
- Clicks each link on the page, captures downloads via browser events
- No URL pattern matching — works on any site

Usage: python3 fetch.py <url> [--output <dir>] [--headless] [--no-login]
"""
import argparse
import asyncio
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

from playwright.async_api import async_playwright


def parse_args():
    parser = argparse.ArgumentParser(
        description="Web Resources Fetcher - click links and capture browser downloads",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples:
  %(prog)s https://example.com/downloads
  %(prog)s https://example.com/downloads --output ~/my-downloads
  %(prog)s https://example.com/files --headless --no-login
        """,
    )
    parser.add_argument("url", help="Target web page URL")
    parser.add_argument("-o", "--output", default=None,
                        help="Download directory (default: ./downloads)")
    parser.add_argument("--headless", action="store_true",
                        help="Run browser in headless mode (no window)")
    parser.add_argument("--no-login", action="store_true",
                        help="Skip login detection, scrape directly")
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Login helpers
# ---------------------------------------------------------------------------

async def wait_for_login(page, target_url, timeout_sec=300, skip=False):
    """Wait for user to log in. Detects via URL change or page content."""
    if skip:
        print("  Skipping login detection")
        return True

    print("\n" + "=" * 50)
    print("  Browser is open. Please log in if required.")
    print("  Auto-detecting login status...")
    print("=" * 50 + "\n")

    await page.goto(target_url, wait_until="domcontentloaded", timeout=30000)
    await asyncio.sleep(2)

    current = page.url
    login_indicators = ["/login", "/signin", "/sign-in", "/auth", "accounts."]
    if not any(ind in current.lower() for ind in login_indicators):
        print(f"  Page loaded directly, no login required.\n")
        return True

    for i in range(timeout_sec):
        try:
            url = page.url
            if not any(ind in url.lower() for ind in login_indicators):
                print(f"\n  Login successful! (redirected to: {url[:60]})\n")
                return True
            has_session = await page.evaluate("""() => {
                const t = (document.body.innerText || '').toLowerCase();
                return t.includes('sign out') || t.includes('log out') ||
                       t.includes('my account') || t.includes('dashboard');
            }""")
            if has_session:
                print(f"\n  Login successful!\n")
                return True
        except Exception:
            pass
        if i % 5 == 0:
            sys.stdout.write(f"\r  Waiting for login... {i}s")
            sys.stdout.flush()
        await asyncio.sleep(1)

    print("\n  Timeout reached, attempting download anyway...\n")
    return False


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def format_size(size_bytes):
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1048576:
        return f"{size_bytes / 1024:.0f} KB"
    elif size_bytes < 1073741824:
        return f"{size_bytes / 1048576:.1f} MB"
    else:
        return f"{size_bytes / 1073741824:.2f} GB"


def format_rate(bytes_count, elapsed_sec):
    if elapsed_sec <= 0:
        return ""
    rate = bytes_count / elapsed_sec
    if rate < 1024:
        return f"{rate:.0f} B/s"
    elif rate < 1048576:
        return f"{rate / 1024:.0f} KB/s"
    else:
        return f"{rate / 1048576:.1f} MB/s"


# ---------------------------------------------------------------------------
# Core: extract links + click-to-download
# ---------------------------------------------------------------------------

async def extract_links(page):
    """Extract ALL links from the page (no URL filtering)."""
    print("  Extracting links...")
    links = await page.evaluate("""() => {
        const r = [], s = new Set();
        for (const a of document.querySelectorAll('a[href]')) {
            const h = a.href, t = a.textContent.trim();
            if (!h || h === '#' || h.startsWith('javascript:') || s.has(h)) continue;
            s.add(h);
            r.push({href: h, text: t.substring(0, 150)});
        }
        return r;
    }""")
    return links


async def click_download(page, link_info, download_dir, idx, total):
    """Click a link; if it triggers a download, save the file.

    Strategy:
    - Listen for 'download' event (fires when browser starts a download)
    - Listen for 'framenavigated' event (fires when page navigates away)
    - Click the link, wait for either event
    - If download → save file
    - If navigated → go back to original page
    - If timeout → skip (regular link)
    """
    url = link_info["href"]
    text = link_info["text"][:60]

    # Skip obviously non-download links
    parsed = urlparse(url)
    path = parsed.path.rstrip("/")
    if not path or path in ("#", "/"):
        return None
    # Skip social/sharing links
    if any(d in parsed.netloc for d in ["twitter.com", "facebook.com", "linkedin.com", "mailto:"]):
        return None

    # Find the link element
    try:
        link_el = page.locator(f'a[href="{url}"]').first
        if not await link_el.count():
            # Try with full URL
            link_el = page.locator(f'a[href="{link_info["href"]}"]').first
            if not await link_el.count():
                return None
    except Exception:
        return None

    # Check if already downloaded
    # We'll check after we know the filename (from download event)

    # Set up listeners BEFORE clicking
    download_event = asyncio.Event()
    nav_event = asyncio.Event()
    download_obj = [None]  # mutable container for the download object

    def on_download(dl):
        download_obj[0] = dl
        download_event.set()

    def on_nav(frame):
        if frame == page.main_frame:
            nav_event.set()

    page.on("download", on_download)
    page.on("framenavigated", on_nav)

    try:
        # Click the link
        await link_el.click(timeout=5000)

        # Wait for download or navigation (whichever comes first)
        done, _ = await asyncio.wait(
            [
                asyncio.create_task(download_event.wait()),
                asyncio.create_task(nav_event.wait()),
            ],
            timeout=8,
            return_when=asyncio.FIRST_COMPLETED,
        )

        if download_event.is_set():
            dl = download_obj[0]
            fn = dl.suggested_filename or f"file_{idx}"
            fp = download_dir / fn

            # Skip if already exists
            if fp.exists() and fp.stat().st_size > 1000:
                sz = format_size(fp.stat().st_size)
                print(f"    [{idx}/{total}] SKIP {fn}  ({sz})")
                return "skip"

            t0 = time.monotonic()
            await dl.save_as(str(fp))
            elapsed = time.monotonic() - t0
            size = fp.stat().st_size
            rate = format_rate(size, elapsed)
            print(f"    [{idx}/{total}] {fn}  OK  {format_size(size)}  ({rate}, {elapsed:.1f}s)")
            return "ok"

        elif nav_event.is_set():
            # Page navigated away — go back
            await page.go_back(timeout=10000, wait_until="domcontentloaded")
            await asyncio.sleep(1)
            return "nav"

        else:
            # Timeout — not a download link
            return "skip"

    except Exception:
        return None
    finally:
        page.remove_listener("download", on_download)
        page.remove_listener("framenavigated", on_nav)


async def process_links(page, links, download_dir):
    """Process all links: click each, capture downloads."""
    print(f"\n  Downloading to: {download_dir}\n")
    download_dir.mkdir(parents=True, exist_ok=True)

    ok, fail, skipped = 0, 0, 0
    total = len(links)

    for i, item in enumerate(links, 1):
        result = await click_download(page, item, download_dir, i, total)
        if result == "ok":
            ok += 1
        elif result == "skip":
            skipped += 1
        elif result == "nav":
            # Navigated — link was a page link, not a download
            skipped += 1
        else:
            fail += 1

    return ok, fail, skipped


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main():
    args = parse_args()
    download_dir = Path(args.output) if args.output else Path.cwd() / "downloads"

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=args.headless)
        page = await browser.new_page()

        # Login
        await wait_for_login(page, args.url, skip=args.no_login)
        await asyncio.sleep(2)

        # Make sure we're on the target page (login may have redirected us)
        current_url = page.url
        target_path = urlparse(args.url).path
        if target_path and target_path not in current_url:
            print("  Navigating to target page...")
            await page.goto(args.url, wait_until="networkidle", timeout=60000)
        await asyncio.sleep(2)

        # Scroll to load lazy content
        print("  Scrolling page to load all content...")
        for _ in range(20):
            await page.evaluate("window.scrollBy(0, 1000)")
            await asyncio.sleep(0.3)
        # Scroll back to top
        await page.evaluate("window.scrollTo(0, 0)")
        await asyncio.sleep(1)

        # Extract ALL links
        links = await extract_links(page)
        print(f"\n  Found {len(links)} links on page:\n")
        for i, item in enumerate(links, 1):
            print(f"    {i:2d}. {item['text'][:70]}")
        print()

        if not links:
            print("  No links found. Exiting.")
            await browser.close()
            return

        # Download: click each link, capture downloads
        ok, fail, skipped = await process_links(page, links, download_dir)

        await browser.close()
        print(f"\n{'=' * 50}")
        print(f"  Done! Downloaded: {ok}  Skipped: {skipped}  Failed: {fail}")
        print(f"  Directory: {download_dir}")
        print(f"{'=' * 50}\n")


if __name__ == "__main__":
    asyncio.run(main())
