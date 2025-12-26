import 'dart:convert';
import 'dart:math';
import 'src/api_base.dart';
export 'src/source_sdk_config.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'src/source_sdk_config.dart';

/// Source SDK
///
/// Overview:
/// - Generates AES-256-CBC encrypted payloads containing `transaction` and
///   `merchant` objects. Payload bytes are IV (16) + ciphertext and encoded
///   using base64url for transport inside the QR.
/// - `Source.instance.present(...)` returns an embeddable `Widget` that renders
///   a QR encoding the AES-encrypted payload (the `merchant` + `transaction`).
///   For convenience the encrypted payload is placed inside a web URL wrapper
///   so users without the Source app can open the page on the web; tapping
///   the provided action attempts the app-scheme URI first and otherwise opens
///   the web URL.
/// - You can provide an `encryptionKey`, or the SDK will generate a secure
///   32-byte key and persist it.

/// Simple transaction model used in payloads.
/// Line item model describing individual purchasable items.
class LineItem {
  final String id;
  final String name;
  final int quantity;
  final int unitAmount; // in smallest currency unit
  final String? currency;
  final Map<String, dynamic>? metadata;

  LineItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitAmount,
    this.currency,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'unitAmount': unitAmount,
    if (currency != null) 'currency': currency,
    'metadata': metadata ?? {},
  };

  static LineItem fromJson(Map<String, dynamic> j) => LineItem(
    id: j['id'] as String,
    name: j['name'] as String,
    quantity: j['quantity'] as int,
    unitAmount: j['unitAmount'] as int,
    currency: j['currency'] as String?,
    metadata: Map<String, dynamic>.from(j['metadata'] ?? {}),
  );
}

class TransactionInfo {
  final String accountId;
  final String? merchantWallet;
  final List<LineItem>? lineItems;
  final int amount; // in smallest currency unit (e.g., cents)
  final String currency;
  final String reference;
  final Map<String, dynamic>? metadata;

