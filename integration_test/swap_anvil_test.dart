import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_wallet/wallet.dart';
import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// Mock aggregator for Anvil-based testing
// ---------------------------------------------------------------------------

class AnvilMockDexAggregator implements DexAggregator {
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
    // For 0.1 ETH → 280 USDC: toAmount = input * 2800 / 10^12
    // (ETH has 18 decimals, USDC has 6 decimals, price = 2800)
    final input = BigInt.tryParse(request.amount.toString()) ?? BigInt.zero;
    final toAmount = input * BigInt.from(2800) ~/ BigInt.parse('1000000000000');
    return QuoteResult(
      fromToken: request.fromToken,
      toToken: request.toToken,
      fromAmount: request.amount.toString(),
      toAmount: toAmount.toString(),
      price: 2800,
      priceImpact: 0.05,
      estimatedGas: '21000',
    );
  }

  @override
  Future<SwapTransaction> buildSwapTx(SwapRequest request) async {
    return SwapTransaction(
      chain: request.chain,
      to: '0x000000000000000000000000000000000000dEaD',
      data: '0x',
      value: request.amount.toString(),
      gasLimit: 21000,
    );
  }

  @override
  Future<ApprovalTransaction> buildApprovalTx(ApprovalRequest request) async {
    return ApprovalTransaction(
      chain: request.chain,
      to: request.token,
      data:
          '0x095ea7b3000000000000000000000000${request.spender.substring(2)}',
      gasLimit: 50000,
    );
  }
}

// ---------------------------------------------------------------------------
// Anvil JSON-RPC helper
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> _callAnvilRpc(
  String url,
  String method, [
  List<dynamic>? params,
]) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params ?? [],
      'id': 1,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      throw Exception(
        'Anvil RPC error for $method: ${decoded['error']}',
      );
    }
    return decoded;
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

