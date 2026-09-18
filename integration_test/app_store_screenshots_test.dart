// App Store screenshot capture for ZeroWallet.
//
// This integration test drives the real app on the 6.9" simulator and captures
// the key screens. Screenshots use the integration_test native capture path
// (binding.takeScreenshot), which on iOS grabs the full simulator screen at
// its native resolution — 1320x2868 for the iPhone 18 Pro Max (440x956
// logical points at 3x scale). The companion driver writes them to
// <repo>/screenshots/<name>.png.
//
// Run with:
//   flutter drive \
//     --driver=test_driver/app_store_screenshots_driver_test.dart \
//     --target=integration_test/app_store_screenshots_test.dart \
//     -d <simulator-udid>
//
// (Or via ./tool/app_store_screenshots.sh which boots the 6.9" simulator.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:zero_wallet/wallet.dart';

import 'test_helpers.dart';

const Duration kSettle = Duration(milliseconds: 500);

Future<void> captureScreenshot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  // Let animations/transitions settle, then capture the full native screen.
  await tester.pump(kSettle);
  await tester.pump(kSettle);
  await binding.takeScreenshot(name);
}

// `home_import_wallet_button` navigates to ImportMethodPage, which presents a
// list of import methods. Tap the mnemonic card. This run forces English, so
// the card title is 'Mnemonic' (zh would be '助记词').
Future<void> chooseMnemonicImportMethod(WidgetTester tester) async {
  await pumpUntilVisible(tester, find.text('Mnemonic'));
  await tapAndPump(tester, find.text('Mnemonic'));
}

// These screens use a plain `IconButton(Icons.arrow_back_ios)` AppBar leading,
// not a Material `BackButton`/Cupertino back button, so `tester.pageBack()`
// finds nothing. Tap the arrow icon instead.
Future<void> tapBackButton(WidgetTester tester) async {
  final back = find.byIcon(Icons.arrow_back_ios).first;
  await pumpUntilVisible(tester, back);
  await tapAndPump(tester, back);
}

void main() {
  // Clears secure storage between runs so the app boots to the welcome screen
  // (a leftover wallet from a prior run would otherwise land on wallet home).
  configureIntegrationTest();
  final binding = IntegrationTestWidgetsFlutterBinding.instance;

  testWidgets('captures App Store screenshots', (tester) async {
    await launchTestApp();
    await tester.pump(const Duration(seconds: 1));

    // Force English for the whole run. The app defaults to system language
    // (zh on this simulator), but App Store screenshots should be in English.
    await SecureStorageService.saveUsageSettings(
      const UsageSettings(language: AppLanguage.english),
    );
    final usageSettingsController = tester
        .widget<ChangeNotifierProvider<UsageSettingsController>>(
          find.byType(ChangeNotifierProvider<UsageSettingsController>),
        )
        .value;
    await usageSettingsController.initialize();
    await tester.pump(kSettle);
    await tester.pump(kSettle);

    // 1. Welcome / onboarding (fresh install, no wallet yet).
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('home_import_wallet_button')),
    );
    await captureScreenshot(tester, binding, '01_welcome');

    // 2. Import a wallet (default BIP39 test vector).
    await openImportWalletFromHome(tester);
    await chooseMnemonicImportMethod(tester);
    await fillImportWalletForm(tester, walletName: 'Zero Wallet');
    await submitImportWallet(tester);
    // Same assertions as expectPostImportPromptVisible, but with the English
    // success text (that helper hardcodes the zh string '导入成功').
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('post_import_sheet_title')),
    );
    expect(find.byKey(const Key('post_import_sheet_title')), findsOneWidget);
    expect(find.text('Import Successful'), findsOneWidget);
    await captureScreenshot(tester, binding, '02_import_success');

    // 3. Wallet home.
    await chooseViewWalletFromPostImportPrompt(tester);
    await pumpUntilWalletHomeReady(tester, walletName: 'Zero Wallet');
    await captureScreenshot(tester, binding, '03_wallet_home');

    // 4. Receive (QR code).
    await openReceiveFromWalletHome(tester);
    await expectWalletReceivePage(tester);
    await captureScreenshot(tester, binding, '04_receive');

    // 5. Wallet detail (HD management).
    await tapBackButton(tester);
    await pumpUntilWalletHomeReady(tester, walletName: 'Zero Wallet');
    await openWalletDetailFromHome(tester);
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('wallet_detail_hd_manage_button')),
    );
    await captureScreenshot(tester, binding, '05_wallet_detail');

    // 6. Profile / settings.
    await tapBackButton(tester);
    await pumpUntilWalletHomeReady(tester, walletName: 'Zero Wallet');
    await tapAndPump(tester, find.byKey(const Key('bottom_nav_profile')));
    await pumpUntilVisible(tester, find.byKey(const Key('profile_page_title')));
    await captureScreenshot(tester, binding, '06_profile');
  });
}
