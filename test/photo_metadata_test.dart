import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/media_viewer.dart';

void main() {
  test('parseDateFromFileName extracts camera and screenshot timestamps', () {
    final cameraDate = parseDateFromFileName('IMG_20261113_180034.jpg');
    expect(cameraDate, DateTime(2026, 11, 13, 18, 0, 34));

    final videoDate = parseDateFromFileName('VID_20261111_161709.mp4');
    expect(videoDate, DateTime(2026, 11, 11, 16, 17, 9));

    final pxlDate = parseDateFromFileName('PXL_20240510_123045.jpg');
    expect(pxlDate, DateTime(2024, 5, 10, 12, 30, 45));

    final dateOnly = parseDateFromFileName('2023-08-15-family.jpg');
    expect(dateOnly, DateTime(2023, 8, 15, 12, 0, 0));

    final nonDate = parseDateFromFileName('random_photo.jpg');
    expect(nonDate, isNull);
  });

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