  TransactionInfo({
    required this.accountId,
    this.merchantWallet,
    this.lineItems,
    required this.amount,
    required this.currency,
    required this.reference,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    if (merchantWallet != null) 'merchantWallet': merchantWallet,
    if (lineItems != null)
      'lineItems': lineItems!.map((e) => e.toJson()).toList(),
    'amount': amount,
    'currency': currency,
    'reference': reference,
    'metadata': metadata ?? {},
  };

  static TransactionInfo fromJson(Map<String, dynamic> j) => TransactionInfo(
    accountId: j['accountId'] as String,
    merchantWallet: j['merchantWallet'] as String?,
    lineItems: (j['lineItems'] as List?)
        ?.map((e) => LineItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    amount: j['amount'] as int,
    currency: j['currency'] as String,
    reference: j['reference'] as String,
    metadata: Map<String, dynamic>.from(j['metadata'] ?? {}),
  );
}

/// The Source SDK singleton.
class Source {
  Source._private();
  static final Source instance = Source._private();

  // Secure storage instance for storing per-merchant encryption keys.
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Configuration is stored in `SourceSDKConfig.current`.

  /// Return a widget that renders a QR containing the encrypted payload.
  /// If `encryptionKey` is null the SDK will generate and persist a 32-byte key.
  Widget present({
    required TransactionInfo transaction,
    String? encryptionKey,

    /// Optional SDK config: if provided, the SDK will be configured with these
    /// values before rendering the QR. This lets merchants call `present()`
    /// once to both configure the SDK and render the QR.
    SourceSDKConfig? sdkConfig,

    /// App custom scheme prefix (used when attempting to open the app directly)
    String appSchemePrefix = 'source://pay?payload=',

    /// Optional web base URL (used as the QR content so scanners open the web page if the app is not installed)
    /// If omitted the SDK will choose a sensible default depending on platform
    /// and environment (dev vs production). Use `SourceSDKConfig.webBaseUrl`
    /// to override globally.
    String? webBase,
    double qrSize = 220,
  }) {
    // Apply provided SDK config (optional).
    if (sdkConfig != null) SourceSDKConfig.configure(sdkConfig);

    Widget buildWithKey(String key) {
      // If the merchant configured an account id via `SourceSDKConfig.configure`, prefer
      // that account id for the payload. This ensures merchants only need to
      // provide their Source `accountId` once.
      final cfg = SourceSDKConfig.current;
      final txForPayload = cfg == null
          ? transaction
          : TransactionInfo(
              accountId: cfg.accountId,
              merchantWallet: cfg.merchantWallet ?? transaction.merchantWallet,
              amount: transaction.amount,
              currency: transaction.currency,
              reference: transaction.reference,
              metadata: transaction.metadata,
            );
      final resolvedMerchantWallet =
          cfg?.merchantWallet ?? txForPayload.merchantWallet;
      final merchantInfo = {
        'accountId': cfg?.accountId ?? txForPayload.accountId,
        if (resolvedMerchantWallet != null)
          'merchantWallet': resolvedMerchantWallet,
        'merchantName': cfg?.merchantName,
      };

      final payloadMap = {
        'transaction': txForPayload.toJson(),
        'merchant': merchantInfo,
      };

      final payload = jsonEncode(payloadMap);
      final encrypted = _encryptPayload(payload, key);
      final encoded = base64UrlEncode(encrypted);
      final encodedParam = Uri.encodeComponent(encoded);

      // Resolve web base: precedence is parameter -> SDK config -> auto default
      final resolvedBase =
          webBase ??
          SourceSDKConfig.current?.webBaseUrl ??
          resolveDefaultWebBase();

      // Build web URL: append the payload as a proper query parameter.
      final webUri = resolvedBase.contains('?')
          ? '$resolvedBase&payload=$encodedParam'
          : '$resolvedBase?payload=$encodedParam';

      // The app URI uses the custom scheme — encode the payload component.
      final appUri = '$appSchemePrefix${Uri.encodeComponent(encoded)}';

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(data: webUri, size: qrSize),
          const SizedBox(height: 12),
          // Hide the raw payload by default. Provide a small action to copy the link instead.
          Builder(
            builder: (ctx) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(ctx);
                      await Clipboard.setData(ClipboardData(text: webUri));
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy link'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      await _openAppOrWeb(
                        Uri.parse(appUri),
                        Uri.parse(webUri),
                        ctx,
                      );
                    },
                    child: const Text('Open in Source app'),
                  ),
                ],
              );
            },
          ),
        ],
      );
    }

    // If caller provided a key, render immediately. Otherwise fetch/create one and render when ready.
    if (encryptionKey != null) {
      return buildWithKey(encryptionKey);
    }

    return FutureBuilder<String>(
      future: _getOrCreateEncryptionKey(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 220,
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || snap.data == null) {
          return const Text('Failed to obtain encryption key');
        }
        return buildWithKey(snap.data!);
      },
    );
  }

  /// Helper: constructs a 32-byte key from the provided string.
  /// Accepts raw-32, hex-64 or base64 variants.
  Uint8List _normalizeKey(String key) {
    // hex 64 chars
    final hexReg = RegExp(r'^[0-9a-fA-F]{64}\$');
    if (hexReg.hasMatch(key)) {
      final bytes = <int>[];
      for (var i = 0; i < key.length; i += 2) {
        bytes.add(int.parse(key.substring(i, i + 2), radix: 16));
      }
      return Uint8List.fromList(bytes);
    }

    try {
      final b = base64Decode(key);
      if (b.length == 32) return Uint8List.fromList(b);
    } catch (_) {}

    // raw string
    final utf = utf8.encode(key);
    if (utf.length == 32) return Uint8List.fromList(utf);

    throw ArgumentError(
      'encryptionKey must be 32 raw chars, 64-hex, or base64-encoded 32 bytes',
    );
  }

  /// Encrypts JSON payload with AES-256-CBC and returns bytes = iv + ciphertext.
  Uint8List _encryptPayload(String jsonPayload, String encryptionKey) {
    final keyBytes = _normalizeKey(encryptionKey);
    final key = encrypt_pkg.Key(keyBytes);
    final iv = encrypt_pkg.IV.fromSecureRandom(16);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );
    final encrypted = encrypter.encrypt(jsonPayload, iv: iv);
    final out = <int>[];
    out.addAll(iv.bytes);
    out.addAll(encrypted.bytes);
    return Uint8List.fromList(out);
  }

  // Generate a cryptographically secure 32-byte key.
  Uint8List _generateKeyBytes() {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
  }

  String _bytesToBase64(Uint8List b) => base64UrlEncode(b);

  // Default web base resolution moved to `lib/src/api_base.dart`.

  // Read the stored encryption key (base64) or generate and persist one.
  Future<String> _getOrCreateEncryptionKey() async {
    const storageKey = 'source_encryption_key';
    final existing = await _secureStorage.read(key: storageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final keyBytes = _generateKeyBytes();
    final encoded = _bytesToBase64(keyBytes);
    await _secureStorage.write(key: storageKey, value: encoded);
    return encoded;
  }

  /// Decode payload produced by `present` and return TransactionInfo.
  /// [payload] may be the full uri like "source://pay?payload=..." or raw base64url string.
  TransactionInfo decodePayload(String payload, String encryptionKey) {
    String encoded = payload;
    final uriIndex = payload.indexOf('payload=');
    if (uriIndex >= 0) {
      encoded = payload.substring(uriIndex + 'payload='.length);
    }
    final bytes = base64Url.decode(encoded);
    if (bytes.length < 17) throw ArgumentError('invalid payload');
    final iv = encrypt_pkg.IV(bytes.sublist(0, 16));
    final cipher = bytes.sublist(16);
    final keyBytes = _normalizeKey(encryptionKey);
    final key = encrypt_pkg.Key(keyBytes);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );
    final decrypted = encrypter.decrypt(encrypt_pkg.Encrypted(cipher), iv: iv);
    final map = jsonDecode(decrypted) as Map<String, dynamic>;
    // Support both legacy payloads (transaction only) and new wrapped payloads
    if (map.containsKey('transaction')) {
      final txMap = Map<String, dynamic>.from(map['transaction'] as Map);
      return TransactionInfo.fromJson(txMap);
    }
    return TransactionInfo.fromJson(map);
  }

  /// Decode payload and return both TransactionInfo and merchant info (if present).
  /// Returns a map with keys: `transaction` (TransactionInfo) and `merchant` (Map).
  Map<String, dynamic> decodePayloadWithMerchant(
    String payload,
    String encryptionKey,
  ) {
    String encoded = payload;
    final uriIndex = payload.indexOf('payload=');
    if (uriIndex >= 0) {
      encoded = payload.substring(uriIndex + 'payload='.length);
    }
    final bytes = base64Url.decode(encoded);
    if (bytes.length < 17) throw ArgumentError('invalid payload');
    final iv = encrypt_pkg.IV(bytes.sublist(0, 16));
    final cipher = bytes.sublist(16);
    final keyBytes = _normalizeKey(encryptionKey);
    final key = encrypt_pkg.Key(keyBytes);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );
    final decrypted = encrypter.decrypt(encrypt_pkg.Encrypted(cipher), iv: iv);
    final map = jsonDecode(decrypted) as Map<String, dynamic>;
    if (map.containsKey('transaction')) {
      final txMap = Map<String, dynamic>.from(map['transaction'] as Map);
      final merchantMap = Map<String, dynamic>.from(map['merchant'] ?? {});
      return {
        'transaction': TransactionInfo.fromJson(txMap),
        'merchant': merchantMap,
      };
    }
    return {
      'transaction': TransactionInfo.fromJson(map),
      'merchant': <String, dynamic>{},
    };
  }

  /// Platform-facing API: decrypt a payload and return a Map with keys
  /// `transaction` and `merchant`. This is a simple entry point the Source
  /// platform can call directly without needing to reimplement decryption.
  ///
  /// Example:
  /// final result = Source.platformDecrypt(payload, encryptionKey);
  static Map<String, dynamic> platformDecrypt(
    String payload,
    String encryptionKey,
  ) {
    return instance.decodePayloadWithMerchant(payload, encryptionKey);
  }

  /// Convenience helper to call Source pay API.
  /// Merchant/backend should perform real authenticated transfers; this is a simple client helper.
  Future<http.Response> payWithApi({
    required Uri endpoint,
    required String bearerToken,
    required TransactionInfo tx,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $bearerToken',
      ...?extraHeaders,
    };
    final body = jsonEncode(tx.toJson());
    final res = await http.post(endpoint, headers: headers, body: body);
    return res;
  }

  /// Helper to attempt opening the Source app using the payload URI if the device has a handler.
  Future<void> _openAppOrWeb(Uri appUri, Uri webUri, BuildContext ctx) async {
    // Try launching the app URI using the platform default; some platforms
    // behave better with `platformDefault` while others need
    // `externalApplication`. Test both and fall back to the web URL.
    bool launched = false;

    try {
      launched = await launchUrl(appUri, mode: LaunchMode.platformDefault);
    } catch (_) {
      launched = false;
    }

    if (!launched) {
      try {
        launched = await launchUrl(
          appUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        launched = false;
      }
    }

    if (launched) return;

    // App launch failed — try opening the web fallback.
    try {
      final webLaunched = await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
      if (webLaunched) return;
    } catch (_) {}

    // If we reach here nothing could be opened. Provide user feedback.
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Unable to open app or web URL')),
      );
    } catch (_) {}
  }
}
