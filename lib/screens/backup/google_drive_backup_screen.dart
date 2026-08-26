import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../database/database_helper.dart';
import '../../providers/bird_provider.dart';
import '../../services/google_drive_backup_service.dart';
import '../../services/google_drive_sync_service.dart';
import '../../ui/aviary_design.dart';
import '../home/home_screen.dart';

class GoogleDriveBackupScreen extends StatefulWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  State<GoogleDriveBackupScreen> createState() =>
      _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState extends State<GoogleDriveBackupScreen> {
  final _backupService = GoogleDriveBackupService.instance;
  final _syncService = GoogleDriveSyncService.instance;
  final _dateFormat = DateFormat('dd MMM yyyy, h:mm a');

  bool _busy = true;
  bool _syncEnabled = false;
  String? _email;
  DateTime? _lastBackupAt;
  DateTime? _lastSyncAt;
  AutoBackupSchedule _schedule = const AutoBackupSchedule(
    frequency: 'daily',
    hour: 14,
    minute: 0,
    weekday: DateTime.monday,
    monthDay: 1,
  );
  List<DriveBackupRecord> _backups = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool interactive = false}) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }

    try {
      _schedule = await _backupService.getSchedule();
      _lastBackupAt = await _backupService.lastManualBackupAt;
      _lastSyncAt = await _syncService.lastSuccessfulSyncAt;
      _syncEnabled = await _syncService.enabled;
      // Opening this screen must also stay silent. Google UI is shown only
      // after the user explicitly presses Connect.
      _email = _backupService.currentEmail;
      _backups = _email == null
          ? const <DriveBackupRecord>[]
          : await _backupService.listBackups(interactive: interactive);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _email = await _backupService.connect();
      await _performSync(interactive: true);
      await _syncService.setEnabled(true);
      _syncEnabled = true;
      await _load(interactive: true);
    } catch (error) {
      await _syncService.setEnabled(false);
      if (!mounted) return;
      setState(() {
        _syncEnabled = false;
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _syncNow() async {
    if (_email == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _performSync(interactive: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync completed · ${result.uploadedChanges} uploaded · '
            '${result.downloadedChanges} applied',
          ),
        ),
      );
      await context.read<BirdProvider>().loadBirds();
      await _load(interactive: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<SyncResult> _performSync({required bool interactive}) async {
    try {
      return await _syncService.syncNow(interactive: interactive);
    } on SyncNeedsMergeChoiceException {
      if (!mounted) rethrow;
      final allowMerge = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Local and cloud data found'),
          content: const Text(
            'This device already contains aviary records and Google Drive also '
            'contains synchronized records. Merge both sets using permanent '
            'record IDs? No local database will be silently replaced.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Merge Safely'),
            ),
          ],
        ),
      );
      if (allowMerge != true) {
        throw const SyncException('Sync canceled.');
      }
      return _syncService.syncNow(
        interactive: interactive,
        allowInitialMerge: true,
      );
    }
  }

  Future<void> _backupNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _backupService.backupNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual backup completed.')),
      );
      await _load(interactive: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _restore(DriveBackupRecord backup) async {
    final currentCount = await DatabaseHelper.instance.getCurrentBirdCount();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text(
            'Backup: ${_dateFormat.format(backup.createdAt)}\n'
            'Current birds: $currentCount\n\n'
            'Your current local database will be replaced. Aviary Pro will '
            'first upload a safety backup and will not continue if that '
            'safety backup fails. Cloud sync will be paused after restore so '
            'the restored copy cannot be overwritten automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _backupService.restoreBackup(backup);
      await _syncService.setEnabled(false);
      if (!mounted) return;
      await context.read<BirdProvider>().loadBirds();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup restored. Cloud sync is paused. When you enable it again, Aviary Pro will ask before merging restored and cloud data.',
          ),
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _disconnect() async {
    await _syncService.setEnabled(false);
    await _backupService.signOut();
    if (!mounted) return;
    setState(() {
      _email = null;
      _syncEnabled = false;
      _backups = const [];
      _error = null;
    });
  }

  Future<void> _setSyncEnabled(bool value) async {
    if (!value) {
      await _syncService.setEnabled(false);
      if (!mounted) return;
      setState(() => _syncEnabled = false);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _performSync(interactive: true);
      await _syncService.setEnabled(true);
      if (!mounted) return;
      setState(() {
        _syncEnabled = true;
        _lastSyncAt = result.syncedAt;
        _busy = false;
      });
      await context.read<BirdProvider>().loadBirds();
    } catch (error) {
      await _syncService.setEnabled(false);
      if (!mounted) return;
      setState(() {
        _syncEnabled = false;
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _editSchedule() async {
    var frequency = _schedule.frequency;
    var time = TimeOfDay(hour: _schedule.hour, minute: _schedule.minute);
    var weekday = _schedule.weekday;
    var monthDay = _schedule.monthDay;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogBodyContext, setDialogState) => AlertDialog(
          title: const Text('Automatic Backup Schedule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: frequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: const [
                    DropdownMenuItem(value: 'off', child: Text('Off')),
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => frequency = value);
                    }
                  },
                ),
                if (frequency != 'off') ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Time'),
                    subtitle: Text(time.format(dialogBodyContext)),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: dialogBodyContext,
                        initialTime: time,
                      );
                      if (picked != null && dialogBodyContext.mounted) {
                        setDialogState(() => time = picked);
                      }
                    },
                  ),
                ],
                if (frequency == 'weekly') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: weekday,
                    decoration: const InputDecoration(labelText: 'Day'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Monday')),
                      DropdownMenuItem(value: 2, child: Text('Tuesday')),
                      DropdownMenuItem(value: 3, child: Text('Wednesday')),
                      DropdownMenuItem(value: 4, child: Text('Thursday')),
                      DropdownMenuItem(value: 5, child: Text('Friday')),
                      DropdownMenuItem(value: 6, child: Text('Saturday')),
                      DropdownMenuItem(value: 7, child: Text('Sunday')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => weekday = value);
                      }
                    },
                  ),
                ],
                if (frequency == 'monthly') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: monthDay,
                    decoration: const InputDecoration(labelText: 'Date'),
                    items: List.generate(
                      28,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('Day ${index + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => monthDay = value);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final schedule = AutoBackupSchedule(
      frequency: frequency,
      hour: time.hour,
      minute: time.minute,
      weekday: weekday,
      monthDay: monthDay,
    );
    await _backupService.setSchedule(schedule);
    setState(() => _schedule = schedule);
  }

  String _kindLabel(String kind) {
    return switch (kind) {
      'daily' || 'auto_daily' => 'Daily automatic',
      'auto_weekly' => 'Weekly automatic',
      'auto_monthly' => 'Monthly automatic',
      'safety' => 'Safety',
      _ => 'Manual',
    };
  }

  String _scheduleLabel() {
    final time = TimeOfDay(hour: _schedule.hour, minute: _schedule.minute)
        .format(context);
    return switch (_schedule.frequency) {
      'off' => 'Automatic backups are off',
      'weekly' =>
        'Weekly on ${DateFormat.EEEE().format(DateTime(2024, 1, _schedule.weekday))} at $time',
      'monthly' => 'Monthly on day ${_schedule.monthDay} at $time',
      _ => 'Daily at $time',
    };
  }

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Sync')),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => _load(interactive: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
              children: [
                Card(
                  color: aviaryCardSurface(
                    context,
                    tint: AviaryColors.history.withValues(alpha: .09),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.cloud_done_outlined,
                                color: AviaryColors.history,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _email ?? 'Google Drive is not connected',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _lastSyncAt == null
                                        ? 'No successful sync yet'
                                        : 'Last sync: ${_dateFormat.format(_lastSyncAt!)}',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_email == null)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _connect,
                              icon: const Icon(Icons.login),
                              label: const Text('Connect Google Drive'),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _syncNow,
                                  icon: const Icon(Icons.sync),
                                  label: const Text('Sync Now'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _busy ? null : _disconnect,
                                child: const Text('Disconnect'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (_email != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: SwitchListTile(
                      value: _syncEnabled,
                      title: const Text(
                        'Change-based cloud sync',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Synchronizes user-created changes. Counts, alerts, age '
                        'calculations and display numbering are recalculated locally.',
                      ),
                      onChanged: _busy ? null : _setSyncEnabled,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_repeat_outlined),
                    title: const Text(
                      'Automatic backup',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_scheduleLabel()}\n'
                      'Keeps the latest 3 successful automatic backups.',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: _busy ? null : _editSchedule,
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text(
                      'Manual backup',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _lastBackupAt == null
                          ? 'Keeps the latest 3 successful manual or safety backups.'
                          : 'Last backup: ${_dateFormat.format(_lastBackupAt!)}\n'
                              'Keeps the latest 3 successful manual or safety backups.',
                    ),
                    trailing: FilledButton(
                      onPressed: _email == null || _busy ? null : _backupNow,
                      child: const Text('Backup Now'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Backup and sync are separate. Sync keeps devices current, '
                    'while backup snapshots let you recover from accidental edits '
                    'or deletions that sync would copy to every device.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: aviaryCardSurface(
                      context,
                      tint: Colors.red.withValues(alpha: .08),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Available backups',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    if (_email != null)
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _busy
                            ? null
                            : () => _load(interactive: true),
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
                if (_email == null)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.cloud_off_outlined),
                      title: Text('Connect Google Drive to view backups'),
                    ),
                  )
                else if (!_busy && _backups.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.cloud_queue),
                      title: Text('No backups found'),
                      subtitle: Text('Use Backup Now to create the first one.'),
                    ),
                  )
                else
                  ..._backups.map(
                    (backup) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AviaryColors.history.withValues(
                              alpha: .12,
                            ),
                            child: const Icon(
                              Icons.cloud_done_outlined,
                              color: AviaryColors.history,
                            ),
                          ),
                          title: Text(
                            '${_kindLabel(backup.kind)} backup',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${_dateFormat.format(backup.createdAt)}'
                            '${_sizeLabel(backup.sizeBytes).isEmpty ? '' : ' · ${_sizeLabel(backup.sizeBytes)}'}'
                            '${backup.schemaVersion == 0 ? '' : ' · DB v${backup.schemaVersion}'}',
                          ),
                          trailing: TextButton(
                            onPressed: _busy ? null : () => _restore(backup),
                            child: const Text('Restore'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
