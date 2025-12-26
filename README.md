Source SDK

## Installation

Add to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  source_sdk: ^0.1.0
```

Run:

```bash
flutter pub get
```

## Usage

Import the package:

```dart
import 'package:source_sdk/source_sdk.dart';
```

Create a `TransactionInfo` and embed the QR widget:

```dart
final tx = TransactionInfo(
  accountId: 'your_account_id',
  lineItems: [
    LineItem(id: 'li-1', name: 'Example item', quantity: 1, unitAmount: 1000, currency: 'USD'),
  ],
  amount: 1000, // smallest currency unit
  currency: 'USD',
  reference: 'order_123',
);

Widget build(BuildContext context) {
  return Source.instance.present(transaction: tx);
}
```

Optionally provide an `encryptionKey` (raw 32-char, 64-hex, or base64-encoded 32 bytes):

```dart
Source.instance.present(transaction: tx, encryptionKey: 'BASE64_OR_HEX_OR_32_CHAR_KEY');
```

To decrypt a payload on the platform or server, use the static helper:

```dart
final result = Source.platformDecrypt(payloadString, encryptionKey);
final transaction = result['transaction'] as TransactionInfo;
final merchant = result['merchant'] as Map<String, dynamic>;
```

## LICENSE
MIT

## Author

The Learmond Corporation
