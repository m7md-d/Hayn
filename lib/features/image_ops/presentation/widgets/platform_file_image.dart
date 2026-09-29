import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/platform_pixels.dart';

/// `Image.file` for images Flutter may not decode correctly itself: on Android
/// an AVIF/HEIC file is shown through the platform bridge (IMG-13). Only the
/// header is read to decide; every other file is `Image.file` as before.
class PlatformFileImage extends StatefulWidget {
  const PlatformFileImage(
    this.path, {
    super.key,
    required this.maxEdge,
    this.fit,
    this.cacheWidth,
    this.errorBuilder,
  });

  final String path;

  /// Bound of the bridge decode; match it to the displayed size.
  final int maxEdge;
  final BoxFit? fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<PlatformFileImage> createState() => _PlatformFileImageState();
}

class _PlatformFileImageState extends State<PlatformFileImage> {
  late Future<Uint8List?> _bridged = _load();

  @override
  void didUpdateWidget(PlatformFileImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.maxEdge != widget.maxEdge) {
      _bridged = _load();
    }
  }

  /// Bridged bytes, or null when Flutter can decode the file itself.
  Future<Uint8List?> _load() async {
    final file = File(widget.path);
    final RandomAccessFile header;
    try {
      header = await file.open();
    } on FileSystemException {
      return null; // Image.file shows the error builder.
    }
    final Uint8List head;
    try {
      head = await header.read(64);
    } finally {
      await header.close();
    }
    if (!PlatformPixels.needsBridge(head)) return null;
    return PlatformPixels.forDisplay(
      await file.readAsBytes(),
      maxEdge: widget.maxEdge,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bridged,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox.shrink();
      }
      final bytes = snapshot.data;
      if (bytes == null) {
        return Image.file(
          File(widget.path),
          fit: widget.fit,
          gaplessPlayback: true,
          cacheWidth: widget.cacheWidth,
          errorBuilder: widget.errorBuilder,
        );
      }
      return Image.memory(
        bytes,
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: widget.cacheWidth,
        errorBuilder: widget.errorBuilder,
      );
    },
  );
}
