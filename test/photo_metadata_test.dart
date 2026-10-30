import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/pages/media_viewer.dart';

void main() {
  testWidgets('Photo details report actual bundled bytes and dimensions', (
    tester,
  ) async {
    final metadata = await tester.runAsync(
      () => readBundledPhotoMetadata('assets/photos/photo_01.jpg'),
    );
    expect(metadata!.bytes, File('assets/photos/photo_01.jpg').lengthSync());
    expect(metadata.width, 800);
    expect(metadata.height, 533);
    expect(metadata.fileSize, '${(metadata.bytes / 1024).round()} KB');
  });
}
