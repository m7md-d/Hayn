import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_index_database.dart';
import 'media_index_service.dart';

/// The single app-wide media index database. Opened once, closed on dispose.
final mediaIndexDatabaseProvider = Provider<MediaIndexDatabase>((ref) {
  final db = MediaIndexDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Keeps the index in step with the device library (scan + size resolution).
final mediaIndexServiceProvider = Provider<MediaIndexService>((ref) {
  return MediaIndexService(db: ref.watch(mediaIndexDatabaseProvider));
});
