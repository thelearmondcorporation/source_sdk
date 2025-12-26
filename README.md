Source SDK

## Overview
Source SDK provides a small, embeddable Flutter widget that generates an
AES-256-CBC encrypted QR payload (IV + ciphertext, base64url encoded) that communicates with the Source Api.

## Key Points
- Widget-only SDK: it renders an encrypted QR and exposes decryption helpers.
- Payload contains `transaction` and `merchant` objects; `transaction` may
  include `lineItems`.
- Encryption: AES-256-CBC with a 16-byte IV prepended; key is 32 bytes.

## Getting Started

### 1) Add the package

Add to your `pubspec.yaml`:

```yaml
dependencies:
  source_sdk: ^1.0.0
```

Then fetch dependencies:

```bash
flutter pub get
```

### 2) Import and render the QR

```dart
import 'package:source_sdk/source_sdk.dart';

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

Widget build(BuildContext context) {
  return Source.instance.present(
    transaction: tx,
    sdkConfig: sdkConfig,
    // optional: pass `encryptionKey` to control encryption, otherwise
    // the SDK will generate and persist a key securely for you.
    // encryptionKey: '01234567890123456789012345678901',
  );
}
```
 
### 3) Next steps (integration checklist)

Use this short checklist to finish integrating and testing the SDK in your app:

- Add `Source.instance.present(...)` to a screen in your app and run the
  example to verify the QR renders.
- Scan the QR with a trusted scanner or the `example/` app to confirm the app integration opens correctly.
- Verify `SourceSDKConfig` (set `accountId` / `merchantName`) and optionally
- Run `flutter analyze` and `flutter test` in your project to validate
  integration.


## Notes
- `SourceSDKConfig` can be used to set `accountId`, `merchantName`, and `merchantInfo`.
- The example app in `example/` demonstrates full integration.


## License

MIT

## Author

The Learmond Corporation
