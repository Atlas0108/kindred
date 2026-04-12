import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Message for [compute] (must be a simple transferable type).
final class CoverImagePrepareMessage {
  const CoverImagePrepareMessage(this.raw, this.contentType);
  final Uint8List raw;
  final String contentType;
}

/// Top-level entry for [compute].
({Uint8List bytes, String contentType}) prepareCoverImageIsolateEntry(CoverImagePrepareMessage msg) {
  return prepareCoverImageForUpload(msg.raw, msg.contentType);
}

/// Runs [prepareCoverImageForUpload] off the UI isolate when possible.
Future<({Uint8List bytes, String contentType})> prepareCoverImageForUploadAsync(
  Uint8List raw,
  String contentType,
) async {
  try {
    return await compute(
      prepareCoverImageIsolateEntry,
      CoverImagePrepareMessage(raw, contentType),
    );
  } on Object catch (_) {
    return prepareCoverImageForUpload(raw, contentType);
  }
}

/// Resize and JPEG-compress cover photos so web Storage uploads stay small and complete.
({Uint8List bytes, String contentType}) prepareCoverImageForUpload(
  Uint8List raw,
  String contentType,
) {
  final lower = contentType.toLowerCase();
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      return (bytes: raw, contentType: contentType);
    }
    var src = decoded;
    const maxSide = 1280;
    if (src.width > maxSide || src.height > maxSide) {
      if (src.width >= src.height) {
        src = img.copyResize(
          src,
          width: maxSide,
          interpolation: img.Interpolation.linear,
        );
      } else {
        src = img.copyResize(
          src,
          height: maxSide,
          interpolation: img.Interpolation.linear,
        );
      }
    }
    var jpeg = Uint8List.fromList(img.encodeJpg(src, quality: 78));
    for (final q in [65, 52, 40]) {
      if (jpeg.length <= 900000) break;
      jpeg = Uint8List.fromList(img.encodeJpg(src, quality: q));
    }
    return (bytes: jpeg, contentType: 'image/jpeg');
  } on Exception {
    if (lower.contains('png')) {
      return (bytes: raw, contentType: 'image/png');
    }
    return (bytes: raw, contentType: contentType);
  }
}
