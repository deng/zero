import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_wallet/wallet.dart';
import 'test_helpers.dart';

/// Minimal mock aggregator for smoke testing the swap page UI.
class _SmokeMockDexAggregator implements DexAggregator {
  @override
  DexAggregatorType get type => DexAggregatorType.mock;

  @override
  Set<ChainType> get supportedChains => {ChainType.eth};

  @override
  Future<List<DexTokenInfo>> getTokens(String chainId) async {
    return [
      const DexTokenInfo(
        address: DexTokenInfo.nativeEthAddress,
        symbol: 'ETH',
        name: 'Ethereum',
        decimals: 18,
        chain: ChainType.eth,
      ),
      const DexTokenInfo(
        address: '0xMockUSDC',
        symbol: 'USDC',
        name: 'USD Coin',
        decimals: 6,
        chain: ChainType.eth,
      ),
    ];
  }

  @override
  Future<QuoteResult> getQuote(QuoteRequest request) async {
    throw UnimplementedError('smoke test should not request quotes');
  }

  @override
  Future<SwapTransaction> buildSwapTx(SwapRequest request) async {
    throw UnimplementedError('smoke test should not build swap tx');
  }

  @override
  Future<ApprovalTransaction> buildApprovalTx(ApprovalRequest request) async {
    throw UnimplementedError('smoke test should not build approval tx');
  }
}

void main() {
  configureIntegrationTest();

  testWidgets('swap page entry with wallet info', (tester) async {
    // -----------------------------------------------------------------------
    // 1. Launch app and import wallet
    // -----------------------------------------------------------------------
    await launchTestApp();
    await importWalletFromHome(
      tester,
      walletName: 'Smoke Test Wallet',
      mnemonic: kValidImportMnemonic,
    );
    await chooseViewWalletFromPostImportPrompt(tester);
    await expectWalletHome(tester, walletName: 'Smoke Test Wallet');

    // -----------------------------------------------------------------------
    // 2. Register mock aggregator before swap page initialises
    // -----------------------------------------------------------------------
    DexAggregatorRegistry.register(_SmokeMockDexAggregator());

    // -----------------------------------------------------------------------
    // 3. Navigate to swap tab
    // -----------------------------------------------------------------------
    final swapTab = find.byKey(const Key('bottom_nav_swap'));
    await pumpUntilVisible(tester, swapTab);
    await tapAndPump(tester, swapTab);

    // -----------------------------------------------------------------------
    // 4. Verify swap page loaded
    // -----------------------------------------------------------------------
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('swap_from_amount_field')),
      timeout: const Duration(seconds: 10),
    );

    // Key UI elements should be present.
    expect(
      find.byKey(const Key('swap_from_amount_field')),
      findsOneWidget,
      reason: 'from amount field should be visible',
    );
    expect(
      find.byKey(const Key('swap_submit_button')),
      findsOneWidget,
      reason: 'swap submit button should be visible',
    );

    // The button should be disabled because no amount has been entered.
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('swap_submit_button')),
    );
    expect(button.onPressed, isNull,
        reason: 'swap button should be disabled when no amount entered');

    // -----------------------------------------------------------------------
    // 5. Verify wallet info is shown instead of chain selector
    // -----------------------------------------------------------------------
    // The wallet info card should show the wallet name.
    expect(
      find.text('Smoke Test Wallet'),
      findsWidgets,
      reason: 'wallet name should be visible on swap page',
    );
  });
}
