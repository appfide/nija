// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ClipItemsTable extends ClipItems
    with TableInfo<$ClipItemsTable, ClipRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClipItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _blobRefMeta = const VerificationMeta(
    'blobRef',
  );
  @override
  late final GeneratedColumn<String> blobRef = GeneratedColumn<String>(
    'blob_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _encryptedMeta = const VerificationMeta(
    'encrypted',
  );
  @override
  late final GeneratedColumn<bool> encrypted = GeneratedColumn<bool>(
    'encrypted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("encrypted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<String> nonce = GeneratedColumn<String>(
    'nonce',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _targetDeviceIdMeta = const VerificationMeta(
    'targetDeviceId',
  );
  @override
  late final GeneratedColumn<String> targetDeviceId = GeneratedColumn<String>(
    'target_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localOnlyMeta = const VerificationMeta(
    'localOnly',
  );
  @override
  late final GeneratedColumn<bool> localOnly = GeneratedColumn<bool>(
    'local_only',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("local_only" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    deviceName,
    contentType,
    content,
    blobRef,
    contentHash,
    sizeBytes,
    encrypted,
    nonce,
    createdAt,
    updatedAt,
    deletedAt,
    synced,
    pinned,
    targetDeviceId,
    localOnly,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'clip_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClipRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('blob_ref')) {
      context.handle(
        _blobRefMeta,
        blobRef.isAcceptableOrUnknown(data['blob_ref']!, _blobRefMeta),
      );
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('encrypted')) {
      context.handle(
        _encryptedMeta,
        encrypted.isAcceptableOrUnknown(data['encrypted']!, _encryptedMeta),
      );
    }
    if (data.containsKey('nonce')) {
      context.handle(
        _nonceMeta,
        nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('target_device_id')) {
      context.handle(
        _targetDeviceIdMeta,
        targetDeviceId.isAcceptableOrUnknown(
          data['target_device_id']!,
          _targetDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('local_only')) {
      context.handle(
        _localOnlyMeta,
        localOnly.isAcceptableOrUnknown(data['local_only']!, _localOnlyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClipRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClipRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      blobRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blob_ref'],
      ),
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      encrypted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}encrypted'],
      )!,
      nonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nonce'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      targetDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_device_id'],
      ),
      localOnly: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}local_only'],
      )!,
    );
  }

  @override
  $ClipItemsTable createAlias(String alias) {
    return $ClipItemsTable(attachedDatabase, alias);
  }
}

class ClipRow extends DataClass implements Insertable<ClipRow> {
  final String id;
  final String deviceId;
  final String deviceName;
  final String contentType;
  final String content;
  final String? blobRef;
  final String contentHash;
  final int sizeBytes;
  final bool encrypted;
  final String? nonce;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final bool synced;
  final bool pinned;
  final String? targetDeviceId;

