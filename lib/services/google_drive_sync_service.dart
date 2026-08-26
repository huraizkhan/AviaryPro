import 'dart:async';
import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import 'google_drive_backup_service.dart';

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SyncNeedsMergeChoiceException extends SyncException {
  const SyncNeedsMergeChoiceException()
      : super(
          'Cloud sync data already exists while this device also contains local data.',
        );
}

class SyncResult {
  const SyncResult({
    required this.downloadedChanges,
    required this.uploadedChanges,
    required this.syncedAt,
  });

  final int downloadedChanges;
  final int uploadedChanges;
  final DateTime syncedAt;
}

class GoogleDriveSyncService {
  GoogleDriveSyncService._();

  static final GoogleDriveSyncService instance = GoogleDriveSyncService._();

  static const String _filePrefix = 'aviarypro_sync_';
  static const String _deviceIdKey = 'drive_sync_device_id';
  static const String _enabledKey = 'drive_sync_enabled';
  static const String _lastSyncAtKey = 'drive_sync_last_success_at';
  static const String _lastSyncErrorKey = 'drive_sync_last_error';
  static const String _remoteSignatureKey = 'drive_sync_remote_signature';

  bool _running = false;
  DateTime? _lastAttemptAt;

  Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<DateTime?> get lastSuccessfulSyncAt async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastSyncAtKey);
    return value == null ? null : DateTime.tryParse(value)?.toLocal();
  }

  Future<String?> get lastSyncError async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSyncErrorKey);
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await prefs.setString(_deviceIdKey, created);
    return created;
  }

  Future<SyncResult?> bootstrapEmptyDeviceFromCloud() async {
    if (_running || await DatabaseHelper.instance.hasUserData()) return null;

    final backupService = GoogleDriveBackupService.instance;
    // Startup/bootstrap must stay silent. If Google has not been explicitly
    // connected in this app session, skip cloud work instead of showing UI.
    if (backupService.currentEmail == null) return null;

    DriveSession? session;
    try {
      session = await backupService.openDrive(interactive: false);
      final remoteFiles = await _listSyncFiles(session.api);
      if (remoteFiles.isEmpty) return null;
    } catch (_) {
      return null;
    } finally {
      session?.close();
    }

    try {
      final result = await syncNow(interactive: false);
      await setEnabled(true);
      return result;
    } catch (error) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncErrorKey, error.toString());
      return null;
    }
  }

  Future<SyncResult?> runAutomaticSync() async {
    if (!await enabled) return null;
    if (_running) return null;

    try {
      final backupService = GoogleDriveBackupService.instance;
      // Restore the previously connected account silently after app restart.
      if (backupService.currentEmail == null) {
        await backupService.restorePreviousSession();
      }
      if (backupService.currentEmail == null) return null;

      final hasLocalChanges =
          await DatabaseHelper.instance.hasPendingSyncChanges();
      final now = DateTime.now();
      final minimumGap = hasLocalChanges
          ? const Duration(seconds: 2)
          : const Duration(seconds: 15);
      if (_lastAttemptAt != null && now.difference(_lastAttemptAt!) < minimumGap) {
        return null;
      }
      _lastAttemptAt = now;

      if (!hasLocalChanges) {
        DriveSession? probeSession;
        try {
          probeSession = await backupService.openDrive(interactive: false);
          final files = await _listSyncFiles(probeSession.api);
          final signature = _remoteSignature(files);
          final prefs = await SharedPreferences.getInstance();
          if (signature == prefs.getString(_remoteSignatureKey)) return null;
        } finally {
          probeSession?.close();
        }
      }

      return await syncNow(interactive: false);
    } catch (error) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncErrorKey, error.toString());
      return null;
    }
  }

  Future<SyncResult> syncNow({
    bool interactive = true,
    bool allowInitialMerge = false,
  }) async {
    if (_running) {
      throw const SyncException('A sync is already running.');
    }
    _running = true;
    final backupService = GoogleDriveBackupService.instance;
    DriveSession? session;

    try {
      final deviceId = await _deviceId();
      session = await backupService.openDrive(interactive: interactive);
      final remoteFiles = await _listSyncFiles(session.api);
      final localHasState = await DatabaseHelper.instance.hasSyncDeviceState();
      final localHasData = await DatabaseHelper.instance.hasUserData();

      if (!localHasState && localHasData && remoteFiles.isNotEmpty) {
        if (!allowInitialMerge) {
          throw const SyncNeedsMergeChoiceException();
        }
        await DatabaseHelper.instance.seedAllLocalDataForSync(deviceId);
      } else if (!localHasState && localHasData && remoteFiles.isEmpty) {
        await DatabaseHelper.instance.seedAllLocalDataForSync(deviceId);
      }

      final prepared =
          await DatabaseHelper.instance.prepareSyncDeviceState(deviceId);
      final pendingIds = (prepared['pendingIds'] as List)
          .map((value) => value.toString())
          .toList();
      final localRecords = _recordList(prepared['records']);
      final ownFileName = '$_filePrefix$deviceId.json';

      if (localRecords.isNotEmpty) {
        await _uploadDeviceState(
          session.api,
          fileName: ownFileName,
          deviceId: deviceId,
          records: localRecords,
          existingFile: remoteFiles
              .where((file) => file.name == ownFileName)
              .firstOrNull,
        );
      }

      final refreshedFiles = await _listSyncFiles(session.api);
      final allRemoteRecords = <Map<String, dynamic>>[];
      for (final file in refreshedFiles) {
        allRemoteRecords.addAll(await _downloadRecords(session.api, file.id!));
      }
      final globalRecords = _mergeLatest(allRemoteRecords);
      final downloaded =
          await DatabaseHelper.instance.applyRemoteSyncRecords(globalRecords);

      await DatabaseHelper.instance.replaceSyncDeviceStateFromGlobal(
        globalRecords,
      );
      final finalFiles = await _listSyncFiles(session.api);
      await _uploadDeviceState(
        session.api,
        fileName: ownFileName,
        deviceId: deviceId,
        // Publish the settled global state. Reprocessing the still-pending local
        // change log here could replace a remote winner's version metadata with
        // an older local timestamp even though the row content was already
        // updated from the cloud.
        records: globalRecords,
        existingFile:
            finalFiles.where((file) => file.name == ownFileName).firstOrNull,
      );

      await DatabaseHelper.instance.markSyncChangesUploaded(pendingIds);
      final syncedAt = DateTime.now();
      final settledFiles = await _listSyncFiles(session.api);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastSyncAtKey,
        syncedAt.toUtc().toIso8601String(),
      );
      await prefs.setString(
        _remoteSignatureKey,
        _remoteSignature(settledFiles),
      );
      await prefs.remove(_lastSyncErrorKey);

      return SyncResult(
        downloadedChanges: downloaded,
        uploadedChanges: pendingIds.length,
        syncedAt: syncedAt,
      );
    } catch (error) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncErrorKey, error.toString());
      rethrow;
    } finally {
      session?.close();
      _running = false;
    }
  }

  List<Map<String, dynamic>> _recordList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<drive.File>> _listSyncFiles(drive.DriveApi api) async {
    final response = await api.files.list(
      spaces: 'appDataFolder',
      q: "name contains '$_filePrefix' and trashed = false",
      orderBy: 'modifiedTime desc',
      $fields: 'files(id,name,modifiedTime,size,appProperties)',
      pageSize: 1000,
    );
    return (response.files ?? const <drive.File>[])
        .where((file) => file.id != null && file.name != null)
        .toList();
  }

  String _remoteSignature(List<drive.File> files) {
    final parts = files
        .where((file) => file.id != null)
        .map(
          (file) => '${file.id}:${file.modifiedTime?.toUtc().toIso8601String() ?? ''}',
        )
        .toList()
      ..sort();
    return parts.join('|');
  }

  Future<void> _uploadDeviceState(
    drive.DriveApi api, {
    required String fileName,
    required String deviceId,
    required List<Map<String, dynamic>> records,
    drive.File? existingFile,
  }) async {
    final now = DateTime.now().toUtc();
    final payload = utf8.encode(jsonEncode(<String, dynamic>{
      'formatVersion': 1,
      'deviceId': deviceId,
      'updatedAt': now.toIso8601String(),
      'records': records,
    }));
    final media = drive.Media(Stream<List<int>>.value(payload), payload.length);
    final metadata = drive.File()
      ..name = fileName
      ..mimeType = 'application/json'
      ..appProperties = <String, String>{
        'kind': 'sync-state',
        'formatVersion': '1',
        'deviceId': deviceId,
        'updatedAt': now.toIso8601String(),
      };

    if (existingFile?.id != null) {
      await api.files.update(
        metadata,
        existingFile!.id!,
        uploadMedia: media,
        $fields: 'id,name,modifiedTime,appProperties',
      );
    } else {
      metadata.parents = const <String>['appDataFolder'];
      await api.files.create(
        metadata,
        uploadMedia: media,
        $fields: 'id,name,modifiedTime,appProperties',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _downloadRecords(
    drive.DriveApi api,
    String fileId,
  ) async {
    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (response is! drive.Media) return const [];
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return const [];
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return const [];
    return _recordList(decoded['records']);
  }

  List<Map<String, dynamic>> _mergeLatest(
    List<Map<String, dynamic>> records,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final record in records) {
      final table = record['table']?.toString();
      final key = record['key']?.toString();
      final changedAt = DateTime.tryParse(record['changedAt']?.toString() ?? '');
      final deviceId = record['deviceId']?.toString();
      if (table == null ||
          key == null ||
          changedAt == null ||
          deviceId == null) {
        continue;
      }
      final composite = '$table|$key';
      final existing = merged[composite];
      if (existing == null || _isNewer(record, existing)) {
        merged[composite] = Map<String, dynamic>.from(record);
      }
    }
    final values = merged.values.toList()
      ..sort((a, b) {
        final table = a['table'].toString().compareTo(b['table'].toString());
        return table != 0
            ? table
            : a['key'].toString().compareTo(b['key'].toString());
      });
    return values;
  }

  bool _isNewer(
    Map<String, dynamic> candidate,
    Map<String, dynamic> existing,
  ) {
    final candidateTime = DateTime.parse(candidate['changedAt'].toString());
    final existingTime = DateTime.parse(existing['changedAt'].toString());
    if (candidateTime.isAfter(existingTime)) return true;
    if (candidateTime.isBefore(existingTime)) return false;
    return candidate['deviceId'].toString().compareTo(
              existing['deviceId'].toString(),
            ) >
        0;
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
