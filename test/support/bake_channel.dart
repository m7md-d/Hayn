import 'dart:io';

import 'package:flutter/services.dart';

/// Answers the platform's upright-decode call with [bytes] the way each side
/// does: iOS returns the PNG (`bakeUpright`), Android writes it to a file and
/// returns the path (`bakeUprightFile`, PERF-02). Other calls get null.
Future<Object?> answerBake(MethodCall call, Uint8List? bytes) async {
  if (call.method == 'bakeUpright') return bytes;
  if (call.method != 'bakeUprightFile' || bytes == null) return null;
  final dir = await Directory.systemTemp.createTemp('hayn-bake-test');
  final file = File('${dir.path}/bake.png');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// Whether [call] asks for an upright decode, on either platform.
bool isBake(MethodCall call) =>
    call.method == 'bakeUpright' || call.method == 'bakeUprightFile';