  /// Captured while this device kept its copies to itself (database sync
  /// off, receive-only, paused): never sent, and never sent later.
  final bool localOnly;
  const ClipRow({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.contentType,
    required this.content,
    this.blobRef,
    required this.contentHash,
    required this.sizeBytes,
    required this.encrypted,
    this.nonce,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.synced,
    required this.pinned,
    this.targetDeviceId,
    required this.localOnly,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['device_name'] = Variable<String>(deviceName);
    map['content_type'] = Variable<String>(contentType);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || blobRef != null) {
      map['blob_ref'] = Variable<String>(blobRef);
    }
    map['content_hash'] = Variable<String>(contentHash);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['encrypted'] = Variable<bool>(encrypted);
    if (!nullToAbsent || nonce != null) {
      map['nonce'] = Variable<String>(nonce);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['synced'] = Variable<bool>(synced);
    map['pinned'] = Variable<bool>(pinned);
    if (!nullToAbsent || targetDeviceId != null) {
      map['target_device_id'] = Variable<String>(targetDeviceId);
    }
    map['local_only'] = Variable<bool>(localOnly);
    return map;
  }

  ClipItemsCompanion toCompanion(bool nullToAbsent) {
    return ClipItemsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      deviceName: Value(deviceName),
      contentType: Value(contentType),
      content: Value(content),
      blobRef: blobRef == null && nullToAbsent
          ? const Value.absent()
          : Value(blobRef),
      contentHash: Value(contentHash),
      sizeBytes: Value(sizeBytes),
      encrypted: Value(encrypted),
      nonce: nonce == null && nullToAbsent
          ? const Value.absent()
          : Value(nonce),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      synced: Value(synced),
      pinned: Value(pinned),
      targetDeviceId: targetDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDeviceId),
      localOnly: Value(localOnly),
    );
  }

  factory ClipRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClipRow(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      contentType: serializer.fromJson<String>(json['contentType']),
      content: serializer.fromJson<String>(json['content']),
      blobRef: serializer.fromJson<String?>(json['blobRef']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      encrypted: serializer.fromJson<bool>(json['encrypted']),
      nonce: serializer.fromJson<String?>(json['nonce']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      synced: serializer.fromJson<bool>(json['synced']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      targetDeviceId: serializer.fromJson<String?>(json['targetDeviceId']),
      localOnly: serializer.fromJson<bool>(json['localOnly']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'deviceName': serializer.toJson<String>(deviceName),
      'contentType': serializer.toJson<String>(contentType),
      'content': serializer.toJson<String>(content),
      'blobRef': serializer.toJson<String?>(blobRef),
      'contentHash': serializer.toJson<String>(contentHash),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'encrypted': serializer.toJson<bool>(encrypted),
      'nonce': serializer.toJson<String?>(nonce),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'synced': serializer.toJson<bool>(synced),
      'pinned': serializer.toJson<bool>(pinned),
      'targetDeviceId': serializer.toJson<String?>(targetDeviceId),
      'localOnly': serializer.toJson<bool>(localOnly),
    };
  }

  ClipRow copyWith({
    String? id,
    String? deviceId,
    String? deviceName,
    String? contentType,
    String? content,
    Value<String?> blobRef = const Value.absent(),
    String? contentHash,
    int? sizeBytes,
    bool? encrypted,
    Value<String?> nonce = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? synced,
    bool? pinned,
    Value<String?> targetDeviceId = const Value.absent(),
    bool? localOnly,
  }) => ClipRow(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    contentType: contentType ?? this.contentType,
    content: content ?? this.content,
    blobRef: blobRef.present ? blobRef.value : this.blobRef,
    contentHash: contentHash ?? this.contentHash,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    encrypted: encrypted ?? this.encrypted,
    nonce: nonce.present ? nonce.value : this.nonce,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    synced: synced ?? this.synced,
    pinned: pinned ?? this.pinned,
    targetDeviceId: targetDeviceId.present
        ? targetDeviceId.value
        : this.targetDeviceId,
    localOnly: localOnly ?? this.localOnly,
  );
  ClipRow copyWithCompanion(ClipItemsCompanion data) {
    return ClipRow(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      content: data.content.present ? data.content.value : this.content,
      blobRef: data.blobRef.present ? data.blobRef.value : this.blobRef,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      encrypted: data.encrypted.present ? data.encrypted.value : this.encrypted,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      synced: data.synced.present ? data.synced.value : this.synced,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      targetDeviceId: data.targetDeviceId.present
          ? data.targetDeviceId.value
          : this.targetDeviceId,
      localOnly: data.localOnly.present ? data.localOnly.value : this.localOnly,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClipRow(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('contentType: $contentType, ')
          ..write('content: $content, ')
          ..write('blobRef: $blobRef, ')
          ..write('contentHash: $contentHash, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('encrypted: $encrypted, ')
          ..write('nonce: $nonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('synced: $synced, ')
          ..write('pinned: $pinned, ')
          ..write('targetDeviceId: $targetDeviceId, ')
          ..write('localOnly: $localOnly')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deviceId,
    deviceName,
    contentType,
    content,
    blobRef,
    contentHash,
    sizeBytes,
    encrypted,
    nonce,
    createdAt,
    updatedAt,
    deletedAt,
    synced,
    pinned,
    targetDeviceId,
    localOnly,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClipRow &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.deviceName == this.deviceName &&
          other.contentType == this.contentType &&
          other.content == this.content &&
          other.blobRef == this.blobRef &&
          other.contentHash == this.contentHash &&
          other.sizeBytes == this.sizeBytes &&
          other.encrypted == this.encrypted &&
          other.nonce == this.nonce &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.synced == this.synced &&
          other.pinned == this.pinned &&
          other.targetDeviceId == this.targetDeviceId &&
          other.localOnly == this.localOnly);
}

class ClipItemsCompanion extends UpdateCompanion<ClipRow> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<String> deviceName;
  final Value<String> contentType;
  final Value<String> content;
  final Value<String?> blobRef;
  final Value<String> contentHash;
  final Value<int> sizeBytes;
  final Value<bool> encrypted;
  final Value<String?> nonce;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> synced;
  final Value<bool> pinned;
  final Value<String?> targetDeviceId;
  final Value<bool> localOnly;
  final Value<int> rowid;
  const ClipItemsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.contentType = const Value.absent(),
    this.content = const Value.absent(),
    this.blobRef = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.encrypted = const Value.absent(),
    this.nonce = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.synced = const Value.absent(),
    this.pinned = const Value.absent(),
    this.targetDeviceId = const Value.absent(),
    this.localOnly = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClipItemsCompanion.insert({
    required String id,
    required String deviceId,
    this.deviceName = const Value.absent(),
    this.contentType = const Value.absent(),
    this.content = const Value.absent(),
    this.blobRef = const Value.absent(),
    required String contentHash,
    this.sizeBytes = const Value.absent(),
    this.encrypted = const Value.absent(),
    this.nonce = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.synced = const Value.absent(),
    this.pinned = const Value.absent(),
    this.targetDeviceId = const Value.absent(),
    this.localOnly = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deviceId = Value(deviceId),
       contentHash = Value(contentHash),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ClipRow> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<String>? deviceName,
    Expression<String>? contentType,
    Expression<String>? content,
    Expression<String>? blobRef,
    Expression<String>? contentHash,
    Expression<int>? sizeBytes,
    Expression<bool>? encrypted,
    Expression<String>? nonce,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? synced,
    Expression<bool>? pinned,
    Expression<String>? targetDeviceId,
    Expression<bool>? localOnly,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (contentType != null) 'content_type': contentType,
      if (content != null) 'content': content,
      if (blobRef != null) 'blob_ref': blobRef,
      if (contentHash != null) 'content_hash': contentHash,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (encrypted != null) 'encrypted': encrypted,
      if (nonce != null) 'nonce': nonce,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (synced != null) 'synced': synced,
      if (pinned != null) 'pinned': pinned,
      if (targetDeviceId != null) 'target_device_id': targetDeviceId,
      if (localOnly != null) 'local_only': localOnly,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClipItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? deviceId,
    Value<String>? deviceName,
    Value<String>? contentType,
    Value<String>? content,
    Value<String?>? blobRef,
    Value<String>? contentHash,
    Value<int>? sizeBytes,
    Value<bool>? encrypted,
    Value<String?>? nonce,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? synced,
    Value<bool>? pinned,
    Value<String?>? targetDeviceId,
    Value<bool>? localOnly,
    Value<int>? rowid,
  }) {
    return ClipItemsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      contentType: contentType ?? this.contentType,
      content: content ?? this.content,
      blobRef: blobRef ?? this.blobRef,
      contentHash: contentHash ?? this.contentHash,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      encrypted: encrypted ?? this.encrypted,
      nonce: nonce ?? this.nonce,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      synced: synced ?? this.synced,
      pinned: pinned ?? this.pinned,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      localOnly: localOnly ?? this.localOnly,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (blobRef.present) {
      map['blob_ref'] = Variable<String>(blobRef.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (encrypted.present) {
      map['encrypted'] = Variable<bool>(encrypted.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<String>(nonce.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (targetDeviceId.present) {
      map['target_device_id'] = Variable<String>(targetDeviceId.value);
    }
    if (localOnly.present) {
      map['local_only'] = Variable<bool>(localOnly.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClipItemsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('contentType: $contentType, ')
          ..write('content: $content, ')
          ..write('blobRef: $blobRef, ')
          ..write('contentHash: $contentHash, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('encrypted: $encrypted, ')
          ..write('nonce: $nonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('synced: $synced, ')
          ..write('pinned: $pinned, ')
          ..write('targetDeviceId: $targetDeviceId, ')
          ..write('localOnly: $localOnly, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final String key;
  final String value;
  const SyncMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(key: Value(key), value: Value(value));
  }

  factory SyncMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaData copyWith({String? key, String? value}) =>
      SyncMetaData(key: key ?? this.key, value: value ?? this.value);
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ClipItemsTable clipItems = $ClipItemsTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [clipItems, syncMeta];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$ClipItemsTableCreateCompanionBuilder =
    ClipItemsCompanion Function({
      required String id,
      required String deviceId,
      Value<String> deviceName,
      Value<String> contentType,
      Value<String> content,
      Value<String?> blobRef,
      required String contentHash,
      Value<int> sizeBytes,
      Value<bool> encrypted,
      Value<String?> nonce,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> synced,
      Value<bool> pinned,
      Value<String?> targetDeviceId,
      Value<bool> localOnly,
      Value<int> rowid,
    });
typedef $$ClipItemsTableUpdateCompanionBuilder =
    ClipItemsCompanion Function({
      Value<String> id,
      Value<String> deviceId,
      Value<String> deviceName,
      Value<String> contentType,
      Value<String> content,
      Value<String?> blobRef,
      Value<String> contentHash,
      Value<int> sizeBytes,
      Value<bool> encrypted,
      Value<String?> nonce,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> synced,
      Value<bool> pinned,
      Value<String?> targetDeviceId,
      Value<bool> localOnly,
      Value<int> rowid,
    });

class $$ClipItemsTableFilterComposer
    extends Composer<_$AppDatabase, $ClipItemsTable> {
  $$ClipItemsTableFilterComposer({
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

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blobRef => $composableBuilder(
    column: $table.blobRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get encrypted => $composableBuilder(
    column: $table.encrypted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetDeviceId => $composableBuilder(
    column: $table.targetDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get localOnly => $composableBuilder(
    column: $table.localOnly,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClipItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClipItemsTable> {
  $$ClipItemsTableOrderingComposer({
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

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blobRef => $composableBuilder(
    column: $table.blobRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get encrypted => $composableBuilder(
    column: $table.encrypted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetDeviceId => $composableBuilder(
    column: $table.targetDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get localOnly => $composableBuilder(
    column: $table.localOnly,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClipItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClipItemsTable> {
  $$ClipItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get blobRef =>
      $composableBuilder(column: $table.blobRef, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<bool> get encrypted =>
      $composableBuilder(column: $table.encrypted, builder: (column) => column);

  GeneratedColumn<String> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<String> get targetDeviceId => $composableBuilder(
    column: $table.targetDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get localOnly =>
      $composableBuilder(column: $table.localOnly, builder: (column) => column);
}

class $$ClipItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClipItemsTable,
          ClipRow,
          $$ClipItemsTableFilterComposer,
          $$ClipItemsTableOrderingComposer,
          $$ClipItemsTableAnnotationComposer,
          $$ClipItemsTableCreateCompanionBuilder,
          $$ClipItemsTableUpdateCompanionBuilder,
          (ClipRow, BaseReferences<_$AppDatabase, $ClipItemsTable, ClipRow>),
          ClipRow,
          PrefetchHooks Function()
        > {
  $$ClipItemsTableTableManager(_$AppDatabase db, $ClipItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClipItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClipItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClipItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> blobRef = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<bool> encrypted = const Value.absent(),
                Value<String?> nonce = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<String?> targetDeviceId = const Value.absent(),
                Value<bool> localOnly = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClipItemsCompanion(
                id: id,
                deviceId: deviceId,
                deviceName: deviceName,
                contentType: contentType,
                content: content,
                blobRef: blobRef,
                contentHash: contentHash,
                sizeBytes: sizeBytes,
                encrypted: encrypted,
                nonce: nonce,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                synced: synced,
                pinned: pinned,
                targetDeviceId: targetDeviceId,
                localOnly: localOnly,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deviceId,
                Value<String> deviceName = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> blobRef = const Value.absent(),
                required String contentHash,
                Value<int> sizeBytes = const Value.absent(),
                Value<bool> encrypted = const Value.absent(),
                Value<String?> nonce = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<String?> targetDeviceId = const Value.absent(),
                Value<bool> localOnly = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClipItemsCompanion.insert(
                id: id,
                deviceId: deviceId,
                deviceName: deviceName,
                contentType: contentType,
                content: content,
                blobRef: blobRef,
                contentHash: contentHash,
                sizeBytes: sizeBytes,
                encrypted: encrypted,
                nonce: nonce,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                synced: synced,
                pinned: pinned,
                targetDeviceId: targetDeviceId,
                localOnly: localOnly,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ClipItemsTable, ClipRow>(table),
                  BaseReferences<_$AppDatabase, $ClipItemsTable, ClipRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClipItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClipItemsTable,
      ClipRow,
      $$ClipItemsTableFilterComposer,
      $$ClipItemsTableOrderingComposer,
      $$ClipItemsTableAnnotationComposer,
      $$ClipItemsTableCreateCompanionBuilder,
      $$ClipItemsTableUpdateCompanionBuilder,
      (ClipRow, BaseReferences<_$AppDatabase, $ClipItemsTable, ClipRow>),
      ClipRow,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaData,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaData,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
          ),
          SyncMetaData,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMetaTable, SyncMetaData>(table),
                  BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaData,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (
        SyncMetaData,
        BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
      ),
      SyncMetaData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ClipItemsTableTableManager get clipItems =>
      $$ClipItemsTableTableManager(_db, _db.clipItems);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
}
