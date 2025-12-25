import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Simple transaction model used in payloads.
class TransactionInfo {
  final String merchantId;
  final String merchantWallet;
  final int amount; // in smallest currency unit (e.g., cents)
  final String currency;
  final String reference;
  final Map<String, dynamic>? metadata;

  TransactionInfo({
    required this.merchantId,
    required this.merchantWallet,
    required this.amount,
    required this.currency,
    required this.reference,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'merchantId': merchantId,
        'merchantWallet': merchantWallet,
        'amount': amount,
        'currency': currency,
        'reference': reference,
        'metadata': metadata ?? {},
      };

  static TransactionInfo fromJson(Map<String, dynamic> j) => TransactionInfo(
        merchantId: j['merchantId'] as String,
        merchantWallet: j['merchantWallet'] as String,
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

  /// Presents a modal containing a 256-bit encrypted QR code for the given transaction.
  ///
  /// [encryptionKey] must be a 32-byte key supplied as either a raw 32-char string,
  /// a 64-char hex string, or a base64 key. This method will assert if the key cannot
  /// be parsed to 32 bytes.
  /// Returns a widget that renders the encrypted QR for embedding on a merchant page.
  ///
  /// Use `Source.instance.present(transaction: tx, encryptionKey: key)` directly in
  /// your widget tree to show the QR; it will not open a modal.
  Widget present({
    required TransactionInfo transaction,
    required String encryptionKey,
    /// App custom scheme prefix (used when attempting to open the app directly)
    String appSchemePrefix = 'source://pay?payload=',
    /// Fallback web URL base (used as the QR content so scanners open the web page if the app is not installed)
    String fallbackWebBase = 'https://www.thelearmondcorporation.com/source/app/pay?payload=',
    double qrSize = 220,
  }) {
    final payload = jsonEncode(transaction.toJson());
    final encrypted = _encryptPayload(payload, encryptionKey);
    final encoded = base64UrlEncode(encrypted);

    // The QR contains the fallback web URL — scanning devices without app will open the web page.
    final webUri = '$fallbackWebBase$encoded';
    // The app URI uses the custom scheme — we'll try to open this first when user taps button
    final appUri = '$appSchemePrefix$encoded';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        QrImageView(
          data: webUri,
          size: qrSize,
        ),
        const SizedBox(height: 12),
        // Hide the raw payload by default. Provide a small action to copy the link instead.
        Builder(builder: (ctx) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(ctx);
                        await Clipboard.setData(ClipboardData(text: webUri));
                        messenger.showSnackBar(const SnackBar(content: Text('Link copied')));
                      },
                icon: const Icon(Icons.copy),
                label: const Text('Copy link'),
              ),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: () async {
                    if (kIsWeb) {
                      final messenger = ScaffoldMessenger.of(ctx);
                      final navigator = Navigator.of(ctx);
                      // ignore: use_build_context_synchronously
                      final token = await Source.instance.showLoginBottomSheet(navigator.context);
                      if (token == null) return;
                      try {
                        final decoded = Source.instance.decodePayload('payload=$encoded', encryptionKey);
                        await Source.instance.showPaysheetBottomSheet(navigator.context, decoded, (tx) async {
                          final res = await Source.instance.payWithApi(
                              endpoint: Uri.parse('https://www.thelearmondcorporation.com/source/app/pay'),
                              bearerToken: token,
                              tx: tx);
                          return res.statusCode == 200;
                        });
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text('Invalid payload: $e')));
                      }
                    } else {
                      await _openAppOrWeb(Uri.parse(appUri), Uri.parse(webUri));
                    }
                  },
                  child: const Text('Open in Source app')),
            ],
          );
        }),
      ],
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

    throw ArgumentError('encryptionKey must be 32 raw chars, 64-hex, or base64-encoded 32 bytes');
  }

  /// Encrypts JSON payload with AES-256-CBC and returns bytes = iv + ciphertext.
  Uint8List _encryptPayload(String jsonPayload, String encryptionKey) {
    final keyBytes = _normalizeKey(encryptionKey);
    final key = encrypt_pkg.Key(keyBytes);
    final iv = encrypt_pkg.IV.fromSecureRandom(16);
    final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc));
    final encrypted = encrypter.encrypt(jsonPayload, iv: iv);
    final out = <int>[];
    out.addAll(iv.bytes);
    out.addAll(encrypted.bytes);
    return Uint8List.fromList(out);
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
    final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc));
    final decrypted = encrypter.decrypt(encrypt_pkg.Encrypted(cipher), iv: iv);
    final map = jsonDecode(decrypted) as Map<String, dynamic>;
    return TransactionInfo.fromJson(map);
  }

  /// Present a simple paysheet for Source-app style integration.
  /// This is intended for the Source app: it decodes the payload, shows the transaction
  /// and calls [onPay] when the user confirms. [onPay] should perform the actual
  /// server-side payment call and return true on success.
  /// Present a simple paysheet for Source-app style integration.
  /// This is intended for the Source app: it decodes the payload, shows the transaction
  /// and calls [onPay] when the user confirms. [onPay] should perform the actual
  /// server-side payment call and return true on success.
  ///
  /// If [paysheetLauncher] is provided it will be used to present the paysheet UI
  /// (for example, using the `paysheet` package). If not provided the SDK falls
  /// back to a simple built-in dialog.
  Future<void> presentPaysheetFromPayload(BuildContext context,
      {required String payload,
      required String encryptionKey,
      required Future<bool> Function(TransactionInfo tx) onPay,
      Future<bool> Function(BuildContext context, TransactionInfo tx)? paysheetLauncher}) async {
    final tx = decodePayload(payload, encryptionKey);

    if (paysheetLauncher != null) {
      // If the host app provided a paysheet launcher (likely using the `paysheet` package), use it.
      await paysheetLauncher(context, tx);
      return;
    }

    // Fallback: simple dialog
    await showDialog(
        context: context,
        builder: (ctx) {
          var loading = false;
          return StatefulBuilder(builder: (c, setState) {
            return AlertDialog(
              title: const Text('Confirm Payment'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Merchant: ${tx.merchantId}'),
                  Text('Amount: ${tx.amount} ${tx.currency}'),
                  Text('Reference: ${tx.reference}'),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: loading ? null : () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: loading
                    ? null
                    : () async {
                      final navigator = Navigator.of(ctx);
                      setState(() => loading = true);
                      final ok = await onPay(tx);
                      setState(() => loading = false);
                      if (ok && navigator.mounted) navigator.pop();
                      },
                  child: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Pay')),
              ],
            );
          });
        });
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
  Future<void> _openAppOrWeb(Uri appUri, Uri webUri) async {
    // Try to open the app custom scheme first
    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    // Otherwise open the web fallback (this page can deep link into the app or show instructions)
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Show a simple login bottom sheet (web fallback). Returns a session token (mock) or null.
  Future<String?> showLoginBottomSheet(BuildContext context) async {
    final emailCtl = TextEditingController();
    final passCtl = TextEditingController();
    return await showModalBottomSheet<String?>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sign in to Source', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(controller: emailCtl, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 8),
                  TextField(controller: passCtl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: () {
                        // In a real app, call your auth endpoint here. Return a session token.
                        Navigator.of(ctx).pop('demo_session_token');
                      },
                      child: const Text('Sign in')),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        });
  }

  /// Show an internal paysheet as a bottom sheet. Calls [onPay] to perform the payment.
  Future<void> showPaysheetBottomSheet(BuildContext context, TransactionInfo tx, Future<bool> Function(TransactionInfo) onPay) async {
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          var loading = false;
          return StatefulBuilder(builder: (c, setState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pay ${tx.amount} ${tx.currency}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Merchant: ${tx.merchantId}'),
                    Text('Reference: ${tx.reference}'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: loading
                              ? null
                              : () async {
                                  final navigator = Navigator.of(ctx);
                                  setState(() => loading = true);
                                  final ok = await onPay(tx);
                                  setState(() => loading = false);
                                  if (ok && navigator.mounted) navigator.pop();
                                },
                          child: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Pay')),
                      ],
                    ),
                  ],
                ),
              ),
            );
          });
        });
  }
}

