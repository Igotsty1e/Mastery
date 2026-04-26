import 'package:flutter/foundation.dart' show kIsWeb;

import '../config.dart';

/// Resolves a backend-relative asset path (audio clip, image) to an absolute
/// URL the browser/native runtime can fetch.
///
/// On web the build script mirrors `backend/public/{audio,images}/` into the
/// SPA bundle so we serve same-origin paths and avoid canvaskit's
/// cross-origin canvas-tainting trap. On native we prefix with the configured
/// API base URL.
String resolveAssetUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  if (kIsWeb) {
    return url.startsWith('/') ? url : '/$url';
  }
  final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  final tail = url.startsWith('/') ? url : '/$url';
  return '$base$tail';
}
