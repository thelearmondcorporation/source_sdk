/// Merchant-provided SDK configuration.
///
/// Merchants should call `SourceSDKConfig.configure(...)` once during app
/// initialization to set their `accountId` and optional merchant info.
class SourceSDKConfig {
  /// The merchant's Source account id used when presenting QR payloads.
  final String accountId;

  /// Optional friendly merchant name for display in the paysheet UI.
  final String? merchantName;

  /// Optional merchant wallet identifier (if different from accountId).
  final String? merchantWallet;

  /// Optional web base URL to use for the QR fallback link (overrides SDK defaults).
  final String? webBaseUrl;

  const SourceSDKConfig({
    required this.accountId,
    this.merchantName,
    this.merchantWallet,
    this.webBaseUrl,
  });

  static SourceSDKConfig? _current;

  /// Configure the SDK with merchant-provided values. Call once at app init.
  static void configure(SourceSDKConfig config) => _current = config;

  /// Current SDK configuration or `null` if not configured.
  static SourceSDKConfig? get current => _current;

  /// Clears the in-memory configuration.
  static void clear() => _current = null;
}
