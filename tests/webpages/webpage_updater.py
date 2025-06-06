#!/usr/bin/python3

"""Script for downloading latest HTML pagesource"""

import os
import urllib.request
import time
import re
from fp.fp import FreeProxy

IMDB_MOVIE_IDS = ["tt0375568", "tt11095742",
                  "tt7214470", "tt7728344", "tt0455275", "tt3450958", "tt0382625",
                  "tt4919664", "tt2487090", "tt3876702", "tt0107144", "tt0816352",
                  "tt5667286", "tt2372220"]
BOM_MOVIE_IDS = ["tt0375568", "tt5093026", "tt3450958", "tt0087332", "tt7167658"]
BOM_RELEASES = [{"ID": "tt0375568", "Country": "USA", "Link": "/release/rl3947005441"},
                {"ID": "tt5093026", "Country": "France",
                    "Link": "/release/rl4152788737"},
                {"ID": "tt3450958", "Country": "Germany",
                    "Link": "/release/rl1965786625"},
                # special case with several re-releases
                {"ID": "tt0087332", "Country": "Original Release",
                    "Link": "/releasegroup/gr2193641989"},
                {"ID": "tt0087332", "Country": "USA", "Link": "/release/rl3663037953"},
                # special case with two original releases for different countries but none is useful
                {"ID": "tt7167658", "Country": "Original Release",
                    "Link": "/releasegroup/gr1831424517"}]

proxy = None

def __save_to_file(filename, content):
    """Save given content to filename (overwrites existing file)
    Args
        filename: filename
        content: html sourcecode
    """
    filename = filename.replace("–", "-")
    filename = filename.replace(":", "")
    filename = filename.replace("ä", "ae")
    # replace html escaped code
    filename = filename.replace("&quot;", "")
    filename = filename.replace("&amp;", "&")
    # files with slash can't be saved to disk
    filename = filename.replace("/", "-")
    print("filename " + filename)
    f = open(filename, "w", encoding='utf-8')
    f.write(content)
    f.close()


def get_latest_pagesource(url) -> str:
    """Get latest pagesource for given URL
    Args
        url: link to web content
    """
    RETRY_TIME = 2
    # find US proxy to avoid site changes due to different locations of developers
    global proxy
    if not proxy:
        proxy = FreeProxy(country_id=['US']).get()
        if not proxy:
            raise Exception("Impossible to find a free US proxy!")
        print("using proxy " + proxy)
    # set proxy for urllib
    proxy_handler = urllib.request.ProxyHandler({'http': proxy})
    opener = urllib.request.build_opener(proxy_handler)
    urllib.request.install_opener(opener)
    while True:
        # try to fetch website
        try:
            req = urllib.request.Request(url, headers={
                                        'User-Agent': ' Mozilla/5.0 (Windows NT 6.1; WOW64; rv:87.0) Gecko/20100101 Firefox/87.0', "Accept-Language": "en-US,en;q=0.5"})
            content = urllib.request.urlopen(req).read().decode('utf-8')
            break
        except urllib.request.HTTPError:
            time.sleep(RETRY_TIME)
            pass
    return content


def findWebpageTitle(content) -> str:
    """Extracts the webpage title from the given html page
    Args
        content: html sourcecode
    """
    match = re.search(r"<title.*?>(.*?)<\/title>", content)
    if match:
        title = match.group(1)
    else:
        raise Exception("Impossible to find title!")
    return title


def findOriginalMovieTitle(content) -> str:
    """Extracts the original title from the given html page
    Args
        content: html sourcecode
    """
    # imdb uses location dependent titles -> use fallback to original title
    match = re.search(
        r"<meta property=\"og:title\" content=\"(.*?)\"/>", content)
    if match:
        title = match.group(1)
    else:
        raise Exception("Impossible to find title!")

    # just keep the old file names without the ratings in the webpage title
    title = title.split("⭐")[0].split("|")[0] + "- IMDb"
    return title


def save_pagesource_to_file(content, title, extrainfo='') -> None:
    """Save given pagesource with defined filename
    Args
        content: html sourcecode
        title: title of the html page
        extrainfo: info which is appended to title and used as filename
    """
    if extrainfo == '':
        filename = title + ".html"
    else:
        filename = title + "--" + extrainfo + ".html"
    __save_to_file(filename, content)
    print("Updated " + title)


current_dir = os.getcwd()
if not current_dir.endswith("webpages"):
    print("Script can only be executed from webpages folder!")
    exit()

print("Getting latest pagesource for all files:")
print("\tIMDb")
for id in IMDB_MOVIE_IDS:
    print("_" + id + "_")
    htmlcode = get_latest_pagesource("https://www.imdb.com/title/" + id + "/")
    origtitle = findOriginalMovieTitle(htmlcode)
    save_pagesource_to_file(htmlcode, origtitle)
    htmlcode = get_latest_pagesource(
        "https://www.imdb.com/title/" + id + "/releaseinfo")
    title = findWebpageTitle(htmlcode)
    first_word_origtitle = origtitle.split()[0]
    if not title.startswith(first_word_origtitle):
        raise Exception("Title mismatch between overview and release page! Title: " + title + " First word orig title: " + first_word_origtitle)
    save_pagesource_to_file(htmlcode, title)

print("\tBox Office Mojo")
for id in BOM_MOVIE_IDS:
    htmlcode = get_latest_pagesource(
        "https://www.boxofficemojo.com/title/" + id + "/")
    title = findWebpageTitle(htmlcode)
    save_pagesource_to_file(htmlcode, title)

print("\tBox Office Mojo Releases")
for item in BOM_RELEASES:
    htmlcode = get_latest_pagesource(
        "https://www.boxofficemojo.com/title/" + item["ID"] + "/")
    if item["Country"] == 'USA':
        website_country = "Domestic"
    else:
        website_country = item["Country"]

    if website_country != 'Original Release':
        regex = r'<a class="a-link-normal" href="(\/release\/rl\d+).*?">(.*?)<\/a>'
    else:
        regex = r'<a class="a-link-normal" href="(\/releasegroup\/gr\d+).*?">(.*?)<\/a>'

    match = re.findall(regex, htmlcode)
    if match:
        for url, name in match:
            if name == website_country:
                weblink = url
                break
    else:
        raise Exception("Impossible to find Release URL!")
    if weblink != item["Link"]:
        raise Exception("Release URL links have changed! Expected: {0} Actual: {1}".format(item["Link"], weblink))
    htmlcode = get_latest_pagesource(
        "https://www.boxofficemojo.com" + item["Link"] + "/")
    title = findWebpageTitle(htmlcode)
    save_pagesource_to_file(htmlcode, title, item["Country"])

print("done.")
