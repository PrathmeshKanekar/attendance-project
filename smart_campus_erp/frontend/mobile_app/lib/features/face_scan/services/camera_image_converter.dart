/// Production-grade CameraImage → InputImage converter.
///
/// Fixes the #1 cause of ML Kit detection failures:
/// incorrect byte buffer construction and format/rotation mismatch.
///
/// Key fixes:
/// - Hardcodes NV21 format detection (raw value 17) instead of relying
///   on InputImageFormatValue.fromRawValue() which fails on some versions
/// - Uses planes[0].bytes only for NV21 (correct — NV21 is interleaved)
/// - Computes correct rotation for front camera on Android
/// - Handles YUV_420_888 fallback with proper plane concatenation
library;

import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraImageConverter {
  CameraImageConverter._();

  /// Android NV21 raw format value from android.graphics.ImageFormat.
  static const int _kNv21RawValue   = 17;
  /// Android YUV_420_888 raw format value.
  static const int _kYuv420RawValue = 35;

  /// Converts a [CameraImage] from the camera stream to an ML Kit [InputImage].
  ///
  /// Returns `null` if the conversion cannot be performed (unsupported format,
  /// empty planes, etc.). This is by design — callers should silently skip
  /// frames that return null rather than crashing.
  static InputImage? convert(CameraImage image, CameraDescription camera) {
    if (image.planes.isEmpty) return null;

    final rotation = _computeRotation(camera);
    if (rotation == null) return null;

    if (Platform.isAndroid) {
      return _convertAndroid(image, rotation);
    } else if (Platform.isIOS) {
      return _convertIOS(image, rotation);
    }

    return null;
  }

  /// Android-specific conversion handling NV21 and YUV_420_888.
  static InputImage? _convertAndroid(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    final int rawFormat = image.format.raw;

    // ── NV21 (raw = 17) ──────────────────────────────────────────────
    // NV21 is a single interleaved buffer: Y plane followed by interleaved VU.
    // The camera plugin delivers this as planes[0] containing the FULL buffer.
    // DO NOT concatenate planes — that produces a corrupt doubled buffer.
    if (rawFormat == _kNv21RawValue) {
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    // ── YUV_420_888 (raw = 35) ───────────────────────────────────────
    // Some OEMs (Samsung, Xiaomi) deliver YUV_420_888 even when NV21 is
    // requested. For ML Kit, we concatenate all planes into a single buffer.
    // ML Kit handles YUV_420_888 correctly when all planes are provided.
    if (rawFormat == _kYuv420RawValue) {
      final allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.yuv_420_888,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    // ── Fallback: try NV21 interpretation ────────────────────────────
    // Some devices report non-standard raw values but still deliver
    // NV21-compatible data. Try planes[0] as NV21.
    debugPrint(
      'CameraImageConverter: Unknown Android format raw=$rawFormat, '
      'attempting NV21 interpretation with planes[0]'
    );
    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  /// iOS-specific conversion for BGRA8888.
  static InputImage? _convertIOS(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    // iOS camera always delivers BGRA8888 as a single plane.
    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  /// Computes the correct [InputImageRotation] for ML Kit.
  ///
  /// On Android front cameras, the sensor orientation is typically 270°.
  /// ML Kit expects the rotation that describes how to rotate the image
  /// from sensor coordinates to the device's natural (portrait) orientation.
  ///
  /// For front cameras, the sensor image is additionally mirrored, but
  /// ML Kit handles mirroring internally — we only need to provide the
  /// rotation angle.
  static InputImageRotation? _computeRotation(CameraDescription camera) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(camera.sensorOrientation)
          ?? InputImageRotation.rotation0deg;
    }

    // Android: Use the sensor orientation directly.
    // For most Android front cameras this is 270.
    // For most Android back cameras this is 90.
    final sensorOrientation = camera.sensorOrientation;
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        // Non-standard orientation — try nearest
        debugPrint(
          'CameraImageConverter: Non-standard sensor orientation '
          '$sensorOrientation, falling back to 270°'
        );
        return InputImageRotation.rotation270deg;
    }
  }
}
