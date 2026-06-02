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

class $TrashEntriesTable extends TrashEntries
    with TableInfo<$TrashEntriesTable, TrashEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrashEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalAssetIdMeta = const VerificationMeta(
    'originalAssetId',
  );
  @override
  late final GeneratedColumn<String> originalAssetId = GeneratedColumn<String>(
    'original_asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdDateMsMeta = const VerificationMeta(
    'createdDateMs',
  );
  @override
  late final GeneratedColumn<int> createdDateMs = GeneratedColumn<int>(
    'created_date_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _modifiedDateMsMeta = const VerificationMeta(
    'modifiedDateMs',
  );
  @override
  late final GeneratedColumn<int> modifiedDateMs = GeneratedColumn<int>(
    'modified_date_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _userAlbumIdsMeta = const VerificationMeta(
    'userAlbumIds',
  );
  @override
  late final GeneratedColumn<String> userAlbumIds = GeneratedColumn<String>(
    'user_album_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _wasInSmartAlbumMeta = const VerificationMeta(
    'wasInSmartAlbum',
  );
  @override
  late final GeneratedColumn<bool> wasInSmartAlbum = GeneratedColumn<bool>(
    'was_in_smart_album',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("was_in_smart_album" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  static const VerificationMeta _assetTypeMeta = const VerificationMeta(
    'assetType',
  );
  @override
  late final GeneratedColumn<int> assetType = GeneratedColumn<int>(
    'asset_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _originalBytesMeta = const VerificationMeta(
    'originalBytes',
  );
  @override
  late final GeneratedColumn<int> originalBytes = GeneratedColumn<int>(
    'original_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _newBytesMeta = const VerificationMeta(
    'newBytes',
  );
  @override
  late final GeneratedColumn<int> newBytes = GeneratedColumn<int>(
    'new_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _backupPathMeta = const VerificationMeta(
    'backupPath',
  );
  @override
  late final GeneratedColumn<String> backupPath = GeneratedColumn<String>(
    'backup_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _newAssetIdMeta = const VerificationMeta(
    'newAssetId',
  );
  @override
  late final GeneratedColumn<String> newAssetId = GeneratedColumn<String>(
    'new_asset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<int> state = GeneratedColumn<int>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMsMeta = const VerificationMeta(
    'deletedAtMs',
  );
  @override
  late final GeneratedColumn<int> deletedAtMs = GeneratedColumn<int>(
    'deleted_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    originalAssetId,
    filename,
    createdDateMs,
    modifiedDateMs,
    latitude,
    longitude,
    isFavorite,
    userAlbumIds,
    wasInSmartAlbum,
    mimeType,
    assetType,
    width,
    height,
    originalBytes,
    newBytes,
    backupPath,
    newAssetId,
    state,
    deletedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trash_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrashEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('original_asset_id')) {
      context.handle(
        _originalAssetIdMeta,
        originalAssetId.isAcceptableOrUnknown(
          data['original_asset_id']!,
          _originalAssetIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalAssetIdMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    }
    if (data.containsKey('created_date_ms')) {
      context.handle(
        _createdDateMsMeta,
        createdDateMs.isAcceptableOrUnknown(
          data['created_date_ms']!,
          _createdDateMsMeta,
        ),
      );
    }
    if (data.containsKey('modified_date_ms')) {
      context.handle(
        _modifiedDateMsMeta,
        modifiedDateMs.isAcceptableOrUnknown(
          data['modified_date_ms']!,
          _modifiedDateMsMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('user_album_ids')) {
      context.handle(
        _userAlbumIdsMeta,
        userAlbumIds.isAcceptableOrUnknown(
          data['user_album_ids']!,
          _userAlbumIdsMeta,
        ),
      );
    }
    if (data.containsKey('was_in_smart_album')) {
      context.handle(
        _wasInSmartAlbumMeta,
        wasInSmartAlbum.isAcceptableOrUnknown(
          data['was_in_smart_album']!,
          _wasInSmartAlbumMeta,
        ),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('asset_type')) {
      context.handle(
        _assetTypeMeta,
        assetType.isAcceptableOrUnknown(data['asset_type']!, _assetTypeMeta),
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
    if (data.containsKey('original_bytes')) {
      context.handle(
        _originalBytesMeta,
        originalBytes.isAcceptableOrUnknown(
          data['original_bytes']!,
          _originalBytesMeta,
        ),
      );
    }
    if (data.containsKey('new_bytes')) {
      context.handle(
        _newBytesMeta,
        newBytes.isAcceptableOrUnknown(data['new_bytes']!, _newBytesMeta),
      );
    }
    if (data.containsKey('backup_path')) {
      context.handle(
        _backupPathMeta,
        backupPath.isAcceptableOrUnknown(data['backup_path']!, _backupPathMeta),
      );
    }
    if (data.containsKey('new_asset_id')) {
      context.handle(
        _newAssetIdMeta,
        newAssetId.isAcceptableOrUnknown(
          data['new_asset_id']!,
          _newAssetIdMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('deleted_at_ms')) {
      context.handle(
        _deletedAtMsMeta,
        deletedAtMs.isAcceptableOrUnknown(
          data['deleted_at_ms']!,
          _deletedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrashEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrashEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      originalAssetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_asset_id'],
      )!,
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      )!,
      createdDateMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_date_ms'],
      )!,
      modifiedDateMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_date_ms'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      userAlbumIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_album_ids'],
      )!,
      wasInSmartAlbum: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}was_in_smart_album'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      assetType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}asset_type'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      originalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}original_bytes'],
      )!,
      newBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}new_bytes'],
      )!,
      backupPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backup_path'],
      )!,
      newAssetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}new_asset_id'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}state'],
      )!,
      deletedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at_ms'],
      )!,
    );
  }

  @override
  $TrashEntriesTable createAlias(String alias) {
    return $TrashEntriesTable(attachedDatabase, alias);
  }
}

