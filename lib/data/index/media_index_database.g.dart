// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_index_database.dart';

// ignore_for_file: type=lint
class $MediaAssetsTable extends MediaAssets
    with TableInfo<$MediaAssetsTable, MediaAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdDateMeta = const VerificationMeta(
    'createdDate',
  );
  @override
  late final GeneratedColumn<int> createdDate = GeneratedColumn<int>(
    'created_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _modifiedDateMeta = const VerificationMeta(
    'modifiedDate',
  );
  @override
  late final GeneratedColumn<int> modifiedDate = GeneratedColumn<int>(
    'modified_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    createdDate,
    modifiedDate,
    width,
    height,
    durationMs,
    sizeBytes,
    title,
    mimeType,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('created_date')) {
      context.handle(
        _createdDateMeta,
        createdDate.isAcceptableOrUnknown(
          data['created_date']!,
          _createdDateMeta,
        ),
      );
    }
    if (data.containsKey('modified_date')) {
      context.handle(
        _modifiedDateMeta,
        modifiedDate.isAcceptableOrUnknown(
          data['modified_date']!,
          _modifiedDateMeta,
        ),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type'],
      )!,
      createdDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_date'],
      )!,
      modifiedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_date'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
    );
  }

  @override
  $MediaAssetsTable createAlias(String alias) {
    return $MediaAssetsTable(attachedDatabase, alias);
  }
}

class MediaAsset extends DataClass implements Insertable<MediaAsset> {
  /// platform asset id (Android MediaStore id / iOS PhotoKit localIdentifier).
  final String id;

  /// AssetType.index — 0 other, 1 image, 2 video, 3 audio.
  final int type;

  /// Epoch seconds. 0 when the platform didn't report a date.
  final int createdDate;
  final int modifiedDate;
  final int width;
  final int height;

  /// Video duration in milliseconds; 0 for stills.
  final int durationMs;

