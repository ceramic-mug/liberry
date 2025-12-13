import re

books = [
"Jane Eyre – Charlotte Brontë (1847)",
"Little Women – Louisa May Alcott (1868)",
"The Art of War – Sun Tzu (5th Century BC)",
"Dracula – Bram Stoker (1897)",
"The Picture of Dorian Gray – Oscar Wilde (1890)",
"Frankenstein – Mary Shelley (1818)",
"Pride and Prejudice – Jane Austen (1813)",
"The Adventures of Huckleberry Finn – Mark Twain (1884)",
"Crime and Punishment – Fyodor Dostoyevsky (1866)",
"War and Peace – Leo Tolstoy (1869)",
"The Count of Monte Cristo – Alexandre Dumas (1844)",
"A Christmas Carol – Charles Dickens (1843)",
"The Odyssey – Homer (c. 8th Century BC)",
"The Time Machine – H.G. Wells (1895)",
"Moby-Dick – Herman Melville (1851)",
"Don Quixote – Miguel de Cervantes (1605)",
"The Secret Garden – Frances Hodgson Burnett (1911)",
"The Wonderful Wizard of Oz – L. Frank Baum (1900)",
"Wuthering Heights – Emily Brontë (1847)",
"Treasure Island – Robert Louis Stevenson (1883)",
"A Tale of Two Cities – Charles Dickens (1859)",
"David Copperfield – Charles Dickens (1850)",
"The Iliad – Homer (c. 8th Century BC)",
"Great Expectations – Charles Dickens (1861)",
"Anna Karenina – Leo Tolstoy (1878)",
"Les Misérables – Victor Hugo (1862)",
"Anne of Green Gables – L. M. Montgomery (1908)",
"The Strange Case of Dr. Jekyll and Mr. Hyde – Robert Louis Stevenson (1886)",
"Oliver Twist – Charles Dickens (1838)",
"Journey to the Center of the Earth – Jules Verne (1864)",
"The Scarlet Letter – Nathaniel Hawthorne (1850)",
"Persuasion – Jane Austen (1818)",
"The Adventures of Tom Sawyer – Mark Twain (1876)",
"The Brothers Karamazov – Fyodor Dostoevsky (1880)",
"Hamlet – William Shakespeare (1603)",
"The Importance of Being Earnest – Oscar Wilde (1895)",
"20,000 Leagues Under the Sea – Jules Verne (1870)",
"The Three Musketeers – Alexandre Dumas (1844)",
"Sense and Sensibility – Jane Austen (1811)",
"The Invisible Man – H. G. Wells (1897)",
"The Metamorphosis – Franz Kafka (1915)",
"The War of the Worlds – H. G. Wells (1898)",
"A Study in Scarlet – Arthur Conan Doyle (1887)",
"The Wind in the Willows – Kenneth Grahame (1908)",
"Peter Pan – J. M. Barrie (1911)",
"The Hound of the Baskervilles – Sir Arthur Conan Doyle (1902)",
"The Adventures of Sherlock Holmes – Sir Arthur Conan Doyle (1892)",
"Emma – Jane Austen (1815)",
"Alice's Adventures in Wonderland – Lewis Carroll (1865)",
"Walden – Henry David Thoreau (1854)",
"The Woman in White – Wilkie Collins (1860)",
"Alice's Adventures in Wonderland & Through the Looking-Glass – Lewis Carroll (1865 / 1871)",
"Mansfield Park – Jane Austen (1814)",
"The Great Gatsby – Francis Scott Fitzgerald (1925)",
"Uncle Tom's Cabin – Harriet Beecher Stowe (1852)",
"Gulliver's Travels – Jonathan Swift (1726)",
"The Island of Doctor Moreau – H. G. Wells (1896)",
"Flatland – Edwin A. Abbott (1884)",
"Northanger Abbey – Jane Austen (1818)",
"Romeo and Juliet – William Shakespeare (1597)",
"The Phantom of the Opera – Gaston Leroux (1910)",
"Candide – Voltaire (1759)",
"The Divine Comedy – Dante Alighieri (c. 1320)",
"The Prince – Niccolo Machiavelli (1532)",
"The Wealth of Nations – Adam Smith (1776)",
"Around the World in Eighty Days – Jules Verne (1873)",
"Macbeth – William Shakespeare (1623)",
"The Scarlet Pimpernel – Baroness Orczy (1905)",
"The Jungle Books – Rudyard Kipling (1894)",
"North and South – Elizabeth Cleghorn Gaskell (1855)",
"A Little Princess – Frances Hodgson Burnett (1905)",
"Heart of Darkness – Joseph Conrad (1899)",
"The Autobiography of Benjamin Franklin – Benjamin Franklin (1791)",
"The Call of the Wild – Jack London (1903)",
"The Complete Grimm's Fairy Tales – Brothers Grimm (1812)",
"The Hunchback of Notre-Dame – Victor Hugo (1831)",
"The Lost World – Arthur Conan Doyle (1912)",
"The Origin of Species – Charles Darwin (1859)",
"Alice in Wonderland – Lewis Carroll (1865)",
"Paradise Lost – John Milton (1667)",
"Bleak House – Charles Dickens (1853)",
"White Fang – Jack London (1906)",
"Through the Looking-Glass – Lewis Carroll (1871)",
"The Sign of Four – Sir Arthur Conan Doyle (1890)",
"Middlemarch – George Eliot (1871)",
"A Princess of Mars – Edgar Rice Burroughs (1912)",
"The Elements of Style – William Strunk Jr. (1918)",
"Tess of the D'Urbervilles – Thomas Hardy (1891)",
"The Moonstone – Wilkie Collins (1868)",
"Robinson Crusoe – Daniel Defoe (1719)",
"The Republic – Plato (c. 375 BC)",
"The Idiot – Fyodor Dostoevsky (1869)",
"Leaves of Grass – Walt Whitman (1855)",
"Nicholas Nickleby – Charles Dickens (1839)",
"The Canterbury Tales – Geoffrey Chaucer (c. 1400)",
"Devils – Fyodor Dostoevsky (1871)",
"Beowulf – Seamus Heaney (Trans.) (c. 700–1000 AD)",
"Aesop's Fables – Aesop (c. 6th Century BC)",
"Ivanhoe – Sir Walter Scott (1819)",
"Othello – William Shakespeare (1622)"
]

