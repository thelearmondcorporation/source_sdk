# Source SDK — Instructions

This document explains how to integrate and use the Source SDK to generate encrypted QR payloads for Source wallet payments.

## Quick overview
- The SDK exposes `Source.instance.present(...)` which returns an embeddable Widget that renders a QR containing an AES-256-CBC encrypted payload.
- Payload shape: `{ "transaction": {..., "lineItems": [{ "id","name","quantity","unitAmount","currency" }] }, "merchant": { "accountId", "merchantWallet" (optional), "merchantName" } }`.
- Encrypted bytes layout: 16-byte IV followed by ciphertext; the result is encoded using base64url for transport.

## Installation
Add the package to your `pubspec.yaml`. If using this repo locally, add as a path dependency:

```yaml
dependencies:
  source_sdk: 1.0.0+1
```

Then run:

```bash
flutter pub get
```

## Basic usage

Example embedding the QR widget in your app, frontend, or UI:

```dart
final tx = TransactionInfo(
  accountId: 'acct_live_abc',
  lineItems: [
    LineItem(id: 'li-1', name: 'Example item', quantity: 1, unitAmount: 1250, currency: 'USD'),
  ], // dynamically pass line items to TransactionInfo
  currency: 'USD',
  reference: 'Order #1234',
);

final sdkConfig = SourceSDKConfig(
  accountId: 'acct_live_abc',
  merchantName: 'Acme Store',
);

Widget build(BuildContext context) {
  return Source.instance.present(
    transaction: tx,
    sdkConfig: sdkConfig,
  );
}
```

`encryptionKey` is optional. If omitted, the SDK generates a secure 32-byte key, stores it in platform secure storage under the key `source_encryption_key`, and reuses it.

If you want to provide a pre-shared key (for server decryption), pass `encryptionKey` as one of the supported formats:
- raw 32-byte string
- 64-char hex string
- base64/base64url encoded 32 bytes
