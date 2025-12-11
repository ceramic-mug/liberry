import requests
import xml.etree.ElementTree as ET
import json
import base64
import time
import os
import sys

# Configuration
BASE_URL = "https://standardebooks.org/feeds/opds"
USERNAME = "joshua.h.eastman@gmail.com"
PASSWORD = "IxThYstaE4984"
OUTPUT_FILE = "../assets/standard_ebooks.json"

# Namespaces for parsing Atom/OPDS XML
NS = {
    'atom': 'http://www.w3.org/2005/Atom',
    'opds': 'http://opds-spec.org/2010/catalog',
    'dc': 'http://purl.org/dc/terms/',
    'dcterms': 'http://purl.org/dc/terms/'
}

class StandardEbooksCrawler:
    def __init__(self, username, password):
        self.session = requests.Session()
        self.session.auth = (username, password)
        self.visited = set()
        
    def fetch_feed(self, url):
        if url in self.visited:
            print(f"Already visited: {url}")
            return None
        
        print(f"Fetching: {url}")
        self.visited.add(url)
        
        try:
            response = self.session.get(url, timeout=30)
            if response.status_code != 200:
                print(f"Error fetching {url}: {response.status_code}")
                return None
            return response.content
        except Exception as e:
            print(f"Exception fetching {url}: {e}")
            return None

    def parse_entry(self, entry_elem):
        """Parse a single entry element."""
        title = entry_elem.find('atom:title', NS).text
        
        # Determine entry type
        links = entry_elem.findall('atom:link', NS)
        
        # Check if it's navigation (subsection) or acquisition (book)
        is_acquisition = False
        nav_link = None
        acquisition_link = None
        cover_url = None
        
        for link in links:
            rel = link.get('rel')
            href = link.get('href')
            type_attr = link.get('type')
            
            if rel == 'http://opds-spec.org/acquisition' or rel == 'http://opds-spec.org/acquisition/open-access':
                is_acquisition = True
                if type_attr == 'application/epub+zip':
                    acquisition_link = self.make_full_url(href)
            
            if rel == 'subsection' or (rel == 'alternate' and type_attr == 'application/atom+xml;profile=opds-catalog;kind=navigation'):
                nav_link = self.make_full_url(href)
                
            if rel == 'http://opds-spec.org/image' or rel == 'http://opds-spec.org/image/thumbnail':
                 cover_url = self.make_full_url(href)

        entry_data = {
            'title': title,
            'id': entry_elem.find('atom:id', NS).text
        }

        if is_acquisition and acquisition_link:
            entry_data['type'] = 'acquisition'
            author_tag = entry_elem.find('atom:author/atom:name', NS)
            entry_data['author'] = author_tag.text if author_tag is not None else "Unknown"
            
            summary_tag = entry_elem.find('atom:summary', NS)
            if summary_tag is not None:
                entry_data['summary'] = summary_tag.text
            
            if cover_url:
                entry_data['coverUrl'] = cover_url
            
            entry_data['downloadUrl'] = acquisition_link
            
        elif nav_link:
            entry_data['type'] = 'navigation'
            content_tag = entry_elem.find('atom:content', NS)
            if content_tag is not None:
                entry_data['content'] = content_tag.text
            
            # Recursively crawl
            # Careful with infinite loops or huge trees. 
            # Standard ebooks structure is usually root -> subjects -> [A-Z] -> books
            # or root -> authors -> [A-Z] -> books
            # We want to crawl "subjects" and "authors" specifically.
            
            # Don't crawl "new releases" or "all" recursively if we are already deep, to avoid duplication?
            # Actually, we should just follow the structure.
            
            # Optimization: If the link is just a "next page", handle it? 
            # Standard ebooks usually has pagination. 
            # BUT for offline DB, better to get EVERYTHING.
            
            # For now, let's store the LINK and decide in crawl() whether to recurse.
            entry_data['link'] = nav_link
            
        else:
            # Maybe just a link to html page? Skip
            return None
            
        return entry_data

    def make_full_url(self, href):
        if href.startswith('http'):
            return href
        return f"https://standardebooks.org{href}"

    def crawl(self, start_url, depth=0, max_depth=5):
        if depth > max_depth:
            return None
            
        xml_content = self.fetch_feed(start_url)
        if not xml_content:
            return None
            
        root = ET.fromstring(xml_content)
        title = root.find('atom:title', NS).text
        
        feed_data = {
            'title': title,
            'entries': []
        }
        
        # Handle Pagination - "next" link
        # We need to stitch pages together into one big list for this node if possible, 
        # OR just keep the structure if we want to mimic it.
        # Ideally for offline DB, we flatten pagination if it's just a list of items.
        
        # Let's iterate pages here
        current_xml = xml_content
        page_count = 0
        
        while True:
            root = ET.fromstring(current_xml)
            entries = root.findall('atom:entry', NS)
            
            for entry in entries:
                parsed = self.parse_entry(entry)
                if parsed:
                    if parsed.get('type') == 'navigation':
                        # Recurse!
                        # But be careful of loops or huge paths.
                        # Standard Ebooks: /subjects -> /subjects/adventure -> books
                        print(f"  Recursing into {parsed['title']}...")
                        sub_feed = self.crawl(parsed['link'], depth + 1, max_depth)
                        if sub_feed:
                            # Embed the sub-feed directly if we want a full tree
                            # Or reference it? embedding is easier for a single JSON file.
                            parsed['feed'] = sub_feed
                    
                    feed_data['entries'].append(parsed)
            
            # Check for next link
            next_link = None
            for link in root.findall('atom:link', NS):
                if link.get('rel') == 'next':
                    next_link = self.make_full_url(link.get('href'))
                    break
            
            if next_link:
                print(f"  Fetching next page: {next_link}")
                current_xml = self.fetch_feed(next_link)
                if not current_xml:
                    break
                page_count += 1
                if page_count > 20: # Safety break
                    print("  Max pages reached")
                    break
            else:
                break
                
        return feed_data

    def generate_db(self):
        # We want to generate two main trees: Subjects and Authors.
        db = {
            'subjects': None,
            'authors': None
        }
        
        print("Crawling Subjects...")
        db['subjects'] = self.crawl(f"{BASE_URL}/subjects")
        
        print("Crawling Authors...")
        db['authors'] = self.crawl(f"{BASE_URL}/authors")
        
        return db

if __name__ == "__main__":
    crawler = StandardEbooksCrawler(USERNAME, PASSWORD)
    db = crawler.generate_db()
    
    # Ensure assets dir exists
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(db, f, indent=2)
        
    print(f"Done! Database saved to {OUTPUT_FILE}")
