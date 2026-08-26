import 'dart:async';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/google_oauth_config.dart';
import '../database/database_helper.dart';

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DriveBackupRecord {
  const DriveBackupRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.kind,
    required this.sizeBytes,
    required this.schemaVersion,
    this.databaseModifiedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final String kind;
  final int sizeBytes;
  final int schemaVersion;
  final DateTime? databaseModifiedAt;

  bool get isAutomatic => kind == 'daily' || kind.startsWith('auto_');
}

class AutoBackupSchedule {
  const AutoBackupSchedule({
    required this.frequency,
    required this.hour,
    required this.minute,
    required this.weekday,
    required this.monthDay,
  });

  final String frequency;
  final int hour;
  final int minute;
  final int weekday;
  final int monthDay;

  bool get enabled => frequency != 'off';

  String get backupKind => switch (frequency) {
        'weekly' => 'auto_weekly',
        'monthly' => 'auto_monthly',
        _ => 'auto_daily',
      };

  DateTime? scheduledOccurrenceFor(DateTime now) {
    final local = now.toLocal();
    if (frequency == 'off') return null;
    if (frequency == 'daily') {
      final candidate = DateTime(
        local.year,
        local.month,
        local.day,
        hour,
        minute,
      );
      return local.isBefore(candidate) ? null : candidate;
    }
    if (frequency == 'weekly') {
      final startOfWeek = DateTime(
        local.year,
        local.month,
        local.day - (local.weekday - DateTime.monday),
      );
      final candidate = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day + (weekday.clamp(1, 7).toInt() - 1),
        hour,
        minute,
      );
      return local.isBefore(candidate) ? null : candidate;
    }
    if (frequency == 'monthly') {
      final day = monthDay.clamp(1, 28).toInt();
      final candidate = DateTime(
        local.year,
        local.month,
        day,
        hour,
        minute,
      );
      return local.isBefore(candidate) ? null : candidate;
    }
    return null;
  }
}

