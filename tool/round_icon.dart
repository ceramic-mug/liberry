import 'dart:io';
import 'dart:math';
import 'package:image/image.dart';

void main() {
  final file = File('assets/icon.png');
  if (!file.existsSync()) {
    print('Error: assets/icon.png not found');
    exit(1);
  }

  final bytes = file.readAsBytesSync();
  final image = decodeImage(bytes);

  if (image == null) {
    print('Error: Could not decode image');
    exit(1);
  }

  // macOS corner radius is approx 22.37% of the size
  final size = min(image.width, image.height);
  final radius = (size * 0.2237).round();

  // Create a new image with alpha channel
  final rounded = Image(size, size);

  // Helper to check if a point is inside the rounded rect
  bool isInside(int x, int y, int w, int h, int r) {
    // Check main body (cross)
    // Center horizontal rect: 0 to W, R to H-R
    if (x >= 0 && x < w && y >= r && y < h - r) return true;
    // Center vertical rect: R to W-R, 0 to H
    if (x >= r && x < w - r && y >= 0 && y < h) return true;

    // Corners
    int cx, cy;

    if (x < r && y < r) {
      // Top Left
      cx = r;
      cy = r;
    } else if (x >= w - r && y < r) {
      // Top Right
      cx = w - r - 1;
      cy = r;
    } else if (x < r && y >= h - r) {
      // Bottom Left
      cx = r;
      cy = h - r - 1;
    } else if (x >= w - r && y >= h - r) {
      // Bottom Right
      cx = w - r - 1;
      cy = h - r - 1;
    } else {
      // Should be covered by main body checks, but just in case
      return false;
    }

    // Distance check
    final dx = x - cx;
    final dy = y - cy;
    return (dx * dx + dy * dy) <= (r * r);
  }

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      if (isInside(x, y, size, size, radius)) {
        rounded.setPixel(x, y, image.getPixel(x, y));
      } else {
        rounded.setPixel(x, y, 0); // Transparent
      }
    }
  }

  final outFile = File('assets/icon_rounded.png');
  outFile.writeAsBytesSync(encodePng(rounded));
  print('Created assets/icon_rounded.png');
}