  /// File size in bytes. null = not yet resolved (filled by the size pass).
  final int? sizeBytes;
  final String? title;
  final String? mimeType;
  const MediaAsset({
    required this.id,
    required this.type,
    required this.createdDate,
    required this.modifiedDate,
    required this.width,
    required this.height,
    required this.durationMs,
    this.sizeBytes,
    this.title,
    this.mimeType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<int>(type);
    map['created_date'] = Variable<int>(createdDate);
    map['modified_date'] = Variable<int>(modifiedDate);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    return map;
  }

  MediaAssetsCompanion toCompanion(bool nullToAbsent) {
    return MediaAssetsCompanion(
      id: Value(id),
      type: Value(type),
      createdDate: Value(createdDate),
      modifiedDate: Value(modifiedDate),
      width: Value(width),
      height: Value(height),
      durationMs: Value(durationMs),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
    );
  }

  factory MediaAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaAsset(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<int>(json['type']),
      createdDate: serializer.fromJson<int>(json['createdDate']),
      modifiedDate: serializer.fromJson<int>(json['modifiedDate']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      title: serializer.fromJson<String?>(json['title']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<int>(type),
      'createdDate': serializer.toJson<int>(createdDate),
      'modifiedDate': serializer.toJson<int>(modifiedDate),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'durationMs': serializer.toJson<int>(durationMs),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'title': serializer.toJson<String?>(title),
      'mimeType': serializer.toJson<String?>(mimeType),
    };
  }

  MediaAsset copyWith({
    String? id,
    int? type,
    int? createdDate,
    int? modifiedDate,
    int? width,
    int? height,
    int? durationMs,
    Value<int?> sizeBytes = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
  }) => MediaAsset(
    id: id ?? this.id,
    type: type ?? this.type,
    createdDate: createdDate ?? this.createdDate,
    modifiedDate: modifiedDate ?? this.modifiedDate,
    width: width ?? this.width,
    height: height ?? this.height,
    durationMs: durationMs ?? this.durationMs,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    title: title.present ? title.value : this.title,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
  );
  MediaAsset copyWithCompanion(MediaAssetsCompanion data) {
    return MediaAsset(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      createdDate: data.createdDate.present
          ? data.createdDate.value
          : this.createdDate,
      modifiedDate: data.modifiedDate.present
          ? data.modifiedDate.value
          : this.modifiedDate,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      title: data.title.present ? data.title.value : this.title,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaAsset(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('createdDate: $createdDate, ')
          ..write('modifiedDate: $modifiedDate, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('title: $title, ')
          ..write('mimeType: $mimeType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    createdDate,
    modifiedDate,
    width,
    height,
    durationMs,
    sizeBytes,
    title,
    mimeType,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaAsset &&
          other.id == this.id &&
          other.type == this.type &&
          other.createdDate == this.createdDate &&
          other.modifiedDate == this.modifiedDate &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          other.sizeBytes == this.sizeBytes &&
          other.title == this.title &&
          other.mimeType == this.mimeType);
}

class MediaAssetsCompanion extends UpdateCompanion<MediaAsset> {
  final Value<String> id;
  final Value<int> type;
  final Value<int> createdDate;
  final Value<int> modifiedDate;
  final Value<int> width;
  final Value<int> height;
  final Value<int> durationMs;
  final Value<int?> sizeBytes;
  final Value<String?> title;
  final Value<String?> mimeType;
  final Value<int> rowid;
  const MediaAssetsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.createdDate = const Value.absent(),
    this.modifiedDate = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.title = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaAssetsCompanion.insert({
    required String id,
    required int type,
    this.createdDate = const Value.absent(),
    this.modifiedDate = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.title = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type);
  static Insertable<MediaAsset> custom({
    Expression<String>? id,
    Expression<int>? type,
    Expression<int>? createdDate,
    Expression<int>? modifiedDate,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<int>? sizeBytes,
    Expression<String>? title,
    Expression<String>? mimeType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (createdDate != null) 'created_date': createdDate,
      if (modifiedDate != null) 'modified_date': modifiedDate,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (title != null) 'title': title,
      if (mimeType != null) 'mime_type': mimeType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaAssetsCompanion copyWith({
    Value<String>? id,
    Value<int>? type,
    Value<int>? createdDate,
    Value<int>? modifiedDate,
    Value<int>? width,
    Value<int>? height,
    Value<int>? durationMs,
    Value<int?>? sizeBytes,
    Value<String?>? title,
    Value<String?>? mimeType,
    Value<int>? rowid,
  }) {
    return MediaAssetsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      createdDate: createdDate ?? this.createdDate,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      title: title ?? this.title,
      mimeType: mimeType ?? this.mimeType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (createdDate.present) {
      map['created_date'] = Variable<int>(createdDate.value);
    }
    if (modifiedDate.present) {
      map['modified_date'] = Variable<int>(modifiedDate.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaAssetsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('createdDate: $createdDate, ')
          ..write('modifiedDate: $modifiedDate, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('title: $title, ')
          ..write('mimeType: $mimeType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MediaIndexDatabase extends GeneratedDatabase {
  _$MediaIndexDatabase(QueryExecutor e) : super(e);
  $MediaIndexDatabaseManager get managers => $MediaIndexDatabaseManager(this);
  late final $MediaAssetsTable mediaAssets = $MediaAssetsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [mediaAssets];
}

typedef $$MediaAssetsTableCreateCompanionBuilder =
    MediaAssetsCompanion Function({
      required String id,
      required int type,
      Value<int> createdDate,
      Value<int> modifiedDate,
      Value<int> width,
      Value<int> height,
      Value<int> durationMs,
      Value<int?> sizeBytes,
      Value<String?> title,
      Value<String?> mimeType,
      Value<int> rowid,
    });
typedef $$MediaAssetsTableUpdateCompanionBuilder =
    MediaAssetsCompanion Function({
      Value<String> id,
      Value<int> type,
      Value<int> createdDate,
      Value<int> modifiedDate,
      Value<int> width,
      Value<int> height,
      Value<int> durationMs,
      Value<int?> sizeBytes,
      Value<String?> title,
      Value<String?> mimeType,
      Value<int> rowid,
    });

class $$MediaAssetsTableFilterComposer
    extends Composer<_$MediaIndexDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdDate => $composableBuilder(
    column: $table.createdDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedDate => $composableBuilder(
    column: $table.modifiedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaAssetsTableOrderingComposer
    extends Composer<_$MediaIndexDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdDate => $composableBuilder(
    column: $table.createdDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedDate => $composableBuilder(
    column: $table.modifiedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaAssetsTableAnnotationComposer
    extends Composer<_$MediaIndexDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get createdDate => $composableBuilder(
    column: $table.createdDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get modifiedDate => $composableBuilder(
    column: $table.modifiedDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);
}

class $$MediaAssetsTableTableManager
    extends
        RootTableManager<
          _$MediaIndexDatabase,
          $MediaAssetsTable,
          MediaAsset,
          $$MediaAssetsTableFilterComposer,
          $$MediaAssetsTableOrderingComposer,
          $$MediaAssetsTableAnnotationComposer,
          $$MediaAssetsTableCreateCompanionBuilder,
          $$MediaAssetsTableUpdateCompanionBuilder,
          (
            MediaAsset,
            BaseReferences<_$MediaIndexDatabase, $MediaAssetsTable, MediaAsset>,
          ),
          MediaAsset,
          PrefetchHooks Function()
        > {
  $$MediaAssetsTableTableManager(
    _$MediaIndexDatabase db,
    $MediaAssetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> createdDate = const Value.absent(),
                Value<int> modifiedDate = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaAssetsCompanion(
                id: id,
                type: type,
                createdDate: createdDate,
                modifiedDate: modifiedDate,
                width: width,
                height: height,
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                title: title,
                mimeType: mimeType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int type,
                Value<int> createdDate = const Value.absent(),
                Value<int> modifiedDate = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaAssetsCompanion.insert(
                id: id,
                type: type,
                createdDate: createdDate,
                modifiedDate: modifiedDate,
                width: width,
                height: height,
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                title: title,
                mimeType: mimeType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$MediaIndexDatabase,
      $MediaAssetsTable,
      MediaAsset,
      $$MediaAssetsTableFilterComposer,
      $$MediaAssetsTableOrderingComposer,
      $$MediaAssetsTableAnnotationComposer,
      $$MediaAssetsTableCreateCompanionBuilder,
      $$MediaAssetsTableUpdateCompanionBuilder,
      (
        MediaAsset,
        BaseReferences<_$MediaIndexDatabase, $MediaAssetsTable, MediaAsset>,
      ),
      MediaAsset,
      PrefetchHooks Function()
    >;

class $MediaIndexDatabaseManager {
  final _$MediaIndexDatabase _db;
  $MediaIndexDatabaseManager(this._db);
  $$MediaAssetsTableTableManager get mediaAssets =>
      $$MediaAssetsTableTableManager(_db, _db.mediaAssets);
}
