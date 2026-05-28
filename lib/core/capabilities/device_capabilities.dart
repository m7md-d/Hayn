import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.hevcHardwareEncode,
    required this.avifEncodeEfficient,
    required this.coreCount,
    required this.ramGb,
  });

  /// True if device can encode HEVC/HEIC via hardware (system codec).
  final bool hevcHardwareEncode;

  /// True if AVIF encoding completes a test frame in reasonable time.
  final bool avifEncodeEfficient;

  /// Available CPU cores.
  final int coreCount;

  /// Total RAM in gigabytes.
  final double ramGb;

  bool get isHighEnd => coreCount >= 8 && ramGb >= 6;
  bool get isMidRange => coreCount >= 4 && ramGb >= 3;

  static const unknown = DeviceCapabilities(
    hevcHardwareEncode: false,
    avifEncodeEfficient: false,
    coreCount: 4,
    ramGb: 4,
  );
}

class DeviceCapabilitiesNotifier extends AsyncNotifier<DeviceCapabilities> {
  static const _channel = MethodChannel('app.naqaa.hayn/capabilities');

  @override
  Future<DeviceCapabilities> build() => _detect();

  Future<DeviceCapabilities> _detect() async {
    try {
      final cores = Platform.numberOfProcessors;

      // RAM via platform channel; falls back to 4 GB if unavailable.
      double ramGb = 4;
      try {
        final bytes = await _channel.invokeMethod<int>('getTotalRamBytes');
        if (bytes != null && bytes > 0) {
          ramGb = bytes / (1024 * 1024 * 1024);
        }
      } on MissingPluginException {
        // Channel not yet implemented — fine for Phase 0.
      }

      return DeviceCapabilities(
        hevcHardwareEncode: false, // Phase 2+: detect via MediaCodecList
        avifEncodeEfficient: false, // Phase 2+: benchmark small encode
        coreCount: cores,
        ramGb: ramGb,
      );
    } catch (_) {
      return DeviceCapabilities.unknown;
    }
  }
}

final deviceCapabilitiesProvider =
    AsyncNotifierProvider<DeviceCapabilitiesNotifier, DeviceCapabilities>(
  DeviceCapabilitiesNotifier.new,
);
