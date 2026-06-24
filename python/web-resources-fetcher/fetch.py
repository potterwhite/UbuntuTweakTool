#!/usr/bin/env python3
"""
Web Resources Fetcher
- 弹出浏览器让你登录（如果站点需要）
- 自动检测登录状态
- 提取页面中所有下载链接并逐个下载

用法: python3 fetch.py <url> [--output <dir>] [--headless] [--no-login]
"""
import argparse
import asyncio
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

from playwright.async_api import async_playwright


def parse_args():
    parser = argparse.ArgumentParser(
        description="Web Resources Fetcher - 从网页提取并下载所有资源",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
示例:
  %(prog)s https://developer.nvidia.com/embedded/downloads#?search=orin%%20nx
  %(prog)s https://example.com/downloads --output ~/my-downloads
  %(prog)s https://example.com/files --headless --no-login
        """,
    )
    parser.add_argument("url", help="要抓取的网页 URL")
    parser.add_argument(
        "-o", "--output",
        default=None,
        help="下载目录（默认: ./downloads）",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="无头模式运行浏览器（不显示窗口）",
    )
    parser.add_argument(
        "--no-login",
        action="store_true",
        help="跳过登录等待，直接开始抓取",
    )
    return parser.parse_args()


async def wait_for_login(page, timeout_sec=300, skip=False):
    """等待用户登录，通过 URL 变化或页面内容检测"""
    if skip:
        print("  跳过登录检测")
        return True

    print("\n" + "=" * 50)
    print("  浏览器已打开，请登录账号")
    print("  脚本会自动检测登录状态，不用操作终端")
    print("=" * 50 + "\n")

    await page.goto("https://developer.nvidia.com/login")

    for i in range(timeout_sec):
        try:
            url = page.url
            # 方法1: URL 离开登录页
            if "/login" not in url.lower() and "accounts.nvidia.com" not in url.lower():
                print(f"\n  ✓ 登录成功！(跳转到: {url[:60]})\n")
                return True
            # 方法2: 页面内容包含登录标志
            has_session = await page.evaluate("""() => {
                const t = (document.body.innerText || '').toLowerCase();
                return t.includes('sign out') || t.includes('log out') ||
                       t.includes('my account') || t.includes('dashboard') ||
                       t.includes('welcome');
            }""")
            if has_session:
                print(f"\n  ✓ 登录成功！\n")
                return True
        except Exception:
            pass
        if i % 5 == 0:
            sys.stdout.write(f"\r  等待登录... {i}秒")
            sys.stdout.flush()
        await asyncio.sleep(1)

    print("\n  ⚠ 超时，继续尝试下载...\n")
    return False


async def extract_links(page):
    """从当前页面提取所有下载链接"""
    print("  提取链接...")
    links = await page.evaluate("""() => {
        const r = [], s = new Set();
        for (const a of document.querySelectorAll('a[href]')) {
            const h = a.href, t = a.textContent.trim();
            if (!h || h === '#' || h.startsWith('javascript:') || s.has(h)) continue;
            s.add(h);
            if (h.includes('developer.nvidia.com/downloads') || h.includes('/release/') ||
                /\\.(tbz2|deb|zip|tar|gz|pdf|img|bin|run|sh|xlsx|exe|msi|dmg|iso)$/i.test(h))
                r.push({href: h, text: t.substring(0, 150)});
        }
        return r;
    }""")

    seen, final = set(), []
    for item in links:
        h = item["href"]
        if h.startswith("/"):
            h = f"https://developer.nvidia.com{h}"
        if h not in seen and h.startswith("http"):
            seen.add(h)
            item["href"] = h
            final.append(item)

    skip_patterns = [
        "/embedded/downloads#",
        "/embedded/downloads/archive",
        "/embedded/community",
        "/embedded/faq",
    ]
    final = [l for l in final if not any(p in l["href"] for p in skip_patterns)]
    return final


async def download_files(page, links, download_dir):
    """逐个下载文件"""
    print(f"\n  开始下载到: {download_dir}\n")
    download_dir.mkdir(parents=True, exist_ok=True)

    ok, fail = 0, 0
    for i, item in enumerate(links, 1):
        url = item["href"]
        fn = os.path.basename(urlparse(url).path).rstrip("/") or f"file_{i}"
        fp = download_dir / fn

        if fp.exists() and fp.stat().st_size > 20000:
            print(f"    [{i}/{len(links)}] SKIP {fn}")
            ok += 1
            continue

        print(f"    [{i}/{len(links)}] {fn} ... ", end="", flush=True)
        try:
            resp = await page.request.get(url, timeout=300000)
            if resp.ok:
                body = await resp.body()
                if len(body) < 15000 and b"<!DOCTYPE html" in body[:500]:
                    print("✗ 需要登录")
                    fail += 1
                else:
                    fp.write_bytes(body)
                    print(f"✓ {len(body) / 1048576:.1f} MB")
                    ok += 1
            else:
                print(f"✗ HTTP {resp.status}")
                fail += 1
        except Exception as e:
            print(f"✗ {e}")
            fail += 1

    return ok, fail


async def main():
    args = parse_args()
    download_dir = Path(args.output) if args.output else Path.cwd() / "downloads"

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=args.headless)
        page = await browser.new_page()

        # 登录
        await wait_for_login(page, skip=args.no_login)
        await asyncio.sleep(2)

        # 打开目标页面
        print(f"  打开页面: {args.url}")
        await page.goto(args.url, wait_until="networkidle", timeout=60000)
        await asyncio.sleep(2)
        for _ in range(5):
            await page.evaluate("window.scrollBy(0, 1000)")
            await asyncio.sleep(0.3)

        # 提取链接
        links = await extract_links(page)
        print(f"\n  找到 {len(links)} 个下载链接:\n")
        for i, item in enumerate(links, 1):
            print(f"    {i:2d}. {item['text'][:70]}")
        print()

        if not links:
            print("  没有找到下载链接，退出。")
            await browser.close()
            return

        # 下载
        ok, fail = await download_files(page, links, download_dir)

        await browser.close()
        print(f"\n{'=' * 50}")
        print(f"  完成! 成功:{ok}  失败:{fail}")
        print(f"  目录: {download_dir}")
        print(f"{'=' * 50}\n")


if __name__ == "__main__":
    asyncio.run(main())
