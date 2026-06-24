#!/usr/bin/env python3
"""
Web Resources Fetcher
- Opens a browser for login if the site requires authentication
- Auto-detects login status
- Extracts all download links from the page and downloads them

Usage: python3 fetch.py <url> [--output <dir>] [--headless] [--no-login]
"""
import argparse
import asyncio
import os
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

from playwright.async_api import async_playwright


def parse_args():
    parser = argparse.ArgumentParser(
        description="Web Resources Fetcher - extract and download all resources from a web page",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples:
  %(prog)s https://example.com/downloads
  %(prog)s https://example.com/downloads --output ~/my-downloads
  %(prog)s https://example.com/files --headless --no-login
        """,
    )
    parser.add_argument("url", help="Target web page URL")
    parser.add_argument(
        "-o", "--output",
        default=None,
        help="Download directory (default: ./downloads)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run browser in headless mode (no window)",
    )
    parser.add_argument(
        "--no-login",
        action="store_true",
        help="Skip login detection, scrape directly",
    )
    return parser.parse_args()


async def wait_for_login(page, target_url, timeout_sec=300, skip=False):
    """Wait for user to log in. Detects via URL change or page content."""
    if skip:
        print("  Skipping login detection")
        return True

    print("\n" + "=" * 50)
    print("  Browser is open. Please log in if required.")
    print("  Auto-detecting login status...")
    print("=" * 50 + "\n")

    # Navigate to the target URL; if it redirects to a login page, wait there
    await page.goto(target_url, wait_until="domcontentloaded", timeout=30000)
    await asyncio.sleep(2)

    # Check if we're already on the target page (no login needed)
    current = page.url
    login_indicators = ["/login", "/signin", "/sign-in", "/auth", "accounts."]
    if not any(ind in current.lower() for ind in login_indicators):
        print(f"  Page loaded directly, no login required.\n")
        return True

    # We're on a login page — wait for redirect back to target
    for i in range(timeout_sec):
        try:
            url = page.url
            if not any(ind in url.lower() for ind in login_indicators):
                print(f"\n  Login successful! (redirected to: {url[:60]})\n")
                return True
            # Also check page content for login indicators
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


async def extract_links(page, base_url):
    """Extract all download links from the current page."""
    print("  Extracting links...")
    links = await page.evaluate("""() => {
        const r = [], s = new Set();
        for (const a of document.querySelectorAll('a[href]')) {
            const h = a.href, t = a.textContent.trim();
            if (!h || h === '#' || h.startsWith('javascript:') || s.has(h)) continue;
            s.add(h);
            if (/\\.(tbz2|deb|zip|tar|gz|pdf|img|bin|run|sh|xlsx|exe|msi|dmg|iso)$/i.test(h) ||
                h.includes('/downloads') || h.includes('/release/'))
                r.push({href: h, text: t.substring(0, 150)});
        }
        return r;
    }""")

    base_domain = f"{urlparse(base_url).scheme}://{urlparse(base_url).netloc}"
    seen, final = set(), []
    for item in links:
        h = item["href"]
        if h.startswith("/"):
            h = f"{base_domain}{h}"
        if h not in seen and h.startswith("http"):
            seen.add(h)
            item["href"] = h
            final.append(item)

    # Filter out navigation links
    skip_suffixes = ["#", "/archive", "/community", "/faq"]
    final = [l for l in final if not any(l["href"].rstrip("/").endswith(p) for p in skip_suffixes)]
    return final


def format_size(size_bytes):
    """Format bytes to human-readable string."""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1048576:
        return f"{size_bytes / 1024:.0f} KB"
    elif size_bytes < 1073741824:
        return f"{size_bytes / 1048576:.1f} MB"
    else:
        return f"{size_bytes / 1073741824:.2f} GB"


def format_rate(bytes_count, elapsed_sec):
    """Format download rate."""
    if elapsed_sec <= 0:
        return ""
    rate = bytes_count / elapsed_sec
    if rate < 1024:
        return f"{rate:.0f} B/s"
    elif rate < 1048576:
        return f"{rate / 1024:.0f} KB/s"
    else:
        return f"{rate / 1048576:.1f} MB/s"


async def download_files(page, links, download_dir):
    """Download files one by one with size and rate display."""
    print(f"\n  Downloading to: {download_dir}\n")
    download_dir.mkdir(parents=True, exist_ok=True)

    ok, fail = 0, 0
    for i, item in enumerate(links, 1):
        url = item["href"]
        fn = os.path.basename(urlparse(url).path).rstrip("/") or f"file_{i}"
        fp = download_dir / fn

        # Skip if already downloaded (>20KB)
        if fp.exists() and fp.stat().st_size > 20000:
            print(f"    [{i}/{len(links)}] SKIP {fn}")
            ok += 1
            continue

        print(f"    [{i}/{len(links)}] {fn} ... ", end="", flush=True)
        try:
            resp = await page.request.get(url, timeout=300000)
            if resp.ok:
                t0 = time.monotonic()
                body = await resp.body()
                elapsed = time.monotonic() - t0

                if len(body) < 15000 and b"<!DOCTYPE html" in body[:500]:
                    print("FAILED (login required)")
                    fail += 1
                else:
                    fp.write_bytes(body)
                    rate = format_rate(len(body), elapsed)
                    print(f"OK  {format_size(len(body))}  ({rate}, {elapsed:.1f}s)")
                    ok += 1
            else:
                print(f"FAILED (HTTP {resp.status})")
                fail += 1
        except Exception as e:
            print(f"FAILED ({e})")
            fail += 1

    return ok, fail


async def main():
    args = parse_args()
    download_dir = Path(args.output) if args.output else Path.cwd() / "downloads"

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=args.headless)
        page = await browser.new_page()

        # Login
        await wait_for_login(page, args.url, skip=args.no_login)
        await asyncio.sleep(2)

        # Open target page (in case login redirected us away)
        current_url = page.url
        target_path = urlparse(args.url).path
        if target_path and target_path not in current_url:
            print(f"  Navigating to target page...")
            await page.goto(args.url, wait_until="networkidle", timeout=60000)
        await asyncio.sleep(2)
        for _ in range(5):
            await page.evaluate("window.scrollBy(0, 1000)")
            await asyncio.sleep(0.3)

        # Extract links
        links = await extract_links(page, args.url)
        print(f"\n  Found {len(links)} download links:\n")
        for i, item in enumerate(links, 1):
            print(f"    {i:2d}. {item['text'][:70]}")
        print()

        if not links:
            print("  No download links found. Exiting.")
            await browser.close()
            return

        # Download
        ok, fail = await download_files(page, links, download_dir)

        await browser.close()
        print(f"\n{'=' * 50}")
        print(f"  Done! Success: {ok}  Failed: {fail}")
        print(f"  Directory: {download_dir}")
        print(f"{'=' * 50}\n")


if __name__ == "__main__":
    asyncio.run(main())
