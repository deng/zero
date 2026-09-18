// Companion driver for app_store_screenshots_test.dart.
//
// Receives screenshots captured by the integration test (via the
// integration_test screenshot channel) and writes them to
// <repo>/screenshots/<name>.png so they can be uploaded to App Store Connect.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const outputDir = 'screenshots';

  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('$outputDir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('Wrote $outputDir/$name.png (${bytes.length} bytes)');
      return true;
    },
    writeResponseOnFailure: true,
  );
}
