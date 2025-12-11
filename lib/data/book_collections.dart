import 'package:flutter/material.dart';

class CollectionBook {
  final String title;
  final String author;
  final String source; // e.g. 'SE', 'PG'
  final String? group; // e.g. 'Antebellum', 'Gothic Sci-Fi'
  final Map<String, String>
  metadata; // e.g. {'Translator': '...', 'Critical Focus': '...'}

  const CollectionBook({
    required this.title,
    required this.author,
    required this.source,
    this.group,
    this.metadata = const {},
  });
}

class BookCollection {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<CollectionBook> books;
  final String? groupingLabel; // Label for the group (e.g. 'Era', 'Sub-Genre')

  const BookCollection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.books,
    this.groupingLabel,
  });
}

class BookCollectionsData {
  static final List<BookCollection> collections = [
    // Module I: The Great American Novel (1850–1929)
    BookCollection(
      title: 'The Great American Novel',
      subtitle: 'Module I (1850–1929)',
      icon: Icons.flag,
      color: Colors.indigo,
      groupingLabel: 'Era',
      books: [
        CollectionBook(
          group: 'Antebellum',
          title: 'The Scarlet Letter',
          author: 'Nathaniel Hawthorne',
          source: 'SE',
          metadata: {'Critical Focus': 'Puritanism, Sin, Allegory'},
        ),
        CollectionBook(
          group: 'Antebellum',
          title: 'Moby-Dick',
          author: 'Herman Melville',
          source: 'SE',
          metadata: {'Critical Focus': 'Industry, Obsession, Metaphysics'},
        ),
        CollectionBook(
          group: 'Realism',
          title: 'Adventures of Huckleberry Finn',
          author: 'Mark Twain',
          source: 'SE',
          metadata: {'Critical Focus': 'Race, Vernacular, The Frontier'},
        ),
        CollectionBook(
          group: 'Realism',
          title: 'The Rise of Silas Lapham',
          author: 'William Dean Howells',
          source: 'SE',
          metadata: {'Critical Focus': 'Social Class, Business Ethics'},
        ),
        CollectionBook(
          group: 'Naturalism',
          title: 'The Red Badge of Courage',
          author: 'Stephen Crane',
          source: 'SE',
          metadata: {'Critical Focus': 'War psychology, Impressionism'},
        ),
        CollectionBook(
          group: 'Prairie',
          title: 'My Ántonia',
          author: 'Willa Cather',
          source: 'SE',
          metadata: {'Critical Focus': 'Immigration, The West, Memory'},
        ),
        CollectionBook(
          group: 'Gilded Age',
          title: 'The Age of Innocence',
          author: 'Edith Wharton',
          source: 'SE',
          metadata: {'Critical Focus': 'Old New York, Social Codes'},
        ),
        CollectionBook(
          group: 'Jazz Age',
          title: 'The Great Gatsby',
          author: 'F. Scott Fitzgerald',
          source: 'SE',
          metadata: {'Critical Focus': 'Wealth, The American Dream'},
        ),
        CollectionBook(
          group: 'Modernism',
          title: 'The Sound and the Fury',
          author: 'William Faulkner',
          source: 'SE/PG',
          metadata: {'Critical Focus': 'Stream of Consciousness, Decay'},
        ),
        CollectionBook(
          group: 'Modernism',
          title: 'A Farewell to Arms',
          author: 'Ernest Hemingway',
          source: 'SE',
          metadata: {'Critical Focus': 'War, Nihilism, The "Lost Generation"'},
        ),
      ],
    ),

    // Module II: The Russian Soul — Golden Age Masters (19th Century)
    BookCollection(
      title: 'The Russian Soul',
      subtitle: 'Module II — Golden Age Masters',
      icon: Icons.snowing,
      color: Colors.redAccent,
      groupingLabel:
          null, // No explicit grouping column in valid input apart from author, but let's list them flat or group by Author if needed?
      // The input has 'Author' as a column. Grouping by Author seems appropriate given multiple entries for Dostoevsky/Tolstoy.
      // Let's check prompt: "Module II... Author Title..."
      // I will group by Author for this one.
      books: [
        CollectionBook(
          group: 'Alexander Pushkin',
          title: 'Eugene Onegin',
          author: 'Alexander Pushkin',
          source: 'PG',
          metadata: {
            'Translator': 'Henry Spalding / Various',
            'Theme': 'The Superfluous Man',
          },
        ),
        CollectionBook(
          group: 'Nikolai Gogol',
          title: 'Dead Souls',
          author: 'Nikolai Gogol',
          source: 'PG',
          metadata: {
            'Translator': 'C.J. Hogarth / D.J. Hogarth',
            'Theme': 'Satire, The Grotesque',
          },
        ),
        CollectionBook(
          group: 'Ivan Turgenev',
          title: 'Fathers and Sons',
          author: 'Ivan Turgenev',
          source: 'SE',
          metadata: {
            'Translator': 'Constance Garnett',
            'Theme': 'Nihilism, Generational Conflict',
          },
        ),
        CollectionBook(
          group: 'Fyodor Dostoevsky',
          title: 'Crime and Punishment',
          author: 'Fyodor Dostoevsky',
          source: 'SE',
          metadata: {
            'Translator': 'Constance Garnett',
            'Theme': 'Psychology of Guilt',
          },
        ),
        CollectionBook(
          group: 'Fyodor Dostoevsky',
          title: 'The Brothers Karamazov',
          author: 'Fyodor Dostoevsky',
          source: 'SE',
          metadata: {
            'Translator': 'Constance Garnett',
            'Theme': 'Faith vs. Reason',
          },
        ),
        CollectionBook(
          group: 'Fyodor Dostoevsky',
          title: 'Demons (The Possessed)',
          author: 'Fyodor Dostoevsky',
          source: 'SE',
          metadata: {
            'Translator': 'Constance Garnett',
            'Theme': 'Political Radicalism',
          },
        ),
        CollectionBook(
          group: 'Leo Tolstoy',
          title: 'War and Peace',
          author: 'Leo Tolstoy',
          source: 'PG/SE',
          metadata: {
            'Translator': 'Maude / Garnett',
            'Theme': 'History, Free Will',
          },
        ),
        CollectionBook(
          group: 'Leo Tolstoy',
          title: 'Anna Karenina',
          author: 'Leo Tolstoy',
          source: 'PG/SE',
          metadata: {
            'Translator': 'Aylmer & Louise Maude',
            'Theme': 'Adultery, Social Hypocrisy',
          },
        ),
        CollectionBook(
          group: 'Anton Chekhov',
          title: 'The Lady with the Dog',
          author: 'Anton Chekhov',
          source: 'PG',
          metadata: {
            'Translator': 'Constance Garnett',
            'Theme': 'The Short Story, Mood',
          },
        ),
      ],
    ),

    // Module III: Speculative Horizons — The Roots of Science Fiction and Fantasy
    BookCollection(
      title: 'Speculative Horizons',
      subtitle: 'Module III — Roots of Sci-Fi & Fantasy',
      icon: Icons.rocket_launch,
      color: Colors.deepPurple,
      groupingLabel: 'Sub-Genre',
      books: [
        CollectionBook(
          group: 'Gothic Sci-Fi',
          title: 'Frankenstein',
          author: 'Mary Shelley',
          source: 'SE',
          metadata: {'Key Concept': 'Scientific Hubris, The Other'},
        ),
        CollectionBook(
          group: 'Post-Apocalyptic',
          title: 'The Last Man',
          author: 'Mary Shelley',
          source: 'SE',
          metadata: {'Key Concept': 'Pandemic, Isolation'},
        ),
        CollectionBook(
          group: 'Scientific Romance',
          title: 'The Time Machine',
          author: 'H.G. Wells',
          source: 'SE',
          metadata: {'Key Concept': 'Evolution, Class Struggle'},
        ),
        CollectionBook(
          group: 'Scientific Romance',
          title: 'The Island of Doctor Moreau',
          author: 'H.G. Wells',
          source: 'SE',
          metadata: {'Key Concept': 'Bioethics, De-evolution'},
        ),
        CollectionBook(
          group: 'Scientific Romance',
          title: '20,000 Leagues Under the Sea',
          author: 'Jules Verne',
          source: 'SE',
          metadata: {'Key Concept': 'Exploration, Technology'},
        ),
        CollectionBook(
          group: 'Planetary Romance',
          title: 'A Princess of Mars',
          author: 'Edgar Rice Burroughs',
          source: 'SE',
          metadata: {'Key Concept': 'Pulp Adventure, World-building'},
        ),
        CollectionBook(
          group: 'Cosmic Horror',
          title: 'The Call of Cthulhu',
          author: 'H.P. Lovecraft',
          source: 'SE',
          metadata: {'Key Concept': 'Indifferent Universe, Madness'},
        ),
        CollectionBook(
          group: 'Fantasy',
          title: 'The King of Elfland\'s Daughter',
          author: 'Lord Dunsany',
          source: 'PG',
          metadata: {'Key Concept': 'High Fantasy, Faerie'},
        ),
      ],
    ),

    // Module IV: The Art of Detection (1841–1929)
    BookCollection(
      title: 'The Art of Detection',
      subtitle: 'Module IV (1841–1929)',
      icon: Icons
          .search, // or local_police if available, but search fits detection
      color: Colors.blueGrey,
      groupingLabel: 'Sub-Genre',
      books: [
        CollectionBook(
          group: 'Origins',
          title: 'The Murders in the Rue Morgue',
          author: 'Edgar Allan Poe',
          source: 'SE',
          metadata: {'Sub-Genre': 'Ratiocination'}, // Keeping prompt structure
        ),
        CollectionBook(
          group: 'Sensation',
          title: 'The Moonstone',
          author: 'Wilkie Collins',
          source: 'SE',
          metadata: {'Sub-Genre': 'Sensation Novel / Proto-Procedural'},
        ),
        CollectionBook(
          group: 'Sensation',
          title: 'The Woman in White',
          author: 'Wilkie Collins',
          source: 'SE',
          metadata: {'Sub-Genre': 'Psychological Thriller'},
        ),
        CollectionBook(
          group: 'Golden Age',
          title: 'The Adventures of Sherlock Holmes',
          author: 'Arthur Conan Doyle',
          source: 'SE',
          metadata: {'Sub-Genre': 'The Great Detective'},
        ),
        CollectionBook(
          group: 'Golden Age',
          title: 'The Innocence of Father Brown',
          author: 'G.K. Chesterton',
          source: 'SE',
          metadata: {'Sub-Genre': 'Intuition / Paradox'},
        ),
        CollectionBook(
          group: 'Golden Age',
          title: 'The Mysterious Affair at Styles',
          author: 'Agatha Christie',
          source: 'PG',
          metadata: {'Sub-Genre': 'Whodunit / Puzzle'},
        ),
        CollectionBook(
          group: 'Hardboiled',
          title: 'Red Harvest',
          author: 'Dashiell Hammett',
          source: 'SE',
          metadata: {'Sub-Genre': 'Noir / Continental Op'},
        ),
        CollectionBook(
          group: 'Hardboiled',
          title: 'The Maltese Falcon',
          author: 'Dashiell Hammett',
          source: 'SE/PG',
          metadata: {'Sub-Genre': 'Noir / Sam Spade'},
        ),
      ],
    ),

    // Module V: Literature of Medieval Europe
    BookCollection(
      title: 'Medieval Europe',
      subtitle: 'Module V — Literature of Medieval Europe',
      icon: Icons.fort,
      color: Colors.brown,
      groupingLabel: null, // Flat list
      books: [
        CollectionBook(
          title: 'Beowulf',
          author: 'Unknown',
          source: 'SE',
          metadata: {'Translator': 'J.L. Hall', 'Type': 'Heroic Epic'},
        ),
        CollectionBook(
          title: 'The Divine Comedy',
          author: 'Dante Alighieri',
          source: 'SE',
          metadata: {
            'Translator': 'H.W. Longfellow',
            'Type': 'Christian Allegory',
          },
        ),
        CollectionBook(
          title: 'The Canterbury Tales',
          author: 'Geoffrey Chaucer',
          source: 'PG',
          metadata: {'Translator': 'Skeat / Various', 'Type': 'Estates Satire'},
        ),
        CollectionBook(
          title: 'The Decameron',
          author: 'Giovanni Boccaccio',
          source: 'PG',
          metadata: {'Translator': 'John Payne', 'Type': 'Frame Narrative'},
        ),
        CollectionBook(
          title: 'The Song of Roland',
          author: 'Unknown',
          source: 'PG',
          metadata: {
            'Translator': 'C.K. Moncrieff',
            'Type': 'Chanson de Geste',
          },
        ),
        CollectionBook(
          title: 'The Nibelungenlied',
          author: 'Unknown',
          source: 'PG',
          metadata: {'Translator': 'D.B. Shumway', 'Type': 'Germanic Epic'},
        ),
      ],
    ),

    // Module VI: Victorian Social Realism (1837–1901)
    BookCollection(
      title: 'Victorian Social Realism',
      subtitle: 'Module VI (1837–1901)',
      icon: Icons.factory,
      color: Colors.grey,
      groupingLabel: null,
      books: [
        CollectionBook(
          title: 'Bleak House',
          author: 'Charles Dickens',
          source: 'SE',
          metadata: {'Critical Focus': 'Law, Urban Decay, Dual Narrative'},
        ),
        CollectionBook(
          title: 'Great Expectations',
          author: 'Charles Dickens',
          source: 'SE',
          metadata: {'Critical Focus': 'Class Ambition, Bildungsroman'},
        ),
        CollectionBook(
          title: 'Middlemarch',
          author: 'George Eliot',
          source: 'SE',
          metadata: {'Critical Focus': 'Provincial Life, Reform, Psychology'},
        ),
        CollectionBook(
          title: 'Vanity Fair',
          author: 'W.M. Thackeray',
          source: 'SE',
          metadata: {'Critical Focus': 'Satire, Social Climbing'},
        ),
        CollectionBook(
          title: 'Tess of the d\'Urbervilles',
          author: 'Thomas Hardy',
          source: 'SE',
          metadata: {'Critical Focus': 'Fate, Sexual Morality, Rural Change'},
        ),
        CollectionBook(
          title: 'The Warden',
          author: 'Anthony Trollope',
          source: 'SE',
          metadata: {'Critical Focus': 'Church Politics, Ethics'},
        ),
        CollectionBook(
          title: 'North and South',
          author: 'Elizabeth Gaskell',
          source: 'PG',
          metadata: {'Critical Focus': 'Industrialization, Labor Relations'},
        ),
      ],
    ),

    // Module VII: The Philosophical Mind
    BookCollection(
      title: 'The Philosophical Mind',
      subtitle: 'Module VII',
      icon: Icons.psychology,
      color: Colors.teal,
      groupingLabel: 'Era',
      books: [
        CollectionBook(
          group: 'Ancient',
          title: 'The Republic',
          author: 'Plato',
          source: 'SE',
          metadata: {'Translator': 'Benjamin Jowett'},
        ),
        CollectionBook(
          group: 'Ancient',
          title: 'Nicomachean Ethics',
          author: 'Aristotle',
          source: 'SE',
          metadata: {'Translator': 'F.H. Peters'},
        ),
        CollectionBook(
          group: 'Enlightenment',
          title: 'Leviathan',
          author: 'Thomas Hobbes',
          source: 'SE',
          metadata: {'Translator': 'N/A'},
        ),
        CollectionBook(
          group: 'Enlightenment',
          title: 'The Social Contract',
          author: 'Rousseau',
          source: 'SE',
          metadata: {'Translator': 'G.D.H. Cole'},
        ),
        CollectionBook(
          group: 'Enlightenment',
          title: 'On Liberty',
          author: 'J.S. Mill',
          source: 'SE',
          metadata: {'Translator': 'N/A'},
        ),
        CollectionBook(
          group: 'Modern',
          title: 'Thus Spake Zarathustra',
          author: 'Nietzsche',
          source: 'SE',
          metadata: {'Translator': 'Thomas Common'},
        ),
        CollectionBook(
          group: 'Modern',
          title: 'Beyond Good and Evil',
          author: 'Nietzsche',
          source: 'SE',
          metadata: {'Translator': 'Helen Zimmern'},
        ),
      ],
    ),

    // Module VIII: Modernism and the Avant-Garde (1900–1929)
    BookCollection(
      title: 'Modernism & Avant-Garde',
      subtitle: 'Module VIII (1900–1929)',
      icon: Icons.auto_awesome,
      color: Colors.amber,
      groupingLabel: null,
      books: [
        // Title Author Year Source Innovation
        CollectionBook(
          title: 'Ulysses',
          author: 'James Joyce',
          source: 'SE',
          metadata: {'Year': '1922', 'Innovation': 'Stream of Consciousness'},
        ),
        CollectionBook(
          title: 'Mrs. Dalloway',
          author: 'Virginia Woolf',
          source: 'SE',
          metadata: {'Year': '1925', 'Innovation': 'Interior Monologue, Time'},
        ),
        CollectionBook(
          title: 'To the Lighthouse',
          author: 'Virginia Woolf',
          source: 'SE',
          metadata: {'Year': '1927', 'Innovation': 'Perspective, Memory'},
        ),
        CollectionBook(
          title: 'Winesburg, Ohio',
          author: 'Sherwood Anderson',
          source: 'SE',
          metadata: {
            'Year': '1919',
            'Innovation': 'The Grotesque, Short Story Cycle',
          },
        ),
        CollectionBook(
          title: 'Main Street',
          author: 'Sinclair Lewis',
          source: 'SE',
          metadata: {'Year': '1920', 'Innovation': 'Satire, Anti-Romance'},
        ),
        CollectionBook(
          title: 'Sons and Lovers',
          author: 'D.H. Lawrence',
          source: 'SE',
          metadata: {'Year': '1913', 'Innovation': 'Psychoanalysis, Class'},
        ),
      ],
    ),

    // Collection I: The French Canvas
    BookCollection(
      title: 'The French Canvas',
      subtitle: 'Realism, Romanticism & Social Chronicle',
      icon: Icons.brush,
      color: Colors.blueAccent,
      groupingLabel: null,
      books: [
        CollectionBook(
          title: 'Father Goriot',
          author: 'Honoré de Balzac',
          source: 'SE',
          metadata: {
            'Translator': 'Ellen Marriage',
            'Focus': 'Realism, Social Climbing, Paris',
          },
        ),
        CollectionBook(
          title: 'Les Misérables',
          author: 'Victor Hugo',
          source: 'SE',
          metadata: {
            'Translator': 'Isabel F. Hapgood',
            'Focus': 'Romanticism, Law vs. Grace, History',
          },
        ),
        CollectionBook(
          title: 'Germinal',
          author: 'Émile Zola',
          source: 'SE',
          metadata: {
            'Translator': 'Havelock Ellis',
            'Focus': 'Naturalism, Labor, Class Struggle',
          },
        ),
        CollectionBook(
          title: 'Madame Bovary',
          author: 'Gustave Flaubert',
          source: 'SE',
          metadata: {
            'Translator': 'Eleanor Marx-Aveling',
            'Focus': 'Psychological Realism, Ennui',
          },
        ),
        CollectionBook(
          title: 'The Count of Monte Cristo',
          author: 'Alexandre Dumas',
          source: 'SE',
          metadata: {
            'Translator': 'Chapman and Hall',
            'Focus': 'Adventure, Revenge, Serial Fiction',
          },
        ),
      ],
    ),

    // Collection II: Voices of the Veil
    BookCollection(
      title: 'Voices of the Veil',
      subtitle: 'African American Literature (1860–1930)',
      icon: Icons.record_voice_over, // or history_edu
      color: Colors.brown,
      groupingLabel: null,
      books: [
        CollectionBook(
          title: 'The Souls of Black Folk',
          author: 'W. E. B. Du Bois',
          source: 'SE',
          metadata: {
            'Format': 'Essays',
            'Focus': 'Double Consciousness, Sociology',
          },
        ),
        CollectionBook(
          title: 'Up From Slavery',
          author: 'Booker T. Washington',
          source: 'SE',
          metadata: {
            'Format': 'Autobiography',
            'Focus': 'Self-Reliance, Industrial Education',
          },
        ),
        CollectionBook(
          title: 'The Autobiography of an Ex-Colored Man',
          author: 'James Weldon Johnson',
          source: 'SE',
          metadata: {'Format': 'Novel', 'Focus': 'Racial Passing, Jazz Age'},
        ),
        CollectionBook(
          title: 'Cane',
          author: 'Jean Toomer',
          source: 'SE',
          metadata: {
            'Format': 'Mixed Media',
            'Focus': 'Harlem Renaissance, The South, Modernism',
          },
        ),
        CollectionBook(
          title: 'The Marrow of Tradition',
          author: 'Charles W. Chesnutt',
          source: 'SE',
          metadata: {
            'Format': 'Historical Fiction',
            'Focus': 'Reconstruction, Political Violence',
          },
        ),
      ],
    ),

    // Collection III: The Architects of Antiquity
    BookCollection(
      title: 'Architects of Antiquity',
      subtitle: 'Epic Poetry, Tragedy & Hellenic Legacy',
      icon: Icons
          .temple_buddhist, // closest to greek temple in standard set, or museum
      color: Colors.amberAccent,
      groupingLabel: null,
      books: [
        CollectionBook(
          title: 'The Iliad',
          author: 'Homer',
          source: 'SE',
          metadata: {
            'Translator': 'William Cullen Bryant',
            'Focus': 'Epic Poetry, War, Blank Verse',
          },
        ),
        CollectionBook(
          title: 'The Odyssey',
          author: 'Homer',
          source: 'SE',
          metadata: {
            'Translator': 'William Cullen Bryant',
            'Focus': 'Epic Poetry, The Journey',
          },
        ),
        CollectionBook(
          title: 'The Aeneid',
          author: 'Virgil',
          source: 'SE',
          metadata: {'Translator': 'John Dryden', 'Focus': 'Roman Epic, Myth'},
        ),
        CollectionBook(
          title: 'Oedipus Rex',
          author: 'Sophocles',
          source: 'SE',
          metadata: {
            'Translator': 'Francis Storr',
            'Focus': 'Greek Tragedy, Fate',
          },
        ),
        CollectionBook(
          title: 'Dialogues (e.g., Cratylus, Republic)',
          author: 'Plato',
          source: 'SE',
          metadata: {
            'Translator': 'Benjamin Jowett',
            'Focus': 'Philosophy, Socratic Method',
          },
        ),
      ],
    ),

    // Collection IV: Shadows and Spectres
    BookCollection(
      title: 'Shadows and Spectres',
      subtitle: 'Gothic and the Uncanny',
      icon: Icons.nights_stay,
      color: Colors.purple.shade900,
      groupingLabel: 'Sub-Genre',
      books: [
        CollectionBook(
          group: 'Vampire Fiction',
          title: 'Carmilla',
          author: 'J. Sheridan Le Fanu',
          source: 'SE',
          metadata: {'Focus': 'Female Vampire, Pre-Dracula'},
        ),
        CollectionBook(
          group: 'Psych. Horror',
          title: 'The Turn of the Screw',
          author: 'Henry James',
          source: 'SE',
          metadata: {'Focus': 'Ambiguity, Unreliable Narrator'},
        ),
        CollectionBook(
          group: 'Urban Gothic',
          title: 'The Strange Case of Dr. Jekyll and Mr. Hyde',
          author: 'R.L. Stevenson',
          source: 'SE',
          metadata: {'Focus': 'Duality of Man, Addiction'},
        ),
        CollectionBook(
          group: 'Gothic Horror',
          title: 'Dracula',
          author: 'Bram Stoker',
          source: 'SE',
          metadata: {'Focus': 'Epistolary Format, The Other'},
        ),
        CollectionBook(
          group: 'Antiquarian Horror',
          title: 'Short Fiction (e.g., Ghost Stories...)',
          author: 'M.R. James',
          source: 'SE',
          metadata: {'Focus': 'Cursed Objects, Academic Settings'},
        ),
      ],
    ),

    // Collection V: The Golden Age of Imagination
    BookCollection(
      title: 'Golden Age of Imagination',
      subtitle: 'Edwardian & Victorian Children’s Classics',
      icon: Icons.castle,
      color: Colors.greenAccent.shade700,
      groupingLabel: null,
      books: [
        CollectionBook(
          title: 'The Secret Garden',
          author: 'Frances H. Burnett',
          source: 'SE',
          metadata: {
            'Setting': 'Yorkshire Moors',
            'Focus': 'Healing, Nature, New Thought',
          },
        ),
        CollectionBook(
          title: 'Anne of Green Gables',
          author: 'L.M. Montgomery',
          source: 'SE',
          metadata: {
            'Setting': 'Prince Edward Island',
            'Focus': 'Imagination, Pastoral',
          },
        ),
        CollectionBook(
          title: 'The Wind in the Willows',
          author: 'Kenneth Grahame',
          source: 'SE',
          metadata: {
            'Setting': 'The River Bank',
            'Focus': 'Anthropomorphism, Home',
          },
        ),
        CollectionBook(
          title: 'Treasure Island',
          author: 'R.L. Stevenson',
          source: 'SE',
          metadata: {
            'Setting': 'The Caribbean',
            'Focus': 'Pirates, Moral Ambiguity',
          },
        ),
        CollectionBook(
          title: 'A Little Princess',
          author: 'Frances H. Burnett',
          source: 'SE',
          metadata: {'Setting': 'London', 'Focus': 'Resilience, Imagination'},
        ),
      ],
    ),
  ]; // End of previous list - wait, I need to remove the closing bracket to append.
  // Actually, I can just replace the closing bracket line with the new items + closing bracket.
  // But let's check the tool usage. It replaces "TargetContent".
  // So I will target "  ];" at the end and replace it with ", ... new items ... ];"
}