class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static final GoogleDriveBackupService instance =
      GoogleDriveBackupService._();

  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static const String _filePrefix = 'aviarypro_backup_';
  static const String _frequencyKey = 'drive_backup_frequency';
  static const String _hourKey = 'drive_backup_hour';
  static const String _minuteKey = 'drive_backup_minute';
  static const String _weekdayKey = 'drive_backup_weekday';
  static const String _monthDayKey = 'drive_backup_month_day';
  static const String _legacyAutoEnabledKey = 'drive_backup_auto_enabled';
  static const String _lastBackupAtKey = 'drive_backup_last_success_at';
  static const String _lastAutoBackupAtKey = 'drive_backup_last_auto_success_at';
  static const String _lastManualBackupAtKey =
      'drive_backup_last_manual_success_at';
  static const String _lastBackupEmailKey = 'drive_backup_account_email';
  static const String _pauseAfterRestoreChangeKey =
      'drive_backup_pause_after_restore_change';

  final GoogleSignIn _signIn = GoogleSignIn.instance;

  bool _initialized = false;
  GoogleSignInAccount? _account;

  String? get currentEmail => _account?.email;

  Future<void> _initialize() async {
    if (_initialized) return;

    final clientId = GoogleOAuthConfig.serverClientId.trim();
    if (clientId.isEmpty) {
      throw const BackupException(
        'Google Drive is not configured yet. Add the Web OAuth client ID in '
        'lib/config/google_oauth_config.dart.',
      );
    }
    await _signIn.initialize(serverClientId: clientId);
    _initialized = true;
  }

  Future<GoogleSignInAccount?> restorePreviousSession() async {
    await _initialize();
    if (_account != null) return _account;

    try {
      final future = _signIn.attemptLightweightAuthentication();
      _account = future == null ? null : await future;
      return _account;
    } on GoogleSignInException {
      return null;
    }
  }

  Future<String> connect() async {
    await _initialize();

    if (!_signIn.supportsAuthenticate()) {
      throw const BackupException(
        'Google sign-in is not supported on this device.',
      );
    }

    try {
      _account = await _signIn.authenticate(scopeHint: scopes);
      await _authorization(interactive: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBackupEmailKey, _account!.email);
      return _account!.email;
    } on GoogleSignInException catch (error) {
      throw BackupException(_friendlySignInError(error));
    }
  }

  Future<void> signOut() async {
    await _initialize();
    await _signIn.signOut();
    _account = null;
  }

  Future<GoogleSignInClientAuthorization> _authorization({
    required bool interactive,
  }) async {
    // Background work must never trigger Google One Tap / sign-in UI.
    // A session is restored only from an explicitly interactive Drive action.
    final account = _account ??
        (interactive ? await restorePreviousSession() : null);
    if (account == null) {
      throw const BackupException('Connect a Google account first.');
    }

    var authorization = await account.authorizationClient
        .authorizationForScopes(scopes);

    if (authorization == null && interactive) {
      authorization = await account.authorizationClient.authorizeScopes(
        scopes,
      );
    }

    if (authorization == null) {
      throw const BackupException(
        'Google Drive permission is required. Open Backup & Sync and connect again.',
      );
    }

    return authorization;
  }

  Future<DriveSession> openDrive({required bool interactive}) async {
    final authorization = await _authorization(interactive: interactive);
    final client = BearerClient(authorization.accessToken);
    return DriveSession(client, drive.DriveApi(client));
  }

  Future<AutoBackupSchedule> getSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    var frequency = prefs.getString(_frequencyKey);
    if (frequency == null) {
      final legacyEnabled = prefs.getBool(_legacyAutoEnabledKey) ?? true;
      frequency = legacyEnabled ? 'daily' : 'off';
      await prefs.setString(_frequencyKey, frequency);
    }
    return AutoBackupSchedule(
      frequency: frequency,
      hour: prefs.getInt(_hourKey) ?? 14,
      minute: prefs.getInt(_minuteKey) ?? 0,
      weekday: prefs.getInt(_weekdayKey) ?? DateTime.monday,
      monthDay: prefs.getInt(_monthDayKey) ?? 1,
    );
  }

  Future<void> setSchedule(AutoBackupSchedule schedule) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_frequencyKey, schedule.frequency);
    await prefs.setInt(_hourKey, schedule.hour.clamp(0, 23).toInt());
    await prefs.setInt(_minuteKey, schedule.minute.clamp(0, 59).toInt());
    await prefs.setInt(_weekdayKey, schedule.weekday.clamp(1, 7).toInt());
    await prefs.setInt(_monthDayKey, schedule.monthDay.clamp(1, 28).toInt());
    await prefs.setBool(_legacyAutoEnabledKey, schedule.enabled);
  }

  Future<DateTime?> get lastSuccessfulBackupAt async {
    return _readDate(_lastBackupAtKey);
  }

  Future<DateTime?> get lastAutomaticBackupAt async {
    return _readDate(_lastAutoBackupAtKey);
  }

  Future<DateTime?> get lastManualBackupAt async {
    return _readDate(_lastManualBackupAtKey);
  }

  Future<DateTime?> _readDate(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    return value == null ? null : DateTime.tryParse(value)?.toLocal();
  }

  Future<String?> get lastConnectedEmail async {
    if (_account != null) return _account!.email;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastBackupEmailKey);
  }

  Future<List<DriveBackupRecord>> listBackups({
    bool interactive = false,
  }) async {
    final session = await openDrive(interactive: interactive);
    try {
      final response = await session.api.files.list(
        spaces: 'appDataFolder',
        q: "name contains '$_filePrefix' and trashed = false",
        orderBy: 'createdTime desc',
        $fields:
            'files(id,name,createdTime,modifiedTime,size,appProperties),nextPageToken',
        pageSize: 1000,
      );

      final records = (response.files ?? const <drive.File>[])
          .where((file) => file.id != null && file.name != null)
          .map(_recordFromDriveFile)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    } finally {
      session.close();
    }
  }

  Future<DriveBackupRecord> backupNow({
    String kind = 'manual',
    bool interactive = true,
    bool pruneAfter = true,
  }) async {
    if (!await DatabaseHelper.instance.hasUserData()) {
      throw const BackupException(
        'No aviary data is available to back up. Empty automatic backups are blocked.',
      );
    }

    final snapshotPath = await DatabaseHelper.instance.createBackupSnapshot();
    final snapshot = File(snapshotPath);
    final session = await openDrive(interactive: interactive);

    try {
      final now = DateTime.now().toUtc();
      final databaseModifiedAt =
          await DatabaseHelper.instance.getDatabaseModifiedAt();
      final schemaVersion = await DatabaseHelper.instance.getSchemaVersion();
      final safeStamp = now.toIso8601String().replaceAll(':', '-');
      final name = '$_filePrefix${kind}_$safeStamp.db';

      final metadata = drive.File()
        ..name = name
        ..parents = const <String>['appDataFolder']
        ..mimeType = 'application/x-aviarypro-backup'
        ..appProperties = <String, String>{
          'formatVersion': '2',
          'kind': kind,
          'createdAt': now.toIso8601String(),
          'databaseModifiedAt':
              databaseModifiedAt?.toUtc().toIso8601String() ?? '',
          'schemaVersion': '$schemaVersion',
          'packageName': 'com.huraiz.avairypro',
        };

      final uploaded = await session.api.files.create(
        metadata,
        uploadMedia: drive.Media(snapshot.openRead(), await snapshot.length()),
        $fields: 'id,name,createdTime,size,appProperties',
      );

      if (uploaded.id == null || uploaded.name == null) {
        throw const BackupException('Google Drive did not return a backup ID.');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBackupAtKey, now.toIso8601String());
      if (kind.startsWith('auto_')) {
        await prefs.setString(_lastAutoBackupAtKey, now.toIso8601String());
      } else {
        await prefs.setString(_lastManualBackupAtKey, now.toIso8601String());
      }
      if (_account != null) {
        await prefs.setString(_lastBackupEmailKey, _account!.email);
      }

      final record = _recordFromDriveFile(uploaded);
      if (pruneAfter) {
        try {
          await _pruneRetention(protectedIds: <String>{record.id});
        } catch (_) {
          // The new file is already safe. Cleanup can be retried later.
        }
      }
      return record;
    } finally {
      session.close();
      if (await snapshot.exists()) {
        await snapshot.delete();
      }
    }
  }

  Future<void> runAutomaticBackupIfDue() async {
    try {
      final schedule = await getSchedule();
      if (!schedule.enabled) return;
      final occurrence = schedule.scheduledOccurrenceFor(DateTime.now());
      if (occurrence == null) return;

      // Automatic backup is allowed only when this app process already has
      // an authenticated account. Never restore/sign in from the background.
      if (_account == null) return;
      if (!await DatabaseHelper.instance.hasUserData()) return;

      final lastAuto = await lastAutomaticBackupAt;
      if (lastAuto != null && !lastAuto.isBefore(occurrence)) return;

      final latestUserChange =
          await DatabaseHelper.instance.getLatestUserChangeAt();
      if (latestUserChange == null) return;
      if (lastAuto != null && !latestUserChange.isAfter(lastAuto)) return;

      final prefs = await SharedPreferences.getInstance();
      final pauseValue = prefs.getString(_pauseAfterRestoreChangeKey);
      final pausedAt = pauseValue == null ? null : DateTime.tryParse(pauseValue);
      if (pausedAt != null && !latestUserChange.toUtc().isAfter(pausedAt)) {
        return;
      }

      await backupNow(kind: schedule.backupKind, interactive: false);
      await prefs.remove(_pauseAfterRestoreChangeKey);
    } catch (_) {
      // Scheduled backup stays quiet and never opens sign-in UI.
    }
  }

  Future<void> _pruneRetention({
    Set<String> protectedIds = const <String>{},
  }) async {
    final backups = await listBackups();
    final automatic = backups.where((backup) => backup.isAutomatic).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final manual = backups.where((backup) => !backup.isAutomatic).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final keepIds = <String>{
      ...automatic.take(3).map((backup) => backup.id),
      ...manual.take(3).map((backup) => backup.id),
      ...protectedIds,
    };
    final toDelete = backups
        .where((backup) => !keepIds.contains(backup.id))
        .toList();
    if (toDelete.isEmpty) return;

    final session = await openDrive(interactive: false);
    try {
      for (final backup in toDelete) {
        await session.api.files.delete(backup.id);
      }
    } finally {
      session.close();
    }
  }

  Future<void> restoreBackup(
    DriveBackupRecord backup, {
    bool createSafetyBackup = true,
  }) async {
    if (createSafetyBackup && await DatabaseHelper.instance.hasUserData()) {
      await backupNow(
        kind: 'safety',
        interactive: true,
        pruneAfter: false,
      );
    }

    final session = await openDrive(interactive: true);
    final targetPath = await DatabaseHelper.instance.createTemporaryBackupPath(
      prefix: 'restore',
    );
    final target = File(targetPath);

    try {
      final media = await session.api.files.get(
        backup.id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (media is! drive.Media) {
        throw const BackupException('Google Drive returned an invalid backup.');
      }

      final sink = target.openWrite();
      await media.stream.pipe(sink);
      await DatabaseHelper.instance.restoreDatabaseFromSnapshot(target.path);
      await DatabaseHelper.instance.resetSyncStateAfterRestore();

      final latestChange =
          await DatabaseHelper.instance.getLatestUserChangeAt();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pauseAfterRestoreChangeKey,
        (latestChange ?? DateTime.now()).toUtc().toIso8601String(),
      );
      try {
        await _pruneRetention();
      } catch (_) {
        // Restore is complete even when cleanup is temporarily unavailable.
      }
    } finally {
      session.close();
      if (await target.exists()) {
        await target.delete();
      }
    }
  }

  DriveBackupRecord _recordFromDriveFile(drive.File file) {
    final properties = file.appProperties ?? const <String, String>{};
    final createdAt = DateTime.tryParse(properties['createdAt'] ?? '') ??
        file.createdTime ??
        DateTime.now().toUtc();

    return DriveBackupRecord(
      id: file.id!,
      name: file.name!,
      createdAt: createdAt.toLocal(),
      kind: properties['kind'] ?? 'manual',
      sizeBytes: int.tryParse(file.size ?? '') ?? 0,
      schemaVersion: int.tryParse(properties['schemaVersion'] ?? '') ?? 0,
      databaseModifiedAt:
          DateTime.tryParse(properties['databaseModifiedAt'] ?? '')?.toLocal(),
    );
  }

  String _friendlySignInError(GoogleSignInException error) {
    if (error.code == GoogleSignInExceptionCode.canceled) {
      return 'Google sign-in was canceled. If you selected an account, check the OAuth package name, SHA-1, and Web client ID.';
    }
    if (error.code == GoogleSignInExceptionCode.clientConfigurationError) {
      return 'Google sign-in is not configured correctly. Check the Android OAuth client, SHA-1, package name, and Web client ID.';
    }
    return error.description ?? 'Google sign-in failed (${error.code.name}).';
  }
}

class DriveSession {
  const DriveSession(this.client, this.api);

  final BearerClient client;
  final drive.DriveApi api;

  void close() => client.close();
}

class BearerClient extends http.BaseClient {
  BearerClient(this.accessToken);

  final String accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