void main() {
  configureIntegrationTest();

  const anvilRpcUrl = String.fromEnvironment(
    'ANVIL_RPC_URL',
    defaultValue: 'http://127.0.0.1:8545',
  );
  const anvilChainId = '31337';
  final launchedUrls = <String>[];

  setUp(() async {
    await captureExternalLaunchUrls(launchedUrls);
  });

  tearDown(() async {
    await stopCapturingExternalLaunchUrls();
  });

  testWidgets('swap with Anvil simulator', (tester) async {

    // -----------------------------------------------------------------------
    // 1. Launch app and import wallet
    // -----------------------------------------------------------------------
    await launchTestApp();

    // Import a wallet with a known mnemonic so we can predict the ETH address
    // and fund it on Anvil.
    await importWalletFromHome(
      tester,
      walletName: 'Anvil Test Wallet',
      mnemonic: kValidImportMnemonic,
    );
    await chooseViewWalletFromPostImportPrompt(tester);
    await expectWalletHome(tester, walletName: 'Anvil Test Wallet');

    // -----------------------------------------------------------------------
    // 2. Add custom EVM network pointing to the local Anvil instance
    // -----------------------------------------------------------------------
    // We must add it as a custom network first so the HD-wallet-add page and
    // the swap status page's EvmChainConfigResolver can find it.
    await CustomEvmNetworkService.validateAndSave(
      name: 'Anvil Local',
      shortName: 'Anvil',
      chainId: anvilChainId,
      rpcUrl: anvilRpcUrl,
      nativeSymbol: 'ETH',
      isTestnet: true,
    );

    // -----------------------------------------------------------------------
    // 3. Register mock aggregator before the swap page initialises
    // -----------------------------------------------------------------------
    // The swap page's _initAggregator() only registers OKX/Jupiter when
    // registeredTypes.isEmpty. By registering our mock first, the guard
    // skips registration, and _resolveAggregator() falls back to our mock.
    DexAggregatorRegistry.register(AnvilMockDexAggregator());

    // -----------------------------------------------------------------------
    // 4. Add HD wallet for the Anvil chain
    // -----------------------------------------------------------------------
    await openWalletDetailFromHome(tester);
    await expectTextVisible(tester, '钱包详情');
    await openHdManageFromWalletDetail(tester);
    await expectTextVisible(tester, '添加钱包');
    await openAddWalletFromHdManage(tester);
    await expectTextVisible(tester, '添加钱包');

    // addHdWalletByChainId scrolls to the chain tile, taps it, creates a
    // sub-wallet, and enters the password.
    await addHdWalletByChainId(
      tester,
      chainId: anvilChainId,
      password: 'Passw0rd!',
    );
    await pumpUntilWalletHomeReady(tester);

    // -----------------------------------------------------------------------
    // 5. Fund the wallet on Anvil
    // -----------------------------------------------------------------------
    final provider = WalletProvider.getInstance();
    expect(provider, isNotNull);
    final wallet = provider!.currentWallet;
    expect(wallet, isNotNull);
    expect(wallet!.chainId, anvilChainId);

    final address = wallet.defaultAddress?.address;
    expect(address, isNotNull);
    debugPrint('Funding Anvil wallet at $address');

    // 100 ETH in wei (hex)
    const hundredEthHex = '0x56BC75E2D63100000';
    await _callAnvilRpc(anvilRpcUrl, 'anvil_setBalance', [
      address,
      hundredEthHex,
    ]);

    // Trigger block production so the balance change is visible immediately.
    await _callAnvilRpc(anvilRpcUrl, 'anvil_mine');

    // -----------------------------------------------------------------------
    // 6. Wait for wallet balance to sync
    // -----------------------------------------------------------------------
    await waitForCurrentWalletNativeAssetBalanceGreaterThanZeroForChain(
      tester,
      chainId: anvilChainId,
    );
    debugPrint('Wallet funded successfully');

    // -----------------------------------------------------------------------
    // 7. Navigate to swap tab
    // -----------------------------------------------------------------------
    final swapTab = find.byKey(const Key('bottom_nav_swap'));
    await pumpUntilVisible(tester, swapTab);
    await tapAndPump(tester, swapTab);

    // Wait for the swap page to load and render the from amount field.
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('swap_from_amount_field')),
      timeout: const Duration(seconds: 10),
    );

    // -----------------------------------------------------------------------
    // 8. Enter swap amount
    // -----------------------------------------------------------------------
    // The mock aggregator's getTokens returned ETH as the default fromToken.
    // Enter 0.1 ETH to trigger a quote fetch.
    await tester.enterText(
      find.byKey(const Key('swap_from_amount_field')),
      '0.1',
    );
    await unfocusAndPump(tester);

    // -----------------------------------------------------------------------
    // 9. Wait for quote result
    // -----------------------------------------------------------------------
    // After the debounce (300 ms) the mock aggregator returns a quote.
    // Wait for the swap submit button to become enabled (pageState == quoteReady).
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('swap_submit_button')),
      timeout: const Duration(seconds: 10),
    );

    // Give the quote time to appear and the page state to update.
    await tester.pump(const Duration(seconds: 2));

    // -----------------------------------------------------------------------
    // 10. Confirm swap — the SwapConfirmSheet is shown as an AlertDialog
    // -----------------------------------------------------------------------
    final submitButton = find.byKey(const Key('swap_submit_button'));
    expect(submitButton, findsOneWidget);
    await scrollToAndTap(tester, submitButton);

    // Wait for the confirm AlertDialog to appear.
    await pumpUntilVisible(
      tester,
      find.byType(AlertDialog),
      timeout: const Duration(seconds: 5),
    );

    // Tap the "兑换" (Swap) confirm button inside the dialog.
    final confirmButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '兑换'),
    );
    expect(confirmButton, findsOneWidget);
    await tapAndPump(tester, confirmButton);

    // -----------------------------------------------------------------------
    // 11. Enter password
    // -----------------------------------------------------------------------
    await expectPasswordVerificationDialogVisible(tester);
    await unlockPasswordPrompt(tester);

    // -----------------------------------------------------------------------
    // 12. Wait for swap completion
    // -----------------------------------------------------------------------
    // The swap status page shows progress steps. Wait for the "完成" (Done)
    // button which appears when _currentStep == _TxStep.completed.
    final doneText = find.text('完成');
    await pumpUntilVisible(
      tester,
      doneText,
      timeout: const Duration(seconds: 60),
    );
    debugPrint('Swap completed successfully');

    // -----------------------------------------------------------------------
    // 13. Verify the swap completed and return to the main page
    // -----------------------------------------------------------------------
    // Tap "完成" to pop back to the swap page.
    await tapAndPump(tester, doneText);

    // Return to wallet home by switching to the home tab.
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('bottom_nav_home')),
      timeout: const Duration(seconds: 5),
    );
    await tapAndPump(tester, find.byKey(const Key('bottom_nav_home')));
    await pumpUntilWalletHomeReady(tester);

    // Verify the wallet still has a balance on the Anvil chain (some ETH
    // was consumed as gas, but most of the 100 ETH should remain).
    final remainingBalance = await waitForCurrentWalletNativeAssetBalanceGreaterThanZeroForChain(
      tester,
      chainId: anvilChainId,
    );
    debugPrint('Remaining balance on Anvil: $remainingBalance ETH');
  });
}
