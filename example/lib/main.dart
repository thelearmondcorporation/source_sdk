import 'package:flutter/material.dart';
import 'package:source_sdk/source_sdk.dart';

/// Example entrypoint for the Source SDK example app.
///
/// This `main` boots a minimal Flutter app that demonstrates embedding the
/// `Source.instance.present(...)` QR widget. It's intended for local testing
/// and examples only.
void main() {
  runApp(const ExampleApp());
}

/// Minimal app wrapper used by the example.
///
/// Presents the `ExamplePage` which hosts the SDK QR widget.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Source SDK Example', home: const ExamplePage());
  }
}

/// Page demonstrating how to embed the `Source` QR widget.
class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  // For the demo we use a fixed 32-char raw key. In production use a
  // securely generated/shared key or let the SDK create and persist one.
  final String demoKey = '01234567890123456789012345678901';

  // Round-trip encryption is handled by the SDK internally when rendering the QR.
  // This example intentionally does not perform encryption itself.

  @override
  Widget build(BuildContext context) {
    final tx = TransactionInfo(
      accountId: 'acct_demo_123',
      lineItems: [
        LineItem(
          id: 'sku-1',
          name: 'T-Shirt',
          quantity: 1,
          unitAmount: 1000,
          currency: 'USD',
        ),
      ],
      amount: 1250,
      currency: 'USD',
      reference: 'order_1234',
    );

    final sdkConfig = SourceSDKConfig(
      accountId: tx.accountId,
      merchantName: 'Demo Store',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Source SDK Example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Embed the QR produced by the SDK. Pass `encryptionKey` so the example
            // can reproduce and decode the payload deterministically.
            Source.instance.present(
              transaction: tx,
              encryptionKey: demoKey,
              sdkConfig: sdkConfig,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
