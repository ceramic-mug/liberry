import sqlite3
import tarfile
import xml.etree.ElementTree as ET
import os
import requests
import zipfile
from io import BytesIO
from tqdm import tqdm

# Configuration
DB_NAME = "gutenberg_optimized.db"
RDF_FILENAME = "rdf-files.tar.zip"
RDF_URL = "https://www.gutenberg.org/cache/epub/feeds/rdf-files.tar.zip"
NS = {
    'pg': 'http://www.gutenberg.org/2009/pgterms/',
    'dc': 'http://purl.org/dc/terms/',
    'rdf': 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'
}

def get_text_safe(element):
    return element.text if element is not None else ""

def download_catalog():
    if os.path.exists(RDF_FILENAME) and os.path.getsize(RDF_FILENAME) > 0:
        print(f"File {RDF_FILENAME} already exists. Skipping download.")
        return

    print(f"Downloading RDF catalog from {RDF_URL}...")
    try:
        response = requests.get(RDF_URL, stream=True)
        response.raise_for_status()
        
        total_size = int(response.headers.get('content-length', 0))
        block_size = 1024 # 1 Kibibyte
        
        with open(RDF_FILENAME, 'wb') as file, tqdm(
            desc=RDF_FILENAME,
            total=total_size,
            unit='iB',
            unit_scale=True,
            unit_divisor=1024,
        ) as bar:
            for data in response.iter_content(block_size):
                size = file.write(data)
                bar.update(size)
                
        print("Download complete.")
    except Exception as e:
        print(f"Failed to download RDF catalog: {e}")
        if os.path.exists(RDF_FILENAME):
            os.remove(RDF_FILENAME)
        raise e

def bake_database():
    try:
        download_catalog()
    except Exception:
        return

    # 1. Setup SQLite with FTS5
    if os.path.exists(DB_NAME):
        os.remove(DB_NAME)
    
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    
    # Main table (normalized data)
    c.execute("""
        CREATE TABLE books (
            id INTEGER PRIMARY KEY,
            title TEXT,
            author TEXT
        )
    """)
    
    # FTS5 Virtual Table for lightning-fast search
    # We use external content to save space (points to 'books' table)
    # Note: content='books' means FTS5 won't store copies of the data, it uses the 'books' table.
    c.execute("""
        CREATE VIRTUAL TABLE books_fts USING fts5(
            title, 
            author, 
            content='books', 
            content_rowid='id'
        )
    """)

    print("Parsing and indexing (this takes a few minutes)...")
    count = 0
    batch_data = []
    
    # Process the file (Expect .tar.zip)
    try:
        # 1. Open as Zip from disk
        with zipfile.ZipFile(RDF_FILENAME) as z:
            # Find the .tar file inside
            tar_filename = next((n for n in z.namelist() if n.endswith('.tar')), None)
            
            if not tar_filename:
                print("Error: No .tar file found inside the downloaded zip.")
                return

            print(f"Extracting {tar_filename} stream...")
            
            # 2. Open the inner tar stream
            with z.open(tar_filename) as tar_stream:
                 # mode='r|' allows reading a stream (non-seekable)
                with tarfile.open(fileobj=tar_stream, mode="r|") as tar:
                    for member in tqdm(tar):
                        if not member.name.endswith('.rdf'):
                            continue

                        try:
                            # Extract ID from filename (pg123.rdf -> 123)
                            # Filename format is usually cache/epub/123/pg123.rdf
                            basename = os.path.basename(member.name)
                            if not basename.startswith('pg') or not basename.endswith('.rdf'):
                                continue
                                
                            book_id_str = basename.replace('pg', '').replace('.rdf', '')
                            if not book_id_str.isdigit():
                                continue
                            
                            book_id = int(book_id_str)
                            
                            f = tar.extractfile(member)
                            if f is None:
                                continue
                                
                            content = f.read()
                            try:
                                root = ET.fromstring(content)
                            except ET.ParseError:
                                continue
                            
                            # Filters: English only & Text only
                            lang_node = root.find('.//dc:language//rdf:value', NS)
                            type_node = root.find('.//dc:type//rdf:value', NS)
                            
                            lang = get_text_safe(lang_node)
                            type_ = get_text_safe(type_node)
                            
                            if lang != 'en' or type_ != 'Text':
                                continue

                            title = get_text_safe(root.find('.//dc:title', NS)).replace('\n', ' ')
                            author_node = root.find('.//pg:agent/pg:name', NS)
                            author = get_text_safe(author_node)
                            if not author:
                                author = "Unknown"
                            
                            # Add to batch
                            batch_data.append((book_id, title, author))
                            count += 1
                            
                            # Bulk Insert every 5000 records
                            if len(batch_data) >= 5000:
                                c.executemany("INSERT INTO books (id, title, author) VALUES (?, ?, ?)", batch_data)
                                c.executemany("INSERT INTO books_fts (rowid, title, author) VALUES (?, ?, ?)", batch_data)
                                conn.commit()
                                batch_data = []
                                
                        except Exception as e:
                            # distinct failure for one record shouldn't stop the whole process
                            continue

        # Insert remaining
        if batch_data:
            c.executemany("INSERT INTO books (id, title, author) VALUES (?, ?, ?)", batch_data)
            c.executemany("INSERT INTO books_fts (rowid, title, author) VALUES (?, ?, ?)", batch_data)
            conn.commit()

        # Optimization: Rebuild FTS index for speed
        print("Optimizing FTS index...")
        c.execute("INSERT INTO books_fts(books_fts) VALUES('optimize')")
        conn.commit()
        
        # VACUUM must be run outside of a transaction
        old_isolation = conn.isolation_level
        conn.isolation_level = None
        c.execute("VACUUM")
        conn.isolation_level = old_isolation
        
        conn.close()
        print(f"Done! Database saved to {DB_NAME}")
        print(f"Total books indexed: {count}")
        
    except Exception as e:
        print(f"An error occurred during processing: {e}")
        if conn:
            conn.close()

if __name__ == "__main__":
    bake_database()
