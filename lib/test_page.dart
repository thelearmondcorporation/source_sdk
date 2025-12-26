import 'package:flutter/material.dart';
import 'source_sdk.dart';

/// Simple test page that shows the encrypted QR for a sample transaction.
class SourceTestPage extends StatelessWidget {
  const SourceTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tx = TransactionInfo(
      accountId: 'merchant_abc',
      lineItems: [
        LineItem(id: 'li-1', name: 'Widget', quantity: 2, unitAmount: 999, currency: 'USD'),
      ],
      amount: 1999,
      currency: 'USD',
      reference: 'order_test_001',
    );

    // Example 32-character raw key for local testing only.
    const testKey = '01234567890123456789012345678901';

    return Scaffold(
      appBar: AppBar(title: const Text('Source SDK — QR Test')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            const Text('Scan this QR with the Source app'),
            const SizedBox(height: 12),
            // Embed the QR widget produced by the SDK (smaller size)
            Center(child: Source.instance.present(transaction: tx, encryptionKey: testKey, qrSize: 148.334345)),
            const SizedBox(height: 24),
              const Text('Payload is hidden for security. Use Copy link to share.'),
            const SizedBox(height: 8),
            // Show the raw payload as a convenience for testing
          ],
        ),
      ),
    );
  }
}