class TrashEntry extends DataClass implements Insertable<TrashEntry> {
  /// Internal trash-entry id (timestamp + random; NOT a device asset id).
  final String id;

  /// The device asset id that was (or is being) replaced.
  final String originalAssetId;
  final String filename;

  /// Original capture + modified dates (epoch ms). 0 = unknown.
  final int createdDateMs;
  final int modifiedDateMs;
  final double? latitude;
  final double? longitude;
  final bool isFavorite;

  /// JSON array of user-album localIds the original belonged to (for restore).
  final String userAlbumIds;

  /// True when the original sat in a smart album we can't re-create (screenshot
  /// / selfie / …) — for display only.
  final bool wasInSmartAlbum;
  final String? mimeType;

  /// AssetType.index — 1 image, 2 video.
  final int assetType;
  final int width;
  final int height;
  final int originalBytes;
  final int newBytes;

  /// Absolute path to the backed-up original bytes (app-private trash dir).
  final String backupPath;

  /// The replacement asset's id; null until it's created / after rollback.
  final String? newAssetId;

  /// Journal state — 0 pending (original NOT yet deleted), 1 committed.
  final int state;

  /// When the original was deleted (epoch ms) — drives the retention countdown.
  final int deletedAtMs;
  const TrashEntry({
    required this.id,
    required this.originalAssetId,
    required this.filename,
    required this.createdDateMs,
    required this.modifiedDateMs,
    this.latitude,
    this.longitude,
    required this.isFavorite,
    required this.userAlbumIds,
    required this.wasInSmartAlbum,
    this.mimeType,
    required this.assetType,
    required this.width,
    required this.height,
    required this.originalBytes,
    required this.newBytes,
    required this.backupPath,
    this.newAssetId,
    required this.state,
    required this.deletedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['original_asset_id'] = Variable<String>(originalAssetId);
    map['filename'] = Variable<String>(filename);
    map['created_date_ms'] = Variable<int>(createdDateMs);
    map['modified_date_ms'] = Variable<int>(modifiedDateMs);
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['user_album_ids'] = Variable<String>(userAlbumIds);
    map['was_in_smart_album'] = Variable<bool>(wasInSmartAlbum);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    map['asset_type'] = Variable<int>(assetType);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['original_bytes'] = Variable<int>(originalBytes);
    map['new_bytes'] = Variable<int>(newBytes);
    map['backup_path'] = Variable<String>(backupPath);
    if (!nullToAbsent || newAssetId != null) {
      map['new_asset_id'] = Variable<String>(newAssetId);
    }
    map['state'] = Variable<int>(state);
    map['deleted_at_ms'] = Variable<int>(deletedAtMs);
    return map;
  }

  TrashEntriesCompanion toCompanion(bool nullToAbsent) {
    return TrashEntriesCompanion(
      id: Value(id),
      originalAssetId: Value(originalAssetId),
      filename: Value(filename),
      createdDateMs: Value(createdDateMs),
      modifiedDateMs: Value(modifiedDateMs),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      isFavorite: Value(isFavorite),
      userAlbumIds: Value(userAlbumIds),
      wasInSmartAlbum: Value(wasInSmartAlbum),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      assetType: Value(assetType),
      width: Value(width),
      height: Value(height),
      originalBytes: Value(originalBytes),
      newBytes: Value(newBytes),
      backupPath: Value(backupPath),
      newAssetId: newAssetId == null && nullToAbsent
          ? const Value.absent()
          : Value(newAssetId),
      state: Value(state),
      deletedAtMs: Value(deletedAtMs),
    );
  }

  factory TrashEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrashEntry(
      id: serializer.fromJson<String>(json['id']),
      originalAssetId: serializer.fromJson<String>(json['originalAssetId']),
      filename: serializer.fromJson<String>(json['filename']),
      createdDateMs: serializer.fromJson<int>(json['createdDateMs']),
      modifiedDateMs: serializer.fromJson<int>(json['modifiedDateMs']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      userAlbumIds: serializer.fromJson<String>(json['userAlbumIds']),
      wasInSmartAlbum: serializer.fromJson<bool>(json['wasInSmartAlbum']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      assetType: serializer.fromJson<int>(json['assetType']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      originalBytes: serializer.fromJson<int>(json['originalBytes']),
      newBytes: serializer.fromJson<int>(json['newBytes']),
      backupPath: serializer.fromJson<String>(json['backupPath']),
      newAssetId: serializer.fromJson<String?>(json['newAssetId']),
      state: serializer.fromJson<int>(json['state']),
      deletedAtMs: serializer.fromJson<int>(json['deletedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'originalAssetId': serializer.toJson<String>(originalAssetId),
      'filename': serializer.toJson<String>(filename),
      'createdDateMs': serializer.toJson<int>(createdDateMs),
      'modifiedDateMs': serializer.toJson<int>(modifiedDateMs),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'userAlbumIds': serializer.toJson<String>(userAlbumIds),
      'wasInSmartAlbum': serializer.toJson<bool>(wasInSmartAlbum),
      'mimeType': serializer.toJson<String?>(mimeType),
      'assetType': serializer.toJson<int>(assetType),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'originalBytes': serializer.toJson<int>(originalBytes),
      'newBytes': serializer.toJson<int>(newBytes),
      'backupPath': serializer.toJson<String>(backupPath),
      'newAssetId': serializer.toJson<String?>(newAssetId),
      'state': serializer.toJson<int>(state),
      'deletedAtMs': serializer.toJson<int>(deletedAtMs),
    };
  }

  TrashEntry copyWith({
    String? id,
    String? originalAssetId,
    String? filename,
    int? createdDateMs,
    int? modifiedDateMs,
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    bool? isFavorite,
    String? userAlbumIds,
    bool? wasInSmartAlbum,
    Value<String?> mimeType = const Value.absent(),
    int? assetType,
    int? width,
    int? height,
    int? originalBytes,
    int? newBytes,
    String? backupPath,
    Value<String?> newAssetId = const Value.absent(),
    int? state,
    int? deletedAtMs,
  }) => TrashEntry(
    id: id ?? this.id,
    originalAssetId: originalAssetId ?? this.originalAssetId,
    filename: filename ?? this.filename,
    createdDateMs: createdDateMs ?? this.createdDateMs,
    modifiedDateMs: modifiedDateMs ?? this.modifiedDateMs,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    isFavorite: isFavorite ?? this.isFavorite,
    userAlbumIds: userAlbumIds ?? this.userAlbumIds,
    wasInSmartAlbum: wasInSmartAlbum ?? this.wasInSmartAlbum,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    assetType: assetType ?? this.assetType,
    width: width ?? this.width,
    height: height ?? this.height,
    originalBytes: originalBytes ?? this.originalBytes,
    newBytes: newBytes ?? this.newBytes,
    backupPath: backupPath ?? this.backupPath,
    newAssetId: newAssetId.present ? newAssetId.value : this.newAssetId,
    state: state ?? this.state,
    deletedAtMs: deletedAtMs ?? this.deletedAtMs,
  );
  TrashEntry copyWithCompanion(TrashEntriesCompanion data) {
    return TrashEntry(
      id: data.id.present ? data.id.value : this.id,
      originalAssetId: data.originalAssetId.present
          ? data.originalAssetId.value
          : this.originalAssetId,
      filename: data.filename.present ? data.filename.value : this.filename,
      createdDateMs: data.createdDateMs.present
          ? data.createdDateMs.value
          : this.createdDateMs,
      modifiedDateMs: data.modifiedDateMs.present
          ? data.modifiedDateMs.value
          : this.modifiedDateMs,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      userAlbumIds: data.userAlbumIds.present
          ? data.userAlbumIds.value
          : this.userAlbumIds,
      wasInSmartAlbum: data.wasInSmartAlbum.present
          ? data.wasInSmartAlbum.value
          : this.wasInSmartAlbum,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      assetType: data.assetType.present ? data.assetType.value : this.assetType,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      originalBytes: data.originalBytes.present
          ? data.originalBytes.value
          : this.originalBytes,
      newBytes: data.newBytes.present ? data.newBytes.value : this.newBytes,
      backupPath: data.backupPath.present
          ? data.backupPath.value
          : this.backupPath,
      newAssetId: data.newAssetId.present
          ? data.newAssetId.value
          : this.newAssetId,
      state: data.state.present ? data.state.value : this.state,
      deletedAtMs: data.deletedAtMs.present
          ? data.deletedAtMs.value
          : this.deletedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrashEntry(')
          ..write('id: $id, ')
          ..write('originalAssetId: $originalAssetId, ')
          ..write('filename: $filename, ')
          ..write('createdDateMs: $createdDateMs, ')
          ..write('modifiedDateMs: $modifiedDateMs, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('userAlbumIds: $userAlbumIds, ')
          ..write('wasInSmartAlbum: $wasInSmartAlbum, ')
          ..write('mimeType: $mimeType, ')
          ..write('assetType: $assetType, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('originalBytes: $originalBytes, ')
          ..write('newBytes: $newBytes, ')
          ..write('backupPath: $backupPath, ')
          ..write('newAssetId: $newAssetId, ')
          ..write('state: $state, ')
          ..write('deletedAtMs: $deletedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    originalAssetId,
    filename,
    createdDateMs,
    modifiedDateMs,
    latitude,
    longitude,
    isFavorite,
    userAlbumIds,
    wasInSmartAlbum,
    mimeType,
    assetType,
    width,
    height,
    originalBytes,
    newBytes,
    backupPath,
    newAssetId,
    state,
    deletedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrashEntry &&
          other.id == this.id &&
          other.originalAssetId == this.originalAssetId &&
          other.filename == this.filename &&
          other.createdDateMs == this.createdDateMs &&
          other.modifiedDateMs == this.modifiedDateMs &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.isFavorite == this.isFavorite &&
          other.userAlbumIds == this.userAlbumIds &&
          other.wasInSmartAlbum == this.wasInSmartAlbum &&
          other.mimeType == this.mimeType &&
          other.assetType == this.assetType &&
          other.width == this.width &&
          other.height == this.height &&
          other.originalBytes == this.originalBytes &&
          other.newBytes == this.newBytes &&
          other.backupPath == this.backupPath &&
          other.newAssetId == this.newAssetId &&
          other.state == this.state &&
          other.deletedAtMs == this.deletedAtMs);
}

class TrashEntriesCompanion extends UpdateCompanion<TrashEntry> {
  final Value<String> id;
  final Value<String> originalAssetId;
  final Value<String> filename;
  final Value<int> createdDateMs;
  final Value<int> modifiedDateMs;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<bool> isFavorite;
  final Value<String> userAlbumIds;
  final Value<bool> wasInSmartAlbum;
  final Value<String?> mimeType;
  final Value<int> assetType;
  final Value<int> width;
  final Value<int> height;
  final Value<int> originalBytes;
  final Value<int> newBytes;
  final Value<String> backupPath;
  final Value<String?> newAssetId;
  final Value<int> state;
  final Value<int> deletedAtMs;
  final Value<int> rowid;
  const TrashEntriesCompanion({
    this.id = const Value.absent(),
    this.originalAssetId = const Value.absent(),
    this.filename = const Value.absent(),
    this.createdDateMs = const Value.absent(),
    this.modifiedDateMs = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.userAlbumIds = const Value.absent(),
    this.wasInSmartAlbum = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.assetType = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.originalBytes = const Value.absent(),
    this.newBytes = const Value.absent(),
    this.backupPath = const Value.absent(),
    this.newAssetId = const Value.absent(),
    this.state = const Value.absent(),
    this.deletedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrashEntriesCompanion.insert({
    required String id,
    required String originalAssetId,
    this.filename = const Value.absent(),
    this.createdDateMs = const Value.absent(),
    this.modifiedDateMs = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.userAlbumIds = const Value.absent(),
    this.wasInSmartAlbum = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.assetType = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.originalBytes = const Value.absent(),
    this.newBytes = const Value.absent(),
    this.backupPath = const Value.absent(),
    this.newAssetId = const Value.absent(),
    this.state = const Value.absent(),
    this.deletedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       originalAssetId = Value(originalAssetId);
  static Insertable<TrashEntry> custom({
    Expression<String>? id,
    Expression<String>? originalAssetId,
    Expression<String>? filename,
    Expression<int>? createdDateMs,
    Expression<int>? modifiedDateMs,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<bool>? isFavorite,
    Expression<String>? userAlbumIds,
    Expression<bool>? wasInSmartAlbum,
    Expression<String>? mimeType,
    Expression<int>? assetType,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? originalBytes,
    Expression<int>? newBytes,
    Expression<String>? backupPath,
    Expression<String>? newAssetId,
    Expression<int>? state,
    Expression<int>? deletedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (originalAssetId != null) 'original_asset_id': originalAssetId,
      if (filename != null) 'filename': filename,
      if (createdDateMs != null) 'created_date_ms': createdDateMs,
      if (modifiedDateMs != null) 'modified_date_ms': modifiedDateMs,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (userAlbumIds != null) 'user_album_ids': userAlbumIds,
      if (wasInSmartAlbum != null) 'was_in_smart_album': wasInSmartAlbum,
      if (mimeType != null) 'mime_type': mimeType,
      if (assetType != null) 'asset_type': assetType,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (originalBytes != null) 'original_bytes': originalBytes,
      if (newBytes != null) 'new_bytes': newBytes,
      if (backupPath != null) 'backup_path': backupPath,
      if (newAssetId != null) 'new_asset_id': newAssetId,
      if (state != null) 'state': state,
      if (deletedAtMs != null) 'deleted_at_ms': deletedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrashEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? originalAssetId,
    Value<String>? filename,
    Value<int>? createdDateMs,
    Value<int>? modifiedDateMs,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<bool>? isFavorite,
    Value<String>? userAlbumIds,
    Value<bool>? wasInSmartAlbum,
    Value<String?>? mimeType,
    Value<int>? assetType,
    Value<int>? width,
    Value<int>? height,
    Value<int>? originalBytes,
    Value<int>? newBytes,
    Value<String>? backupPath,
    Value<String?>? newAssetId,
    Value<int>? state,
    Value<int>? deletedAtMs,
    Value<int>? rowid,
  }) {
    return TrashEntriesCompanion(
      id: id ?? this.id,
      originalAssetId: originalAssetId ?? this.originalAssetId,
      filename: filename ?? this.filename,
      createdDateMs: createdDateMs ?? this.createdDateMs,
      modifiedDateMs: modifiedDateMs ?? this.modifiedDateMs,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isFavorite: isFavorite ?? this.isFavorite,
      userAlbumIds: userAlbumIds ?? this.userAlbumIds,
      wasInSmartAlbum: wasInSmartAlbum ?? this.wasInSmartAlbum,
      mimeType: mimeType ?? this.mimeType,
      assetType: assetType ?? this.assetType,
      width: width ?? this.width,
      height: height ?? this.height,
      originalBytes: originalBytes ?? this.originalBytes,
      newBytes: newBytes ?? this.newBytes,
      backupPath: backupPath ?? this.backupPath,
      newAssetId: newAssetId ?? this.newAssetId,
      state: state ?? this.state,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (originalAssetId.present) {
      map['original_asset_id'] = Variable<String>(originalAssetId.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (createdDateMs.present) {
      map['created_date_ms'] = Variable<int>(createdDateMs.value);
    }
    if (modifiedDateMs.present) {
      map['modified_date_ms'] = Variable<int>(modifiedDateMs.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (userAlbumIds.present) {
      map['user_album_ids'] = Variable<String>(userAlbumIds.value);
    }
    if (wasInSmartAlbum.present) {
      map['was_in_smart_album'] = Variable<bool>(wasInSmartAlbum.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (assetType.present) {
      map['asset_type'] = Variable<int>(assetType.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (originalBytes.present) {
      map['original_bytes'] = Variable<int>(originalBytes.value);
    }
    if (newBytes.present) {
      map['new_bytes'] = Variable<int>(newBytes.value);
    }
    if (backupPath.present) {
      map['backup_path'] = Variable<String>(backupPath.value);
    }
    if (newAssetId.present) {
      map['new_asset_id'] = Variable<String>(newAssetId.value);
    }
    if (state.present) {
      map['state'] = Variable<int>(state.value);
    }
    if (deletedAtMs.present) {
      map['deleted_at_ms'] = Variable<int>(deletedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrashEntriesCompanion(')
          ..write('id: $id, ')
          ..write('originalAssetId: $originalAssetId, ')
          ..write('filename: $filename, ')
          ..write('createdDateMs: $createdDateMs, ')
          ..write('modifiedDateMs: $modifiedDateMs, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('userAlbumIds: $userAlbumIds, ')
          ..write('wasInSmartAlbum: $wasInSmartAlbum, ')
          ..write('mimeType: $mimeType, ')
          ..write('assetType: $assetType, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('originalBytes: $originalBytes, ')
          ..write('newBytes: $newBytes, ')
          ..write('backupPath: $backupPath, ')
          ..write('newAssetId: $newAssetId, ')
          ..write('state: $state, ')
          ..write('deletedAtMs: $deletedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MediaIndexDatabase extends GeneratedDatabase {
  _$MediaIndexDatabase(QueryExecutor e) : super(e);
  $MediaIndexDatabaseManager get managers => $MediaIndexDatabaseManager(this);
  late final $MediaAssetsTable mediaAssets = $MediaAssetsTable(this);
  late final $TrashEntriesTable trashEntries = $TrashEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    mediaAssets,
    trashEntries,
  ];
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
typedef $$TrashEntriesTableCreateCompanionBuilder =
    TrashEntriesCompanion Function({
      required String id,
      required String originalAssetId,
      Value<String> filename,
      Value<int> createdDateMs,
      Value<int> modifiedDateMs,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<bool> isFavorite,
      Value<String> userAlbumIds,
      Value<bool> wasInSmartAlbum,
      Value<String?> mimeType,
      Value<int> assetType,
      Value<int> width,
      Value<int> height,
      Value<int> originalBytes,
      Value<int> newBytes,
      Value<String> backupPath,
      Value<String?> newAssetId,
      Value<int> state,
      Value<int> deletedAtMs,
      Value<int> rowid,
    });
typedef $$TrashEntriesTableUpdateCompanionBuilder =
    TrashEntriesCompanion Function({
      Value<String> id,
      Value<String> originalAssetId,
      Value<String> filename,
      Value<int> createdDateMs,
      Value<int> modifiedDateMs,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<bool> isFavorite,
      Value<String> userAlbumIds,
      Value<bool> wasInSmartAlbum,
      Value<String?> mimeType,
      Value<int> assetType,
      Value<int> width,
      Value<int> height,
      Value<int> originalBytes,
      Value<int> newBytes,
      Value<String> backupPath,
      Value<String?> newAssetId,
      Value<int> state,
      Value<int> deletedAtMs,
      Value<int> rowid,
    });

class $$TrashEntriesTableFilterComposer
    extends Composer<_$MediaIndexDatabase, $TrashEntriesTable> {
  $$TrashEntriesTableFilterComposer({
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

  ColumnFilters<String> get originalAssetId => $composableBuilder(
    column: $table.originalAssetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdDateMs => $composableBuilder(
    column: $table.createdDateMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedDateMs => $composableBuilder(
    column: $table.modifiedDateMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userAlbumIds => $composableBuilder(
    column: $table.userAlbumIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get wasInSmartAlbum => $composableBuilder(
    column: $table.wasInSmartAlbum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get assetType => $composableBuilder(
    column: $table.assetType,
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

  ColumnFilters<int> get originalBytes => $composableBuilder(
    column: $table.originalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get newBytes => $composableBuilder(
    column: $table.newBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backupPath => $composableBuilder(
    column: $table.backupPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get newAssetId => $composableBuilder(
    column: $table.newAssetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAtMs => $composableBuilder(
    column: $table.deletedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrashEntriesTableOrderingComposer
    extends Composer<_$MediaIndexDatabase, $TrashEntriesTable> {
  $$TrashEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get originalAssetId => $composableBuilder(
    column: $table.originalAssetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdDateMs => $composableBuilder(
    column: $table.createdDateMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedDateMs => $composableBuilder(
    column: $table.modifiedDateMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userAlbumIds => $composableBuilder(
    column: $table.userAlbumIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get wasInSmartAlbum => $composableBuilder(
    column: $table.wasInSmartAlbum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get assetType => $composableBuilder(
    column: $table.assetType,
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

  ColumnOrderings<int> get originalBytes => $composableBuilder(
    column: $table.originalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get newBytes => $composableBuilder(
    column: $table.newBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backupPath => $composableBuilder(
    column: $table.backupPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get newAssetId => $composableBuilder(
    column: $table.newAssetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAtMs => $composableBuilder(
    column: $table.deletedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrashEntriesTableAnnotationComposer
    extends Composer<_$MediaIndexDatabase, $TrashEntriesTable> {
  $$TrashEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get originalAssetId => $composableBuilder(
    column: $table.originalAssetId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<int> get createdDateMs => $composableBuilder(
    column: $table.createdDateMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get modifiedDateMs => $composableBuilder(
    column: $table.modifiedDateMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userAlbumIds => $composableBuilder(
    column: $table.userAlbumIds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get wasInSmartAlbum => $composableBuilder(
    column: $table.wasInSmartAlbum,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get assetType =>
      $composableBuilder(column: $table.assetType, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get originalBytes => $composableBuilder(
    column: $table.originalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get newBytes =>
      $composableBuilder(column: $table.newBytes, builder: (column) => column);

  GeneratedColumn<String> get backupPath => $composableBuilder(
    column: $table.backupPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get newAssetId => $composableBuilder(
    column: $table.newAssetId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get deletedAtMs => $composableBuilder(
    column: $table.deletedAtMs,
    builder: (column) => column,
  );
}

class $$TrashEntriesTableTableManager
    extends
        RootTableManager<
          _$MediaIndexDatabase,
          $TrashEntriesTable,
          TrashEntry,
          $$TrashEntriesTableFilterComposer,
          $$TrashEntriesTableOrderingComposer,
          $$TrashEntriesTableAnnotationComposer,
          $$TrashEntriesTableCreateCompanionBuilder,
          $$TrashEntriesTableUpdateCompanionBuilder,
          (
            TrashEntry,
            BaseReferences<
              _$MediaIndexDatabase,
              $TrashEntriesTable,
              TrashEntry
            >,
          ),
          TrashEntry,
          PrefetchHooks Function()
        > {
  $$TrashEntriesTableTableManager(
    _$MediaIndexDatabase db,
    $TrashEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrashEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrashEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrashEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> originalAssetId = const Value.absent(),
                Value<String> filename = const Value.absent(),
                Value<int> createdDateMs = const Value.absent(),
                Value<int> modifiedDateMs = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String> userAlbumIds = const Value.absent(),
                Value<bool> wasInSmartAlbum = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int> assetType = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int> originalBytes = const Value.absent(),
                Value<int> newBytes = const Value.absent(),
                Value<String> backupPath = const Value.absent(),
                Value<String?> newAssetId = const Value.absent(),
                Value<int> state = const Value.absent(),
                Value<int> deletedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrashEntriesCompanion(
                id: id,
                originalAssetId: originalAssetId,
                filename: filename,
                createdDateMs: createdDateMs,
                modifiedDateMs: modifiedDateMs,
                latitude: latitude,
                longitude: longitude,
                isFavorite: isFavorite,
                userAlbumIds: userAlbumIds,
                wasInSmartAlbum: wasInSmartAlbum,
                mimeType: mimeType,
                assetType: assetType,
                width: width,
                height: height,
                originalBytes: originalBytes,
                newBytes: newBytes,
                backupPath: backupPath,
                newAssetId: newAssetId,
                state: state,
                deletedAtMs: deletedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String originalAssetId,
                Value<String> filename = const Value.absent(),
                Value<int> createdDateMs = const Value.absent(),
                Value<int> modifiedDateMs = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String> userAlbumIds = const Value.absent(),
                Value<bool> wasInSmartAlbum = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int> assetType = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int> originalBytes = const Value.absent(),
                Value<int> newBytes = const Value.absent(),
                Value<String> backupPath = const Value.absent(),
                Value<String?> newAssetId = const Value.absent(),
                Value<int> state = const Value.absent(),
                Value<int> deletedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrashEntriesCompanion.insert(
                id: id,
                originalAssetId: originalAssetId,
                filename: filename,
                createdDateMs: createdDateMs,
                modifiedDateMs: modifiedDateMs,
                latitude: latitude,
                longitude: longitude,
                isFavorite: isFavorite,
                userAlbumIds: userAlbumIds,
                wasInSmartAlbum: wasInSmartAlbum,
                mimeType: mimeType,
                assetType: assetType,
                width: width,
                height: height,
                originalBytes: originalBytes,
                newBytes: newBytes,
                backupPath: backupPath,
                newAssetId: newAssetId,
                state: state,
                deletedAtMs: deletedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrashEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$MediaIndexDatabase,
      $TrashEntriesTable,
      TrashEntry,
      $$TrashEntriesTableFilterComposer,
      $$TrashEntriesTableOrderingComposer,
      $$TrashEntriesTableAnnotationComposer,
      $$TrashEntriesTableCreateCompanionBuilder,
      $$TrashEntriesTableUpdateCompanionBuilder,
      (
        TrashEntry,
        BaseReferences<_$MediaIndexDatabase, $TrashEntriesTable, TrashEntry>,
      ),
      TrashEntry,
      PrefetchHooks Function()
    >;

class $MediaIndexDatabaseManager {
  final _$MediaIndexDatabase _db;
  $MediaIndexDatabaseManager(this._db);
  $$MediaAssetsTableTableManager get mediaAssets =>
      $$MediaAssetsTableTableManager(_db, _db.mediaAssets);
  $$TrashEntriesTableTableManager get trashEntries =>
      $$TrashEntriesTableTableManager(_db, _db.trashEntries);
}
