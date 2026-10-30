import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Every bundled SVG decodes as standalone vector artwork', (
    tester,
  ) async {
    final assets = Directory('assets/illustrations/vector')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.svg'));
    expect(assets, isNotEmpty);
    await tester.runAsync(() async {
      for (final asset in assets) {
        final source = asset.readAsStringSync();
        expect(source, isNot(contains('<image')), reason: asset.path);
        expect(source, isNot(contains('base64')), reason: asset.path);
        final picture = await vg.loadPicture(
          SvgAssetLoader(asset.path.replaceAll('\\', '/')),
          null,
        );
        expect(picture.size.isEmpty, isFalse, reason: asset.path);
        picture.picture.dispose();
      }
    });
  });
}