# Step 1: Remove erroneous Alices
# "Alice in Wonderland" is a duplicate title for "Alice's Adventures in Wonderland"
# "Alice's Adventures in Wonderland & Through the Looking-Glass" is a combined duplicate
cleaned_books = [
    b for b in books 
    if b != "Alice in Wonderland – Lewis Carroll (1865)" 
    and b != "Alice's Adventures in Wonderland & Through the Looking-Glass – Lewis Carroll (1865 / 1871)"
]

# Step 2: Add missing books
# Based on Project Gutenberg popularity
missing_books = [
    "The Yellow Wallpaper – Charlotte Perkins Gilman (1892)",
    "A Modest Proposal – Jonathan Swift (1729)"
]
cleaned_books.extend(missing_books)

def parse_year(item):
    # Extract year string - find ALL parentheticals and take the last one that looks like a date
    matches = re.findall(r'\((.*?)\)', item)
    if not matches:
        return 9999
    
    # Iterate backwards to find one with a digit
    date_str = ""
    for m in reversed(matches):
        if re.search(r'\d', m):
            date_str = m
            break
            
    if not date_str:
        return 9999
    
    # Handle BC dates
    if 'BC' in date_str:
        # Extract number
        num = re.search(r'\d+', date_str)
        if num:
            # Century to year approximation (8th Century BC -> -750 approx, but for sorting just -800)
            if 'Century' in date_str:
                return -int(num.group(0)) * 100
            else:
                return -int(num.group(0))
    
    # Handle AD/Normal dates
    # Handle "c. 1400"
    # Handle "1865 / 1871" -> 1865
    date_str = date_str.split('/')[0]
    nums = re.findall(r'\d+', date_str)
    
    if 'Century' in date_str and not 'BC' in date_str:
        # c. 20th Century -> 1900
         if nums:
             return (int(nums[0]) - 1) * 100

    if nums:
        # Last number usually? Or first? "c. 700-1000 AD" -> 700
        return int(nums[0])
        
    return 9999

# Sort
sorted_books = sorted(cleaned_books, key=parse_year)

for b in sorted_books:
    print(b)

print(f"\nTotal: {len(sorted_books)}")
