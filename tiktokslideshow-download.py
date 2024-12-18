import argparse
import itertools
import json
import re
from pathlib import Path

import requests
import yt_dlp
from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service as ChromeService
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait
from webdriver_manager.chrome import ChromeDriverManager


# TODO: auto load cookies from browser files
# Load cookies into the browser
def load_cookies(driver, file_path: str):
    cookies = json.loads(Path(file_path).read_text())
    for cookie in cookies:
        driver.add_cookie(
            {
                "name": cookie["name"],
                "value": cookie["value"],
                "domain": cookie["domain"],
            }
        )


# TODO: figure out how to convert json cookies to netscape cookies
def json_to_netscape(json_file):
    """
    Converts a JSON cookies file to Netscape format.

    :param json_file: Path to the input JSON cookies file.
    """
    # Get the base name and change the extension to .txt
    json_path = Path(json_file)
    netscape_file = json_path.with_suffix(".txt")

    if netscape_file.exists():
        print("Netscape cookies found.")
        return netscape_file

    try:
        with open(json_file, "r") as file:
            cookies = json.load(file)

        with open(netscape_file, "w") as file:
            # Write the netscape header
            file.write("# Netscape HTTP Cookie File\n")
            file.write("# This file is generated by a script\n\n")

            for cookie in cookies:
                # Extract fields
                domain: str = cookie.get("domain", "")
                flag = "TRUE" if domain.startswith(".") else "FALSE"
                path: str = cookie.get("path", "/")
                secure = "TRUE" if cookie.get("secure", False) else "FALSE"
                expiry = int(cookie.get("expirationDate", "0"))
                name: str = cookie.get("name", "")
                value = cookie.get("value", "")

                # Write to Netscape format
                file.write(
                    f"{domain}\t{flag}\t{path}\t{secure}\t{expiry}\t{name}\t{value}\n"
                )

        return netscape_file
    except Exception as e:
        print(f"Error converting cookies: {e}")


# Fetch the TikTok page
def fetch_page(url: str, file_path: str):
    options = Options()
    options.add_argument("--headless")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("start-maximized")
    options.add_argument("enable-automation")
    options.add_argument("--disable-blink-features=AutomationControlled")

    # Set up WebDriver Manager
    driver = webdriver.Chrome(
        options=options, service=ChromeService()
    )
    driver.get("https://www.tiktok.com/")

    # Load cookies
    load_cookies(driver, file_path)
    driver.refresh()

    # Navigate to the target URL
    driver.get(url)

    try:
        # Wait for the page to load completely
        WebDriverWait(driver, 10).until(
            EC.presence_of_element_located(
                (By.CSS_SELECTOR, ".css-brxox6-ImgPhotoSlide.e10jea832")
            )
        )
        return driver.page_source
    except Exception as e:
        print(f"Failed to fetch the page: {e}")
        return None
    finally:
        driver.quit()


# Parse image links from the slideshow
def parse_slideshow_links(html):
    soup = BeautifulSoup(html, "html.parser")
    image_tags = soup.select(".css-brxox6-ImgPhotoSlide.e10jea832")
    image_links = [img["src"] for img in image_tags if "src" in img.attrs]

    # Flatten any nested lists
    flat_image_links = list(
        itertools.chain(
            *[
                sublist if isinstance(sublist, list) else [sublist]
                for sublist in image_links
            ]
        )
    )
    return flat_image_links

# Parse image links from the slideshow
def parse_slideshow_links_with_index(html):
    soup = BeautifulSoup(html, "html.parser")
    image_tags = soup.select(".css-brxox6-ImgPhotoSlide.e10jea832")
    image_links = [(img["src"],img.parent["data-swiper-slide-index"] ) for img in image_tags if "src" in img.attrs and img.parent]

    # Flatten any nested lists
    flat_image_links = list(
        itertools.chain(
            *[
                sublist if isinstance(sublist, list) else [sublist]
                for sublist in image_links
            ]
        )
    )

    # dedup list so each entry is only downloaded once
    flat_image_links: list[tuple[str,int]] = list(dict.fromkeys(flat_image_links))
    return flat_image_links


# Download images
def download_images(image_links: list[str], output_dir):
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)

    for link in image_links:
        try:
            response = requests.get(link, stream=True)
            response.raise_for_status()
            file_name = link.split("/")[-1].split("?")[0]
            file_path = output_dir / file_name
            with file_path.open("wb") as file:
                for chunk in response.iter_content(chunk_size=8192):
                    file.write(chunk)
            print(f"Downloaded: {file_name}")
        except requests.RequestException as e:
            print(f"Failed to download {link}: {e}")

