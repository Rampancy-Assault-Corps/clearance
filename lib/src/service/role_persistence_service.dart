import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:racbot_nyxx/src/util/app_logger.dart';

class RolePersistenceService {
  final String dataDirPath;
  final bool atomicWrites;
  final AppLogger logger;

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');
  final Map<String, PersistedRoleEntry> _entries =
      <String, PersistedRoleEntry>{};
  late final File _storageFile;
  bool _loaded = false;

  RolePersistenceService({
    required this.dataDirPath,
    required this.atomicWrites,
    required this.logger,
  }) {
    _storageFile = File(p.join(dataDirPath, 'role_persistence.json'));
  }

  PersistedRoleEntry? loadEntry({required int guildId, required int userId}) {
    _ensureLoaded();
    return _entries[_entryKey(guildId: guildId, userId: userId)];
  }

  void saveEntry({
    required int guildId,
    required int userId,
    required List<int> roleIds,
  }) {
    _ensureLoaded();

    List<int> normalizedRoleIds = _normalizeRoleIds(roleIds);
    String key = _entryKey(guildId: guildId, userId: userId);
    if (normalizedRoleIds.isEmpty) {
      _entries.remove(key);
      _writeEntries();
      return;
    }

    _entries[key] = PersistedRoleEntry(
      guildId: guildId,
      userId: userId,
      roleIds: normalizedRoleIds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _writeEntries();
  }

  void deleteEntry({required int guildId, required int userId}) {
    _ensureLoaded();

    String key = _entryKey(guildId: guildId, userId: userId);
    PersistedRoleEntry? removedEntry = _entries.remove(key);
    if (removedEntry == null) {
      return;
    }

    _writeEntries();
  }

  Future<void> close() => Future<void>.value();

  void _ensureLoaded() {
    if (_loaded) {
      return;
    }

    _readEntriesFromDisk();
    _loaded = true;
  }

  void _readEntriesFromDisk() {
    if (!_storageFile.existsSync()) {
      return;
    }

    String rawContent;
    try {
      rawContent = _storageFile.readAsStringSync();
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to read role persistence file ${_storageFile.path}.',
        error,
        stackTrace,
      );
      return;
    }

    if (rawContent.trim().isEmpty) {
      return;
    }

    try {
      Object? decoded = jsonDecode(rawContent);
      if (decoded is! Map) {
        logger.warning(
          'Ignoring role persistence file because the root JSON value is not an object.',
        );
        return;
      }

      Object? rawEntries = decoded['entries'];
      if (rawEntries is! List) {
        logger.warning(
          'Ignoring role persistence file because the entries list is missing.',
        );
        return;
      }

      for (Object? rawEntry in rawEntries) {
        Map<String, Object?>? json = _jsonObject(rawEntry);
        if (json == null) {
          continue;
        }

        try {
          PersistedRoleEntry entry = PersistedRoleEntry.fromJson(json);
          _entries[_entryKey(guildId: entry.guildId, userId: entry.userId)] =
              entry;
        } on FormatException catch (error) {
          logger.warning('Skipping invalid persisted role entry: $error');
        }
      }
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to parse role persistence file ${_storageFile.path}.',
        error,
        stackTrace,
      );
      _entries.clear();
    }
  }

  void _writeEntries() {
    if (_entries.isEmpty) {
      try {
        if (_storageFile.existsSync()) {
          _storageFile.deleteSync();
        }
      } on Object catch (error, stackTrace) {
        logger.severe(
          'Failed to delete empty role persistence file ${_storageFile.path}.',
          error,
          stackTrace,
        );
      }
      return;
    }

    List<PersistedRoleEntry> entries = _entries.values.toList();
    entries.sort((PersistedRoleEntry left, PersistedRoleEntry right) {
      int guildCompare = left.guildId.compareTo(right.guildId);
      if (guildCompare != 0) {
        return guildCompare;
      }
      return left.userId.compareTo(right.userId);
    });

    List<Map<String, Object>> serializedEntries = <Map<String, Object>>[];
    for (PersistedRoleEntry entry in entries) {
      serializedEntries.add(entry.toJson());
    }

    String payload =
        '${_encoder.convert(<String, Object>{'entries': serializedEntries})}\n';
    try {
      if (atomicWrites) {
        _writeAtomic(payload);
      } else {
        _storageFile.writeAsStringSync(payload, flush: true);
      }
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to write role persistence file ${_storageFile.path}.',
        error,
        stackTrace,
      );
    }
  }

  void _writeAtomic(String payload) {
    File tempFile = File('${_storageFile.path}.tmp');
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    tempFile.writeAsStringSync(payload, flush: true);
    if (_storageFile.existsSync()) {
      _storageFile.deleteSync();
    }
    tempFile.renameSync(_storageFile.path);
  }

  Map<String, Object?>? _jsonObject(Object? value) {
    if (value is! Map) {
      return null;
    }

    Map<String, Object?> json = <String, Object?>{};
    for (MapEntry<Object?, Object?> entry in value.entries) {
      Object? key = entry.key;
      if (key is! String) {
        continue;
      }

      json[key] = entry.value;
    }
    return json;
  }

  String _entryKey({required int guildId, required int userId}) =>
      '$guildId:$userId';

  List<int> _normalizeRoleIds(List<int> roleIds) {
    List<int> normalizedRoleIds = <int>[];
    for (int roleId in roleIds) {
      if (roleId <= 0 || normalizedRoleIds.contains(roleId)) {
        continue;
      }
      normalizedRoleIds.add(roleId);
    }
    normalizedRoleIds.sort();
    return normalizedRoleIds;
  }
}

class PersistedRoleEntry {
  final int guildId;
  final int userId;
  final List<int> roleIds;
  final int updatedAt;

  const PersistedRoleEntry({
    required this.guildId,
    required this.userId,
    required this.roleIds,
    required this.updatedAt,
  });

  factory PersistedRoleEntry.fromJson(Map<String, Object?> json) {
    int? guildId = _readInt(json['guild_id']);
    int? userId = _readInt(json['user_id']);
    if (guildId == null || guildId <= 0) {
      throw const FormatException('guild_id must be a positive integer.');
    }
    if (userId == null || userId <= 0) {
      throw const FormatException('user_id must be a positive integer.');
    }

    List<int> roleIds = <int>[];
    Object? rawRoleIds = json['role_ids'];
    if (rawRoleIds is List) {
      for (Object? rawRoleId in rawRoleIds) {
        int? roleId = _readInt(rawRoleId);
        if (roleId == null || roleId <= 0 || roleIds.contains(roleId)) {
          continue;
        }
        roleIds.add(roleId);
      }
    }
    roleIds.sort();

    int updatedAt = _readInt(json['updated_at']) ?? 0;
    return PersistedRoleEntry(
      guildId: guildId,
      userId: userId,
      roleIds: roleIds,
      updatedAt: updatedAt,
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  Map<String, Object> toJson() => <String, Object>{
    'guild_id': guildId,
    'user_id': userId,
    'role_ids': roleIds,
    'updated_at': updatedAt,
  };
}