/// Web landing page widget for the QR web fallback.
/// Put this in `source_sdk.dart` so the SDK exposes the web landing flow.
class WebLandingPage extends StatefulWidget {
  final String encryptionKey;

  const WebLandingPage({super.key, required this.encryptionKey});

  @override
  State<WebLandingPage> createState() => _WebLandingPageState();
}

class _WebLandingPageState extends State<WebLandingPage> {
  String? payloadEncoded;
  bool loggedIn = false;
  @override
  void initState() {
    super.initState();
    // Read payload from URL query param 'payload' (web)
    final q = Uri.base.queryParameters['payload'];
    payloadEncoded = q;
    // If payload exists, automatically prompt login and paysheet after first frame.
    if (payloadEncoded != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        // ignore: use_build_context_synchronously
        final token = await Source.instance.showLoginBottomSheet(navigator.context);
        if (token == null) return;
        if (!mounted) return;
        try {
          final decoded = Source.instance.decodePayload('payload=$payloadEncoded', widget.encryptionKey);
          await Source.instance.showPaysheetBottomSheet(navigator.context, decoded, (tx) async {
            final res = await Source.instance.payWithApi(
              endpoint: Uri.parse('https://www.thelearmondcorporation.com/source/app/pay'),
              bearerToken: token,
              tx: tx,
            );
            return res.statusCode == 200;
          });
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Invalid payload: $e')));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Source — Pay')), 
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Welcome to Source', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (payloadEncoded == null) const Text('No payment payload found.'),
            if (payloadEncoded != null) ...[
              const Text('A payment is ready. Sign in to continue.'),
              const SizedBox(height: 12),
                ElevatedButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  // show login
                  // ignore: use_build_context_synchronously
                  final token = await Source.instance.showLoginBottomSheet(navigator.context);
                  if (token != null) {
                    if (!mounted) return;
                    setState(() => loggedIn = true);
                    // decode payload and present paysheet bottom sheet
                    try {
                      final decoded = Source.instance.decodePayload('payload=$payloadEncoded', widget.encryptionKey);
                      await Source.instance.showPaysheetBottomSheet(navigator.context, decoded, (tx) async {
                        // call pay API — placeholder endpoint, replace with real backend
                        final res = await Source.instance.payWithApi(
                            endpoint: Uri.parse('https://api.thelearmondcorporation.com/pay'),
                            bearerToken: token,
                            tx: tx,
                        );
                        return res.statusCode == 200;
                      });
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Invalid payload: $e')));
                    }
                  }
                },
                child: const Text('Sign in and Pay'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