# Download images
def download_images_with_index(video_id, image_links: list[tuple[str,int]], output_dir):
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)

    for (link,index) in image_links:
        try:
            response = requests.get(link, stream=True)
            response.raise_for_status()
            file_name = f"[{video_id}]-{index}-" + link.split("/")[-1].split("?")[0]
            file_path = output_dir / file_name
            with file_path.open("wb") as file:
                for chunk in response.iter_content(chunk_size=8192):
                    file.write(chunk)
            print(f"Downloaded: {file_name}")
        except requests.RequestException as e:
            print(f"Failed to download {link}: {e}")

# Detect content type using regex
def is_slideshow(url: str):
    return "photo" in url


# Download a TikTok video
# TODO: error handling in case it's a priv video? tell user to retry specifying cookies
def download_video(video_id, url, output_dir, cookies_file):
    """
    Downloads a TikTok video using yt-dlp, with support for cookies.

    :param video_id: The video ID to download.
    :param url: The URL of the TikTok video.
    :param output_dir: Directory to save the downloaded video.
    :param cookies_file: Path to the cookies JSON file.
    """
    netscape_cookies = json_to_netscape(cookies_file)

    ydl_opts = {
        "outtmpl": f"{output_dir}/[{video_id}]%(title).100B.%(ext)s",  # Save with video title as filename
        "format": "best",  # Specify  format
        "noplaylist": True,  # Single video download
        "quiet": False,  # Verbose output
        "cookiefile": netscape_cookies,  # Use cookies
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])

            print("Video downloaded successfully.")
    except Exception as e:
        print(f"Failed to download video: {e}")

def check_audio_only(url, cookies_file):
    """
    Extracts Tiktok metadata and evaluates if it is audio-only

    audio-only Tiktoks are almost always slideshows with
    /video/ instead of /photo/ in the url

    :param url: The URL of the TikTok video.
    :param cookies_file: Path to the cookies JSON file.
    """
    netscape_cookies = json_to_netscape(cookies_file)

    ydl_opts = {
        "outtmpl": f"/tmp/%(title).100B.%(ext)s",  # Save with video title as filename
        "format": "best",  # Specify  format
        "noplaylist": True,  # Single video download
        "quiet": False,  # Verbose output
        "cookiefile": netscape_cookies,  # Use cookies
        "nodownload":True, # Don't download the video
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            video_metadata = ydl.extract_info(url)
            if video_metadata is None:
                raise RuntimeError("Video has no metadata")

            audio_only = video_metadata["resolution"] == "audio only"

            if audio_only:
                print("Video URL is actually audio only, treating as a slideshow")

            return audio_only

    except Exception as e:
        print(f"Failed to download video metadata: {e}")

def extract_video_id(url):
    """
    Extracts video ID first with a regex or GET request

    Long video URLs which already have the video ID at the end are extracted
    Short URLs (such as those shared externally) need a GET request to resolve the full URL first
    """
    # retrieve the 19 digit video ID, rest is optional
    video_id_pattern = re.compile(r'tiktok\.com/.*/(\d{19})(?:\?.*)?')

    # Attempt to find the video ID in the given URL
    match = video_id_pattern.search(url)

    if not match:
        # there's no match, check if its a tiktok URL and resolve it
        if "tiktok" not in url:
            raise RuntimeError("URL is not a valid TikTok URL")
        resolved_url = requests.get(url).url
        match = video_id_pattern.search(resolved_url)
        if not match:
            raise RuntimeError("Failed to extract video ID from the URL")

    # Return the captured video ID
    return match.group(1)

def main():
    # Parse command-line args
    parser = argparse.ArgumentParser(description="Download TikTok slideshow images.")
    parser.add_argument("link", help="TikTok video link")
    parser.add_argument(
        "--cookies", required=True, help="Path to the cookies file (cookies.json)"
    )
    parser.add_argument(
        "--output", required=True, help="Output folder for downloaded images"
    )
    args = parser.parse_args()

    video_id = extract_video_id(args.link)

    # Decide based on URl content type
    if is_slideshow(args.link) or check_audio_only(args.link, args.cookies):
        print("Detected slideshow. Downloading images...")
        # Load cookies and fetch
        html = fetch_page(args.link, args.cookies)

        if html:
            # Parse and download images
            if image_links := parse_slideshow_links_with_index(html):
                print(f"Found {len(image_links)} images. Downloading...")
                download_images_with_index(video_id,image_links, args.output)
            else:
                print("No images found.")
    elif not is_slideshow(args.link):
        print("Detected video. Downloading video...")

        download_video(video_id, args.link, args.output, args.cookies)
    else:
        print("Link neither a video nor slideshow...")


if __name__ == "__main__":
    main()
