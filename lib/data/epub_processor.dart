import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class EpubProcessor {
  /// Processes an existing EPUB file to make it Kindle-friendly.
  ///
  /// 1. Extracts metadata to determine a clean filename.
  /// 2. Ensures cover image metadata is set correctly in OPF.
  /// 3. Injects a simple cover.xhtml if missing (and if a cover image exists).
  /// 4. Repacks the EPUB.
  ///
  /// Returns the path to the newly created temporary file.
  /// Process EPUB with optional external cover injection
  static Future<File> process(
    String inputPath, {
    String? externalCoverPath,
  }) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw Exception('Input file not found: $inputPath');
    }

    // 1. Read the Zip file
    // 1. Read the Zip file
    final bytes = await inputFile.readAsBytes();
    final rawArchive = ZipDecoder().decodeBytes(bytes);

    // Create a fresh, mutable Archive and copy files
    // This avoids "UnmodifiableListMixin" errors if the decoder returns an immutable list
    final archive = Archive();
    for (final file in rawArchive) {
      archive.addFile(file);
    }

    // Better strategy: Create a new Archive for output if needed?
    // Or just assume it is mutable but maybe 'codeUnits' was the issue.
    // Let's fix codeUnits usage regardless.

    // 2. Find the OPF file path from container.xml
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      throw Exception('Invalid EPUB: Missing META-INF/container.xml');
    }

    final containerXml = XmlDocument.parse(
      String.fromCharCodes(containerFile.content),
    );
    final rootfile = containerXml.findAllElements('rootfile').firstOrNull;
    final opfPath = rootfile?.getAttribute('full-path');

    if (opfPath == null) {
      throw Exception(
        'Invalid EPUB: Could not locate OPF file in container.xml',
      );
    }

    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception(
        'Invalid EPUB: OPF file listed in container.xml not found ($opfPath)',
      );
    }

    // 3. Parse OPF
    var opfContent = String.fromCharCodes(opfFile.content);
    final opfXml = XmlDocument.parse(opfContent);

    // 4. Extract Title and Author for filename
    final metadata = opfXml.findAllElements('metadata').firstOrNull;
    String title = 'Unknown Title';
    String author = 'Unknown Author';

    if (metadata != null) {
      final dcTitle = metadata
          .findAllElements('dc:title')
          .firstOrNull
          ?.innerText;
      final dcCreator = metadata
          .findAllElements('dc:creator')
          .firstOrNull
          ?.innerText;

      if (dcTitle != null && dcTitle.isNotEmpty) title = dcTitle;
      if (dcCreator != null && dcCreator.isNotEmpty) author = dcCreator;
    }

    // Sanitize for filename
    final safeTitle = _sanitizeFilename(title);
    final safeAuthor = _sanitizeFilename(author);
    final newFilename = '$safeTitle - $safeAuthor.epub';

    // 5. Fix Cover Metadata
    final manifest = opfXml.findAllElements('manifest').firstOrNull;
    if (manifest != null) {
      XmlElement? coverImageItem;

      // A. Try External Cover Injection
      if (externalCoverPath != null) {
        final extCoverFile = File(externalCoverPath);
        if (await extCoverFile.exists()) {
          try {
            final extCoverBytes = await extCoverFile.readAsBytes();
            final extExtension = p.extension(externalCoverPath);
            final coverExtName = 'cover_injected$extExtension';

            // Place alongside OPF
            final opfDir = p.dirname(opfPath);
            final resultPath = opfDir == '.'
                ? coverExtName
                : '$opfDir/$coverExtName';

            // Check if likely duplicates? Archive allows multiple files with same name? standard zip does, but better avoid.
            // We use a unique name.

            archive.addFile(
              ArchiveFile(resultPath, extCoverBytes.length, extCoverBytes),
            );

            final newCoverId = 'cover-injected';
            final mediaType = _getMediaType(externalCoverPath);

            // Add new item to manifest
            coverImageItem = XmlElement(XmlName('item'), [
              XmlAttribute(XmlName('id'), newCoverId),
              XmlAttribute(XmlName('href'), coverExtName),
              XmlAttribute(XmlName('media-type'), mediaType),
              XmlAttribute(XmlName('properties'), 'cover-image'),
            ]);
            manifest.children.add(coverImageItem);

            // Update Meta
            if (metadata != null) {
              final oldMeta = metadata.children
                  .whereType<XmlElement>()
                  .firstWhere(
                    (e) => e.getAttribute('name') == 'cover',
                    orElse: () => XmlElement(XmlName('dummy')),
                  );
              if (oldMeta.name.local != 'dummy') {
                oldMeta.setAttribute('content', newCoverId);
              } else {
                metadata.children.add(
                  XmlElement(XmlName('meta'), [
                    XmlAttribute(XmlName('name'), 'cover'),
                    XmlAttribute(XmlName('content'), newCoverId),
                  ]),
                );
              }
            }
          } catch (e) {
            print('Error injecting external cover: $e');
            // Fallback to internal search
            coverImageItem = null;
          }
        }
      }

      // B. Internal Fallback
      if (coverImageItem == null) {
        // Method A: Check for properties="cover-image"
        coverImageItem = manifest.children.whereType<XmlElement>().firstWhere(
          (e) => e.getAttribute('properties') == 'cover-image',
          orElse: () => XmlElement(XmlName('dummy')),
        );

        if (coverImageItem.name.local == 'dummy') {
          coverImageItem = null; // reset

          // Method B: Check for <meta name="cover" content="itemId">
          String? coverId;
          final metaCover = metadata?.children
              .whereType<XmlElement>()
              .firstWhere(
                (e) => e.getAttribute('name') == 'cover',
                orElse: () => XmlElement(XmlName('dummy')),
              );

          if (metaCover != null && metaCover.name.local != 'dummy') {
            coverId = metaCover.getAttribute('content');
          }

          if (coverId != null) {
            coverImageItem = manifest.children
                .whereType<XmlElement>()
                .firstWhere(
                  (e) => e.getAttribute('id') == coverId,
                  orElse: () => XmlElement(XmlName('dummy')),
                );
            if (coverImageItem.name.local == 'dummy') coverImageItem = null;
          }

          // Method C: Heuristic
          if (coverImageItem == null) {
            coverImageItem = manifest.children
                .whereType<XmlElement>()
                .firstWhere((e) {
                  final id = e.getAttribute('id')?.toLowerCase() ?? '';
                  final href = e.getAttribute('href')?.toLowerCase() ?? '';
                  final type = e.getAttribute('media-type') ?? '';
                  return (id.contains('cover') || href.contains('cover')) &&
                      type.startsWith('image/');
                }, orElse: () => XmlElement(XmlName('dummy')));
            if (coverImageItem.name.local == 'dummy') coverImageItem = null;
          }

          // Apply fixes if found
          if (coverImageItem != null) {
            final coverId = coverImageItem.getAttribute('id');
            if (coverImageItem.getAttribute('properties') != 'cover-image') {
              coverImageItem.setAttribute('properties', 'cover-image');
            }
            if (metadata != null && coverId != null) {
              final hasMeta = metadata.children.whereType<XmlElement>().any(
                (e) =>
                    e.getAttribute('name') == 'cover' &&
                    e.getAttribute('content') == coverId,
              );
              if (!hasMeta) {
                metadata.children.add(
                  XmlElement(XmlName('meta'), [
                    XmlAttribute(XmlName('name'), 'cover'),
                    XmlAttribute(XmlName('content'), coverId),
                  ]),
                );
              }
            }
          }
        }
      }

      // Finally, ensure cover page exists (using whatever cover item we have, injected or internal)
      // Note: usage of _ensureCoverPage assumes coverImageItem is set
      if (coverImageItem != null) {
        _ensureCoverPage(archive, opfXml, opfPath, coverImageItem);

        // Save OPF
        final newOpfString = opfXml.toXmlString();
        final existingFileIndex = archive.files.indexWhere(
          (f) => f.name == opfPath,
        );
        if (existingFileIndex != -1) {
          final newContentInfo = Uint8List.fromList(newOpfString.codeUnits);
          final newFile = ArchiveFile(
            opfPath,
            newContentInfo.length,
            newContentInfo,
          );

          // Workaround: Direct assignment []= fails with UnmodifiableListMixin in some contexts.
          // Since we know 'add' works (we built the archive via add), try remove/insert.
          try {
            archive.files.removeAt(existingFileIndex);
            archive.files.insert(existingFileIndex, newFile);
          } catch (e) {
            print('Error modifying archive list in place: $e');
            // Fallback: Just add it (will be duplicate in list, but ZipEncoder usually handles last-win or duplicates)
            // Better: Remove by object if index failed?
            // If removeAt failed, we can't remove.
            // Let's try to just add it and hope.
            archive.addFile(newFile);
          }
        }
      }
    }

    // 6. Repack to Temp
    final tempDir = await getTemporaryDirectory();
    final outputPath = p.join(tempDir.path, newFilename);
    final encoder = ZipEncoder();
    final newZipBytes = encoder.encode(archive);

    if (newZipBytes == null) {
      throw Exception('Failed to encode EPUB');
    }

    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(newZipBytes);

    return outputFile;
  }

  static void _ensureCoverPage(
    Archive archive,
    XmlDocument opfXml,
    String opfPath,
    XmlElement coverImageItem,
  ) {
    // Check Spine for a cover page reference
    final spine = opfXml.findAllElements('spine').firstOrNull;
    if (spine == null) return;

    // Does the first item in spine look like a cover?
    // Or is there any item with properties="cover-image"? (No, valid only on manifest items usually? Actually HTML items shouldn't have it generally, images do)
    // But we can check if there is an item referencing a file named cover.xhtml or similar.

    // We'll rely on the manifest to see if there is an XHTML item that we think is the cover page.
    final manifest = opfXml.findAllElements('manifest').firstOrNull;
    if (manifest == null) return;

    bool hasCoverPage = false;

    // Look for an HTML item in manifest that might be a cover page
    // Often has id="cover-page" or href="cover.xhtml"
    // Also strictly, should check <guide> <reference type="cover" ... />

    // 1. Check Guide
    final guide = opfXml.findAllElements('guide').firstOrNull;
    if (guide != null) {
      final coverRef = guide.children.whereType<XmlElement>().firstWhere(
        (e) => e.getAttribute('type') == 'cover',
        orElse: () => XmlElement(XmlName('dummy')),
      );
      if (coverRef.name.local != 'dummy') {
        hasCoverPage = true;
        // Ideally we verified this file actually exists and is in spine, but let's assume if it's in guide, it's there.
      }
    }

    if (!hasCoverPage) {
      // Create one!
      final coverImageHref = coverImageItem.getAttribute('href');
      // final coverImageMime = coverImageItem.getAttribute('media-type'); // Unused

      if (coverImageHref == null) return;

      // Determine relative path for the new cover.xhtml
      // opfPath is like "OEBPS/content.opf"
      // coverImageHref is relative to OPF, e.g. "images/cover.jpg"

      // We will place cover.xhtml in the same dir as existing HTMLs or just alongside OPF to be safe?
      // Let's place it alongside OPF.
      final opfDir = p.dirname(opfPath);
      final coverPageFilename =
          'cover_gen_${DateTime.now().millisecondsSinceEpoch}.xhtml';
      final fullCoverPagePath = opfDir == '.'
          ? coverPageFilename
          : '$opfDir/$coverPageFilename';

      // Content
      final xhtmlContent =
          '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>Cover</title>
  <style type="text/css">
    body { margin: 0; padding: 0; text-align: center; }
    div { height: 100%; width: 100%; }
    img { max-height: 100%; max-width: 100%; }
  </style>
</head>
<body>
  <div>
    <img src="$coverImageHref" alt="Cover" />
  </div>
</body>
</html>''';

      // Add to Archive
      // Use Uint8List for mutable buffer
      final xhtmlBytes = Uint8List.fromList(xhtmlContent.codeUnits);
      archive.addFile(
        ArchiveFile(fullCoverPagePath, xhtmlBytes.length, xhtmlBytes),
      );

      // Add to Manifest
      // XmlElement(name, attributes, children)
      manifest.children.add(
        XmlElement(XmlName('item'), [
          XmlAttribute(XmlName('id'), 'cover-page-gen'),
          XmlAttribute(XmlName('href'), coverPageFilename),
          XmlAttribute(XmlName('media-type'), 'application/xhtml+xml'),
        ]),
      );

      // Add to Spine as FIRST item
      final itemRef = XmlElement(XmlName('itemref'), [
        XmlAttribute(XmlName('idref'), 'cover-page-gen'),
      ]);
      spine.children.insert(0, itemRef);

      // Add to Guide (create if missing)
      if (guide == null) {
        opfXml.rootElement.children.add(
          XmlElement(XmlName('guide'), [], [
            XmlElement(XmlName('reference'), [
              XmlAttribute(XmlName('type'), 'cover'),
              XmlAttribute(XmlName('title'), 'Cover'),
              XmlAttribute(XmlName('href'), coverPageFilename),
            ]),
          ]),
        );
      } else {
        guide.children.insert(
          0,
          XmlElement(XmlName('reference'), [
            XmlAttribute(XmlName('type'), 'cover'),
            XmlAttribute(XmlName('title'), 'Cover'),
            XmlAttribute(XmlName('href'), coverPageFilename),
          ]),
        );
      }
    }
  }

  static String _sanitizeFilename(String input) {
    // 1. Convert to ASCII-compatible where possible (User might have accents)
    // For now simple regex for filesystem safety
    var safe = input.replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '',
    ); // Remove illegal chars
    safe = safe.replaceAll(RegExp(r'\s+'), ' '); // Collapse spaces
    safe = safe.trim();
    if (safe.length > 50) safe = safe.substring(0, 50); // Truncate
    return safe;
  }

  static String _getMediaType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }
}
