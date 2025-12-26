import 'dart:io';
import 'package:flutter/foundation.dart';

/// Resolve a sensible default web base URL for QR fallback links.
/// - In release builds this points to the production website.
/// - In debug/profile builds it returns an address suitable for emulators/simulators.
String resolveDefaultWebBase() {
  if (kReleaseMode) {
    return 'https://www.thelearmondcorporation.com/source/app/pay';
  }

  try {
    if (Platform.isAndroid) {
      // Android emulator default host forwarding to host machine
      return 'http://10.0.2.2:4000/source/app/pay';
    }
    if (Platform.isIOS) {
      // Use localhost on iOS simulator to avoid potential name-resolution
      // inconsistencies with `localhost` in some environments.
      return 'http://localhost:4000/source/app/pay';
    }
  } catch (_) {}

  return 'http://localhost:4000/source/app/pay';
}
