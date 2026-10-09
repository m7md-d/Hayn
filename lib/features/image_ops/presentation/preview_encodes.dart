import 'package:flutter/foundation.dart';

import '../../../core/isolates/heavy_work.dart';
import '../../settings/providers/preferences_providers.dart';
import '../data/image_encoder.dart';

/// What a compress preview encode was asked for: the image and every setting
/// that shapes its bytes. A result is saved only under the request that
/// produced it (RV-01).
@immutable
class PreviewRequest {
  const PreviewRequest({
    required this.assetId,
    required this.format,
    required this.quality,
    required this.keepMetadata,
    required this.keepOriginalTime,
    required this.bitDepth,
  });

  final String assetId;
  final DefaultFormat format;
  final int quality;
  final bool keepMetadata;
  final bool keepOriginalTime;
  final int bitDepth;

  @override
  bool operator ==(Object other) =>
      other is PreviewRequest &&
      other.assetId == assetId &&
      other.format == format &&
      other.quality == quality &&
      other.keepMetadata == keepMetadata &&
      other.keepOriginalTime == keepOriginalTime &&
      other.bitDepth == bitDepth;

  @override
  int get hashCode => Object.hash(
    assetId,
    format,
    quality,
    keepMetadata,
    keepOriginalTime,
    bitDepth,
  );
}

/// One preview encode in flight: its request and its place in the gate.
class PreviewJob {
  PreviewJob._(this._generation, this.request, this.ticket);
  final int _generation;
  final PreviewRequest request;
  final HeavyWorkTicket ticket;
}

/// The compress screen's preview encodes (RV-01). A job keeps the request it
/// started with; a settings change or another image makes it stale at once
/// (and withdraws it from the gate if it has not started), so a late result
/// is never shown or saved under a request it was not made for.
class PreviewEncodes {
  int _generation = 0;
  HeavyWorkTicket? _ticket;
  PreviewRequest? _doneRequest;
  EncodedImage? _done;

  /// A new job for [request]; any earlier one becomes stale.
  PreviewJob begin(PreviewRequest request) {
    invalidate();
    final ticket = _ticket = HeavyWorkTicket();
    return PreviewJob._(_generation, request, ticket);
  }

  /// Makes the job in flight stale: the request it was made for changed.
  void invalidate() {
    _generation++;
    _ticket?.withdraw();
    _ticket = null;
  }

  bool isCurrent(PreviewJob job) => job._generation == _generation;

  /// Keeps [result] as [job]'s request's; false when the job is stale.
  bool complete(PreviewJob job, EncodedImage result) {
    if (!isCurrent(job)) return false;
    _doneRequest = job.request;
    _done = result;
    return true;
  }

  /// Forgets the finished result (another image is active, or it failed).
  void clear() {
    _doneRequest = null;
    _done = null;
  }

  /// The finished result when it was made for exactly [request].
  EncodedImage? reusable(PreviewRequest request) =>
      _doneRequest == request ? _done : null;
}
