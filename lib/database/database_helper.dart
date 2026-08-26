import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('aviarypro.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return openDatabase(
      path,
      version: 15,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await _createSpeciesTable(db);

    await db.execute('''
      CREATE TABLE cages(
        id TEXT PRIMARY KEY,
        identifier TEXT NOT NULL,
        type TEXT NOT NULL,
        location TEXT,
        notes TEXT,
        identityMode TEXT NOT NULL DEFAULT 'named',
        physicalCageId TEXT,
        physicalName TEXT,
        portionIndex INTEGER NOT NULL DEFAULT 1,
        seriesOrder INTEGER,
        active INTEGER NOT NULL DEFAULT 1,
        mergedIntoId TEXT,
        soldAt TEXT,
        soldPrice REAL,
        soldBuyer TEXT,
        soldNotes TEXT,
        createdAt TEXT,
        updatedAt TEXT,
        FOREIGN KEY (mergedIntoId) REFERENCES cages(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE birds(
        id TEXT PRIMARY KEY,
        ringNumber TEXT NOT NULL,
        name TEXT,
        gender TEXT,
        mutation TEXT,
        hatchDate TEXT,
        speciesId TEXT,
        ageGroup TEXT,
        estimatedAgeDays INTEGER,
        source TEXT,
        sourceDate TEXT,
        sourcePerson TEXT,
        sourcePlace TEXT,
        sourceDetails TEXT,
        parentPairId TEXT,
        purchasePrice REAL,
        notes TEXT,
        active INTEGER,
        cageId TEXT,
        nestClutchId TEXT,
        leftNestDate TEXT,
        saleStatus TEXT NOT NULL DEFAULT 'Not for Sale',
        reservedBuyer TEXT,
        reservedPrice REAL,
        reservedAt TEXT,
        soldBuyer TEXT,
        soldPrice REAL,
        soldAt TEXT,
        soldNotes TEXT,
        fosteredAt TEXT,
        fosterNotes TEXT,
        removedAt TEXT,
        removalReason TEXT,
        createdAt TEXT,
        originClutchId TEXT,
        FOREIGN KEY (speciesId) REFERENCES species(id),
        FOREIGN KEY (cageId) REFERENCES cages(id),
        FOREIGN KEY (parentPairId) REFERENCES pairs(id),
        FOREIGN KEY (nestClutchId) REFERENCES clutches(id)
      )
    ''');

    await _createPairsTable(db);
    await _createBreedingTables(db);
    await _createCageStructureTables(db);
    await _createManagementTables(db);
    await _createWorkflowTables(db);
    await _createUniqueIndexes(db);
    await _seedDefaultSpecies(db);
    await _createSyncInfrastructure(db);
  }

  Future<void> _createSpeciesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS species(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        chickToYoungDays INTEGER,
        adultAgeMonths INTEGER,
        incubationDays INTEGER,
        clutchWindowDays INTEGER NOT NULL DEFAULT 15,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<void> _seedDefaultSpecies(Database db) async {
    await db.insert(
      'species',
      {
        'id': 'cockatiel',
        'name': 'Cockatiel',
        'chickToYoungDays': null,
        'adultAgeMonths': 8,
        'incubationDays': 18,
        'clutchWindowDays': 15,
        'active': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.insert(
      'species',
      {
        'id': 'ringneck',
        'name': 'Ringneck',
        'chickToYoungDays': null,
        'adultAgeMonths': null,
        'incubationDays': 22,
        'clutchWindowDays': 15,
        'active': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _createPairsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pairs(
        id TEXT PRIMARY KEY,
        identifier TEXT COLLATE NOCASE UNIQUE,
        maleBirdId TEXT NOT NULL,
        femaleBirdId TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        endedAt TEXT,
        endReason TEXT,
        notes TEXT,
        breedingStatus TEXT NOT NULL DEFAULT 'Inactive',
        FOREIGN KEY (maleBirdId) REFERENCES birds(id),
        FOREIGN KEY (femaleBirdId) REFERENCES birds(id),
        CHECK (maleBirdId != femaleBirdId)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pairs_male
      ON pairs(maleBirdId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pairs_female
      ON pairs(femaleBirdId)
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_pairs_identifier_unique
      ON pairs(identifier COLLATE NOCASE)
      WHERE identifier IS NOT NULL
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pair_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        syncId TEXT UNIQUE,
        pairId TEXT NOT NULL,
        startedAt TEXT NOT NULL,
        endedAt TEXT,
        endReason TEXT,
        cageId TEXT,
        FOREIGN KEY (pairId) REFERENCES pairs(id),
        FOREIGN KEY (cageId) REFERENCES cages(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pair_sessions_pair
      ON pair_sessions(pairId, startedAt DESC)
    ''');
  }

  Future<void> _createCageStructureTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cage_merge_links(
        cageAId TEXT NOT NULL,
        cageBId TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        PRIMARY KEY (cageAId, cageBId),
        FOREIGN KEY (cageAId) REFERENCES cages(id),
        FOREIGN KEY (cageBId) REFERENCES cages(id),
        CHECK (cageAId < cageBId)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cage_merge_links_a
      ON cage_merge_links(cageAId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cage_merge_links_b
      ON cage_merge_links(cageBId)
    ''');
  }

  Future<void> _createBreedingTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clutches(
        id TEXT PRIMARY KEY,
        pairId TEXT NOT NULL,
        clutchNumber INTEGER NOT NULL DEFAULT 1,
        startedAt TEXT NOT NULL,
        firstEggDate TEXT,
        endedAt TEXT,
        status TEXT NOT NULL DEFAULT 'Active',
        expectedEggs INTEGER,
        incubationDaysOverride INTEGER,
        notes TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (pairId) REFERENCES pairs(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS eggs(
        id TEXT PRIMARY KEY,
        clutchId TEXT NOT NULL,
        currentClutchId TEXT,
        eggNumber INTEGER NOT NULL,
        laidDate TEXT NOT NULL,
        expectedHatchDate TEXT,
        status TEXT NOT NULL DEFAULT 'Incubating',
        hatchedBirdId TEXT,
        notes TEXT,
        updatedAt TEXT,
        fosteredAt TEXT,
        fosterNotes TEXT,
        FOREIGN KEY (clutchId) REFERENCES clutches(id),
        FOREIGN KEY (currentClutchId) REFERENCES clutches(id),
        FOREIGN KEY (hatchedBirdId) REFERENCES birds(id),
        UNIQUE(clutchId, eggNumber)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_clutches_pair
      ON clutches(pairId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_clutches_status
      ON clutches(status)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_eggs_clutch
      ON eggs(clutchId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_eggs_current_clutch
      ON eggs(currentClutchId)
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_clutch_number_unique
      ON clutches(pairId, clutchNumber)
    ''');

    await _createSupportTables(db);
  }

  Future<void> _createSupportTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS finance_transactions(
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        birdId TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (birdId) REFERENCES birds(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bird_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        syncId TEXT UNIQUE,
        birdId TEXT NOT NULL,
        eventType TEXT NOT NULL,
        eventDate TEXT NOT NULL,
        details TEXT,
        FOREIGN KEY (birdId) REFERENCES birds(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_finance_date
      ON finance_transactions(date)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bird_events_bird
      ON bird_events(birdId, eventDate)
    ''');

    await _createActivityTables(db);
  }

  Future<void> _createManagementTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ring_ranges(
        id TEXT PRIMARY KEY,
        speciesId TEXT NOT NULL,
        startNumber INTEGER NOT NULL,
        endNumber INTEGER NOT NULL,
        padding INTEGER NOT NULL DEFAULT 3,
        active INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (speciesId) REFERENCES species(id),
        CHECK (startNumber >= 0),
        CHECK (endNumber >= startNumber)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ring_ranges_species
      ON ring_ranges(speciesId, startNumber, endNumber)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS managed_bird_values(
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        speciesId TEXT,
        value TEXT NOT NULL COLLATE NOCASE,
        active INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (speciesId) REFERENCES species(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_managed_bird_values_kind
      ON managed_bird_values(kind, speciesId, value COLLATE NOCASE)
    ''');
  }

  Future<void> _createWorkflowTables(Database db) async {
    await _addColumnIfMissing(db, 'finance_transactions', 'quantity', 'REAL');
    await _addColumnIfMissing(db, 'finance_transactions', 'unit', 'TEXT');
    await _addColumnIfMissing(db, 'birds', 'eyeColor', 'TEXT');
    await _addColumnIfMissing(db, 'birds', 'downColor', 'TEXT');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_locations(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        active INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_outings(
        id TEXT PRIMARY KEY,
        outingDate TEXT NOT NULL,
        locationId TEXT,
        status TEXT NOT NULL DEFAULT 'Open',
        notes TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (locationId) REFERENCES sale_locations(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_outing_birds(
        id TEXT PRIMARY KEY,
        outingId TEXT NOT NULL,
        birdId TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Taken',
        soldPrice REAL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (outingId) REFERENCES sale_outings(id),
        FOREIGN KEY (birdId) REFERENCES birds(id)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_sale_outing_bird_unique
      ON sale_outing_birds(outingId, birdId)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_price_guides(
        id TEXT PRIMARY KEY,
        speciesId TEXT NOT NULL,
        mutation TEXT NOT NULL DEFAULT '',
        ageGroup TEXT NOT NULL,
        price REAL NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (speciesId) REFERENCES species(id)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_sale_price_guide_unique
      ON sale_price_guides(speciesId, mutation COLLATE NOCASE, ageGroup COLLATE NOCASE)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS breeding_observations(
        id TEXT PRIMARY KEY,
        pairId TEXT NOT NULL,
        clutchId TEXT,
        observationType TEXT NOT NULL,
        observedAt TEXT NOT NULL,
        resolved INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (pairId) REFERENCES pairs(id),
        FOREIGN KEY (clutchId) REFERENCES clutches(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_breeding_observations_pair
      ON breeding_observations(pairId, observedAt DESC)
    ''');
  }

  Future<void> _createActivityTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        syncId TEXT UNIQUE,
        category TEXT NOT NULL,
        eventType TEXT NOT NULL,
        eventDate TEXT NOT NULL,
        title TEXT NOT NULL,
        details TEXT,
        entityType TEXT,
        entityId TEXT,
        birdId TEXT,
        amount REAL,
        financeType TEXT,
        sourceKey TEXT UNIQUE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_events_date
      ON activity_events(eventDate DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_events_category
      ON activity_events(category, eventDate DESC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dismissed_dashboard_alerts(
        alertKey TEXT PRIMARY KEY,
        dismissedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_queue(
        alertKey TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        scheduledFor TEXT,
        createdAt TEXT NOT NULL,
        delivered INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static const List<String> _syncTableOrder = <String>[
    'species',
    'cages',
    'cage_merge_links',
    'birds',
    'pairs',
    'pair_sessions',
    'clutches',
    'eggs',
    'finance_transactions',
    'bird_events',
    'activity_events',
    'ring_ranges',
    'managed_bird_values',
    'sale_locations',
    'sale_outings',
    'sale_outing_birds',
    'sale_price_guides',
    'breeding_observations',
  ];

  Future<void> _createSyncInfrastructure(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_runtime(
        id INTEGER PRIMARY KEY CHECK(id = 1),
        suppress INTEGER NOT NULL DEFAULT 0,
        lastUserChangeAt TEXT
      )
    ''');
    await db.insert(
      'sync_runtime',
      const <String, Object>{'id': 1, 'suppress': 0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_change_log(
        id TEXT PRIMARY KEY,
        tableName TEXT NOT NULL,
        recordKey TEXT NOT NULL,
        operation TEXT NOT NULL,
        changedAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_change_log_record
      ON sync_change_log(tableName, recordKey, changedAt)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_device_state(
        tableName TEXT NOT NULL,
        recordKey TEXT NOT NULL,
        operation TEXT NOT NULL,
        changedAt TEXT NOT NULL,
        rowJson TEXT,
        originDeviceId TEXT NOT NULL,
        PRIMARY KEY(tableName, recordKey)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_applied_versions(
        tableName TEXT NOT NULL,
        recordKey TEXT NOT NULL,
        changedAt TEXT NOT NULL,
        originDeviceId TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(tableName, recordKey)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tableName TEXT NOT NULL,
        recordKey TEXT NOT NULL,
        localChangedAt TEXT,
        remoteChangedAt TEXT,
        details TEXT,
        createdAt TEXT NOT NULL,
        resolved INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _createSyncTriggers(db);
  }

  Future<void> _createSyncTriggers(Database db) async {
    final triggerDefinitions = <Map<String, String>>[
      {'table': 'species', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'cages', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {
        'table': 'cage_merge_links',
        'newKey': "NEW.cageAId || '|' || NEW.cageBId",
        'oldKey': "OLD.cageAId || '|' || OLD.cageBId",
      },
      {'table': 'birds', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'pairs', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {
        'table': 'pair_sessions',
        'newKey': 'NEW.syncId',
        'oldKey': 'OLD.syncId',
      },
      {'table': 'clutches', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'eggs', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {
        'table': 'finance_transactions',
        'newKey': 'NEW.id',
        'oldKey': 'OLD.id',
      },
      {
        'table': 'bird_events',
        'newKey': 'NEW.syncId',
        'oldKey': 'OLD.syncId',
      },
      {
        'table': 'activity_events',
        'newKey': 'NEW.syncId',
        'oldKey': 'OLD.syncId',
      },
      {'table': 'ring_ranges', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'managed_bird_values', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'sale_locations', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'sale_outings', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'sale_outing_birds', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'sale_price_guides', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
      {'table': 'breeding_observations', 'newKey': 'NEW.id', 'oldKey': 'OLD.id'},
    ];

    for (final definition in triggerDefinitions) {
      final table = definition['table']!;
      final safeName = table.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final newKey = definition['newKey']!;
      final oldKey = definition['oldKey']!;
      for (final suffix in const ['insert', 'update', 'delete']) {
        await db.execute('DROP TRIGGER IF EXISTS sync_${safeName}_$suffix');
      }

      await db.execute('''
        CREATE TRIGGER sync_${safeName}_insert
        AFTER INSERT ON $table
        WHEN (SELECT suppress FROM sync_runtime WHERE id = 1) = 0
          AND ($newKey) IS NOT NULL
        BEGIN
          INSERT INTO sync_change_log(id, tableName, recordKey, operation, changedAt)
          VALUES(
            lower(hex(randomblob(16))),
            '$table',
            $newKey,
            'upsert',
            strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
          );
          UPDATE sync_runtime
          SET lastUserChangeAt = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
          WHERE id = 1;
        END
      ''');

      await db.execute('''
        CREATE TRIGGER sync_${safeName}_update
        AFTER UPDATE ON $table
        WHEN (SELECT suppress FROM sync_runtime WHERE id = 1) = 0
          AND ($newKey) IS NOT NULL
        BEGIN
          INSERT INTO sync_change_log(id, tableName, recordKey, operation, changedAt)
          VALUES(
            lower(hex(randomblob(16))),
            '$table',
            $newKey,
            'upsert',
            strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
          );
          UPDATE sync_runtime
          SET lastUserChangeAt = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
          WHERE id = 1;
        END
      ''');

      await db.execute('''
        CREATE TRIGGER sync_${safeName}_delete
        AFTER DELETE ON $table
        WHEN (SELECT suppress FROM sync_runtime WHERE id = 1) = 0
          AND ($oldKey) IS NOT NULL
        BEGIN
          INSERT INTO sync_change_log(id, tableName, recordKey, operation, changedAt)
          VALUES(
            lower(hex(randomblob(16))),
            '$table',
            $oldKey,
            'delete',
            strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
          );
          UPDATE sync_runtime
          SET lastUserChangeAt = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
          WHERE id = 1;
        END
      ''');
    }
  }

  Future<void> _setSyncSuppressed(
    DatabaseExecutor executor,
    bool value,
  ) async {
    await executor.update(
      'sync_runtime',
      {'suppress': value ? 1 : 0},
      where: 'id = 1',
    );
  }

  Future<DateTime?> getLatestUserChangeAt() async {
    final db = await database;
    final rows = await db.query(
      'sync_runtime',
      columns: ['lastUserChangeAt'],
      where: 'id = 1',
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.first['lastUserChangeAt']?.toString();
    return value == null ? null : DateTime.tryParse(value)?.toLocal();
  }

  Future<bool> hasSyncDeviceState() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_device_state'),
    );
    return (count ?? 0) > 0;
  }

  Future<bool> hasPendingSyncChanges() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_change_log'),
    );
    return (count ?? 0) > 0;
  }

  Future<void> resetSyncStateAfterRestore() async {
    final db = await database;
    await db.transaction((txn) async {
      await _setSyncSuppressed(txn, true);
      try {
        await txn.delete('sync_change_log');
        await txn.delete('sync_device_state');
        await txn.delete('sync_applied_versions');
        await txn.update(
          'sync_runtime',
          {'lastUserChangeAt': DateTime.now().toUtc().toIso8601String()},
          where: 'id = 1',
        );
      } finally {
        await _setSyncSuppressed(txn, false);
      }
    });
  }

  Future<void> seedAllLocalDataForSync(String deviceId) async {
    final db = await database;
    await db.transaction((txn) async {
      final existing = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT COUNT(*) FROM sync_device_state'),
      );
      if ((existing ?? 0) > 0) return;

      final changedAt = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'sync_runtime',
        {'lastUserChangeAt': changedAt},
        where: 'id = 1',
      );
      await _setSyncSuppressed(txn, true);
      try {
        for (final table in _syncTableOrder) {
          final rows = await txn.query(table);
          for (final rawRow in rows) {
            final row = _sanitizeSyncRow(table, rawRow);
            final recordKey = _syncRecordKey(table, row);
            if (recordKey == null || recordKey.isEmpty) continue;
            final rowJson = jsonEncode(row);
            await txn.insert(
              'sync_device_state',
              {
                'tableName': table,
                'recordKey': recordKey,
                'operation': 'upsert',
                'changedAt': changedAt,
                'rowJson': rowJson,
                'originDeviceId': deviceId,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            await txn.insert(
              'sync_applied_versions',
              {
                'tableName': table,
                'recordKey': recordKey,
                'changedAt': changedAt,
                'originDeviceId': deviceId,
                'deleted': 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      } finally {
        await _setSyncSuppressed(txn, false);
      }
    });
  }

  Future<Map<String, dynamic>> prepareSyncDeviceState(String deviceId) async {
    final db = await database;
    return db.transaction((txn) async {
      final pending = await txn.query(
        'sync_change_log',
        orderBy: 'changedAt ASC, rowid ASC',
      );
      final latest = <String, Map<String, dynamic>>{};
      for (final raw in pending) {
        final row = Map<String, dynamic>.from(raw);
        latest['${row['tableName']}|${row['recordKey']}'] = row;
      }

      await _setSyncSuppressed(txn, true);
      try {
        for (final change in latest.values) {
          final table = change['tableName'].toString();
          final recordKey = change['recordKey'].toString();
          final operation = change['operation'].toString();
          final changedAt = change['changedAt'].toString();
          final row = operation == 'delete'
              ? null
              : await _readSyncRow(txn, table, recordKey);
          final effectiveOperation = row == null ? 'delete' : 'upsert';
          await txn.insert(
            'sync_device_state',
            {
              'tableName': table,
              'recordKey': recordKey,
              'operation': effectiveOperation,
              'changedAt': changedAt,
              'rowJson': row == null ? null : jsonEncode(row),
              'originDeviceId': deviceId,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await txn.insert(
            'sync_applied_versions',
            {
              'tableName': table,
              'recordKey': recordKey,
              'changedAt': changedAt,
              'originDeviceId': deviceId,
              'deleted': effectiveOperation == 'delete' ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } finally {
        await _setSyncSuppressed(txn, false);
      }

      final stateRows = await txn.query(
        'sync_device_state',
        orderBy: 'tableName ASC, recordKey ASC',
      );
      return <String, dynamic>{
        'pendingIds': pending.map((row) => row['id'].toString()).toList(),
        'records': stateRows.map((row) {
          final rowJson = row['rowJson']?.toString();
          return <String, dynamic>{
            'table': row['tableName'],
            'key': row['recordKey'],
            'operation': row['operation'],
            'changedAt': row['changedAt'],
            'deviceId': row['originDeviceId'],
            'row': rowJson == null ? null : jsonDecode(rowJson),
          };
        }).toList(),
      };
    });
  }

  Future<void> replaceSyncDeviceStateFromGlobal(
    List<Map<String, dynamic>> records,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await _setSyncSuppressed(txn, true);
      try {
        await txn.delete('sync_device_state');
        for (final record in records) {
          final row = record['row'];
          await txn.insert(
            'sync_device_state',
            {
              'tableName': record['table'].toString(),
              'recordKey': record['key'].toString(),
              'operation': record['operation'].toString(),
              'changedAt': record['changedAt'].toString(),
              'rowJson': row == null ? null : jsonEncode(row),
              'originDeviceId': record['deviceId'].toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } finally {
        await _setSyncSuppressed(txn, false);
      }
    });
  }

  Future<void> markSyncChangesUploaded(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'sync_change_log',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<List<Map<String, dynamic>>> getAppliedSyncVersions() async {
    final db = await database;
    return db.query('sync_applied_versions');
  }

  Future<int> applyRemoteSyncRecords(
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return 0;
    final db = await database;
    var appliedCount = 0;

    await db.transaction((txn) async {
      await txn.execute('PRAGMA defer_foreign_keys = ON');
      await _setSyncSuppressed(txn, true);
      try {
        final appliedRows = await txn.query('sync_applied_versions');
        final versions = <String, Map<String, dynamic>>{
          for (final row in appliedRows)
            '${row['tableName']}|${row['recordKey']}': row,
        };

        bool isNewer(Map<String, dynamic> record) {
          final key = '${record['table']}|${record['key']}';
          final existing = versions[key];
          if (existing == null) return true;
          final remoteTime = DateTime.tryParse(record['changedAt'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final localTime = DateTime.tryParse(existing['changedAt'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          if (remoteTime.isAfter(localTime)) return true;
          if (remoteTime.isBefore(localTime)) return false;
          return record['deviceId'].toString().compareTo(
                    existing['originDeviceId'].toString(),
                  ) >
              0;
        }

        final applicable = records.where(isNewer).toList();
        final upserts = applicable
            .where((record) => record['operation'] != 'delete')
            .toList();
        final deletes = applicable
            .where((record) => record['operation'] == 'delete')
            .toList();

        const upsertOrder = <String>[
          'species',
          'cages',
          'cage_merge_links',
          'birds',
          'pairs',
          'pair_sessions',
          'clutches',
          'eggs',
          'finance_transactions',
          'bird_events',
          'activity_events',
          'ring_ranges',
          'managed_bird_values',
          'sale_locations',
          'sale_outings',
          'sale_outing_birds',
          'sale_price_guides',
          'breeding_observations',
        ];
        final deferredBirdRows = <Map<String, dynamic>>[];

        for (final table in upsertOrder) {
          for (final record in upserts.where((r) => r['table'] == table)) {
            final decoded = record['row'];
            if (decoded is! Map) continue;
            final row = Map<String, dynamic>.from(decoded);
            if (table == 'birds') {
              deferredBirdRows.add(Map<String, dynamic>.from(row));
              row.remove('parentPairId');
              row.remove('nestClutchId');
              row.remove('originClutchId');
            }
            await _upsertSyncRow(txn, table, row, record['key'].toString());
            appliedCount++;
          }
        }

        for (final bird in deferredBirdRows) {
          final birdId = bird['id']?.toString();
          if (birdId == null) continue;
          await txn.update(
            'birds',
            {
              'parentPairId': bird['parentPairId'],
              'nestClutchId': bird['nestClutchId'],
              'originClutchId': bird['originClutchId'],
            },
            where: 'id = ?',
            whereArgs: [birdId],
          );
        }

        const deleteOrder = <String>[
          'breeding_observations',
          'sale_outing_birds',
          'sale_outings',
          'sale_locations',
          'sale_price_guides',
          'managed_bird_values',
          'ring_ranges',
          'activity_events',
          'bird_events',
          'finance_transactions',
          'eggs',
          'clutches',
          'pair_sessions',
          'pairs',
          'birds',
          'cage_merge_links',
          'cages',
          'species',
        ];
        for (final table in deleteOrder) {
          for (final record in deletes.where((r) => r['table'] == table)) {
            await _deleteSyncRow(
              txn,
              table,
              record['key'].toString(),
            );
            appliedCount++;
          }
        }

        for (final record in applicable) {
          final row = <String, dynamic>{
            'tableName': record['table'].toString(),
            'recordKey': record['key'].toString(),
            'changedAt': record['changedAt'].toString(),
            'originDeviceId': record['deviceId'].toString(),
            'deleted': record['operation'] == 'delete' ? 1 : 0,
          };
          await txn.insert(
            'sync_applied_versions',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          versions['${row['tableName']}|${row['recordKey']}'] = row;
        }

        await _renumberActiveSeriesTxn(txn);
        await _recalculateExpectedHatchDatesTxn(txn);
      } finally {
        await _setSyncSuppressed(txn, false);
      }
    });

    await synchronizeAutomaticSaleStatuses();
    await synchronizeBirdAgeGroups();
    return appliedCount;
  }

  Map<String, dynamic> _sanitizeSyncRow(
    String table,
    Map<String, dynamic> rawRow,
  ) {
    final row = Map<String, dynamic>.from(rawRow);
    if (table == 'pair_sessions' ||
        table == 'bird_events' ||
        table == 'activity_events') {
      row.remove('id');
    }
    if (table == 'cages' && row['identityMode'] == 'series') {
      row.remove('identifier');
    }
    return row;
  }

  String? _syncRecordKey(String table, Map<String, dynamic> row) {
    if (table == 'cage_merge_links') {
      final a = row['cageAId']?.toString();
      final b = row['cageBId']?.toString();
      return a == null || b == null ? null : '$a|$b';
    }
    if (table == 'pair_sessions' ||
        table == 'bird_events' ||
        table == 'activity_events') {
      return row['syncId']?.toString();
    }
    return row['id']?.toString();
  }

  Future<Map<String, dynamic>?> _readSyncRow(
    DatabaseExecutor executor,
    String table,
    String recordKey,
  ) async {
    late final List<Map<String, dynamic>> rows;
    if (table == 'cage_merge_links') {
      final parts = recordKey.split('|');
      if (parts.length != 2) return null;
      rows = await executor.query(
        table,
        where: 'cageAId = ? AND cageBId = ?',
        whereArgs: parts,
        limit: 1,
      );
    } else if (table == 'pair_sessions' ||
        table == 'bird_events' ||
        table == 'activity_events') {
      rows = await executor.query(
        table,
        where: 'syncId = ?',
        whereArgs: [recordKey],
        limit: 1,
      );
    } else {
      rows = await executor.query(
        table,
        where: 'id = ?',
        whereArgs: [recordKey],
        limit: 1,
      );
    }
    if (rows.isEmpty) return null;
    return _sanitizeSyncRow(table, rows.first);
  }

  Future<void> _upsertSyncRow(
    DatabaseExecutor executor,
    String table,
    Map<String, dynamic> row,
    String recordKey,
  ) async {
    if (table == 'cage_merge_links') {
      final parts = recordKey.split('|');
      if (parts.length != 2) return;
      row['cageAId'] = parts[0];
      row['cageBId'] = parts[1];
      final existing = await executor.query(
        table,
        columns: ['cageAId'],
        where: 'cageAId = ? AND cageBId = ?',
        whereArgs: parts,
        limit: 1,
      );
      if (existing.isEmpty) {
        await executor.insert(table, row);
      } else {
        await executor.update(
          table,
          row,
          where: 'cageAId = ? AND cageBId = ?',
          whereArgs: parts,
        );
      }
      return;
    }

    if (table == 'pair_sessions' ||
        table == 'bird_events' ||
        table == 'activity_events') {
      row['syncId'] = recordKey;
      final existing = await executor.query(
        table,
        columns: ['id'],
        where: 'syncId = ?',
        whereArgs: [recordKey],
        limit: 1,
      );
      if (existing.isEmpty) {
        await executor.insert(table, row);
      } else {
        await executor.update(
          table,
          row,
          where: 'syncId = ?',
          whereArgs: [recordKey],
        );
      }
      return;
    }

    row['id'] = recordKey;
    if (table == 'cages' && !row.containsKey('identifier')) {
      row['identifier'] = '__sync__$recordKey';
    }
    final existing = await executor.query(
      table,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [recordKey],
      limit: 1,
    );
    if (existing.isEmpty) {
      await executor.insert(table, row);
    } else {
      await executor.update(
        table,
        row,
        where: 'id = ?',
        whereArgs: [recordKey],
      );
    }
  }

  Future<void> _deleteSyncRow(
    DatabaseExecutor executor,
    String table,
    String recordKey,
  ) async {
    if (table == 'cage_merge_links') {
      final parts = recordKey.split('|');
      if (parts.length != 2) return;
      await executor.delete(
        table,
        where: 'cageAId = ? AND cageBId = ?',
        whereArgs: parts,
      );
      return;
    }
    if (table == 'pair_sessions' ||
        table == 'bird_events' ||
        table == 'activity_events') {
      await executor.delete(
        table,
        where: 'syncId = ?',
        whereArgs: [recordKey],
      );
      return;
    }
    await executor.delete(
      table,
      where: 'id = ?',
      whereArgs: [recordKey],
    );
  }

  Future<void> _recalculateExpectedHatchDatesTxn(
    DatabaseExecutor executor,
  ) async {
    await executor.rawUpdate('''
      UPDATE eggs
      SET expectedHatchDate = date(
        laidDate,
        '+' || COALESCE(
          (
            SELECT clutch.incubationDaysOverride
            FROM clutches clutch
            WHERE clutch.id = COALESCE(eggs.currentClutchId, eggs.clutchId)
          ),
          (
            SELECT species.incubationDays
            FROM clutches clutch
            INNER JOIN pairs pair ON pair.id = clutch.pairId
            INNER JOIN birds male ON male.id = pair.maleBirdId
            INNER JOIN species ON species.id = male.speciesId
            WHERE clutch.id = COALESCE(eggs.currentClutchId, eggs.clutchId)
          )
        ) || ' days'
      )
      WHERE status IN ('Incubating', 'Fertile')
        AND laidDate IS NOT NULL
    ''');
  }

  Future<bool> birdRingNumberExists(
      String ringNumber, {
        String? excludeBirdId,
      }) async {
    final db = await database;
    final clean = ringNumber.trim();
    if (clean.isEmpty) return false;
    final numeric = int.tryParse(clean);

    final exactOrNumeric = numeric == null
        ? 'LOWER(TRIM(ringNumber)) = LOWER(?)'
        : '''(
            LOWER(TRIM(ringNumber)) = LOWER(?)
            OR (
              TRIM(ringNumber) <> ''
              AND TRIM(ringNumber) NOT GLOB '*[^0-9]*'
              AND CAST(TRIM(ringNumber) AS INTEGER) = ?
            )
          )''';
    final where = excludeBirdId == null
        ? exactOrNumeric
        : '($exactOrNumeric) AND id != ?';
    final args = <Object?>[clean];
    if (numeric != null) args.add(numeric);
    if (excludeBirdId != null) args.add(excludeBirdId);

    final result = await db.query(
      'birds',
      columns: ['id'],
      where: where,
      whereArgs: args,
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<bool> cageIdentifierExists(
      String identifier, {
        String? excludeCageId,
      }) async {
    final db = await database;

    final result = await db.query(
      'cages',
      columns: ['id'],
      where: excludeCageId == null
          ? 'identifier = ? COLLATE NOCASE AND COALESCE(active, 1) = 1 '
              'AND mergedIntoId IS NULL'
          : 'identifier = ? COLLATE NOCASE AND id != ? '
              'AND COALESCE(active, 1) = 1 AND mergedIntoId IS NULL',
      whereArgs: excludeCageId == null
          ? [identifier.trim()]
          : [identifier.trim(), excludeCageId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<bool> _columnExists(
      Database db,
      String tableName,
      String columnName,
      ) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');

    return columns.any(
          (column) => column['name'] == columnName,
    );
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String tableName,
    String columnName,
    String definition,
  ) async {
    final exists = await _columnExists(
      db,
      tableName,
      columnName,
    );

    if (!exists) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
      );
    }
  }

  Future<void> _createUniqueIndexes(Database db) async {
    await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_birds_ring_unique
    ON birds(ringNumber COLLATE NOCASE)
    WHERE TRIM(ringNumber) <> ''
  ''');

    await db.execute('DROP INDEX IF EXISTS idx_cages_identifier_unique');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_cages_identifier_unique
      ON cages(identifier COLLATE NOCASE)
      WHERE COALESCE(active, 1) = 1 AND mergedIntoId IS NULL
    ''');
  }

  Future<void> _onUpgrade(
      Database db,
      int oldVersion,
      int newVersion,
      ) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cages(
          id TEXT PRIMARY KEY,
          identifier TEXT NOT NULL,
          type TEXT NOT NULL,
          location TEXT,
          notes TEXT
        )
      ''');

      final hasCageId = await _columnExists(
        db,
        'birds',
        'cageId',
      );

      if (!hasCageId) {
        await db.execute(
          'ALTER TABLE birds ADD COLUMN cageId TEXT',
        );
      }
    }

    if (oldVersion < 3) {
      await _createPairsTable(db);
    }

    if (oldVersion < 4) {
      await _createUniqueIndexes(db);
    }

    if (oldVersion < 5) {
      await _createSpeciesTable(db);

      await _addColumnIfMissing(db, 'birds', 'speciesId', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'ageGroup', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'sourceDate', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'sourcePerson', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'sourcePlace', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'sourceDetails', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'parentPairId', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'notes', 'TEXT');

      await _seedDefaultSpecies(db);
    }

    if (oldVersion < 6) {
      await _addColumnIfMissing(db, 'pairs', 'identifier', 'TEXT');
      await _addColumnIfMissing(db, 'pairs', 'notes', 'TEXT');
      await _addColumnIfMissing(
        db,
        'pairs',
        'breedingStatus',
        "TEXT NOT NULL DEFAULT 'New'",
      );

      await _addColumnIfMissing(db, 'birds', 'nestClutchId', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'leftNestDate', 'TEXT');
      await _addColumnIfMissing(
        db,
        'birds',
        'saleStatus',
        "TEXT NOT NULL DEFAULT 'Not for Sale'",
      );
      await _addColumnIfMissing(db, 'birds', 'reservedBuyer', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'reservedPrice', 'REAL');
      await _addColumnIfMissing(db, 'birds', 'reservedAt', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'soldBuyer', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'soldPrice', 'REAL');
      await _addColumnIfMissing(db, 'birds', 'soldAt', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'soldNotes', 'TEXT');

      await _createBreedingTables(db);
      await _backfillPairIdentifiers(db);
    }
    if (oldVersion < 7) {
      await _addColumnIfMissing(
        db,
        'species',
        'clutchWindowDays',
        'INTEGER NOT NULL DEFAULT 15',
      );
      await _addColumnIfMissing(db, 'birds', 'fosteredAt', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'fosterNotes', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'removedAt', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'removalReason', 'TEXT');
      await _addColumnIfMissing(
        db,
        'clutches',
        'clutchNumber',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(db, 'eggs', 'currentClutchId', 'TEXT');
      await _addColumnIfMissing(db, 'eggs', 'fosteredAt', 'TEXT');
      await _addColumnIfMissing(db, 'eggs', 'fosterNotes', 'TEXT');
      await _createSupportTables(db);

      final pairs = await db.query('pairs', columns: ['id']);
      for (final pair in pairs) {
        final clutches = await db.query(
          'clutches',
          columns: ['id'],
          where: 'pairId = ?',
          whereArgs: [pair['id']],
          orderBy: 'startedAt ASC, createdAt ASC',
        );
        for (var index = 0; index < clutches.length; index++) {
          await db.update(
            'clutches',
            {'clutchNumber': index + 1},
            where: 'id = ?',
            whereArgs: [clutches[index]['id']],
          );
        }
      }

      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_clutch_number_unique
        ON clutches(pairId, clutchNumber)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_eggs_current_clutch
        ON eggs(currentClutchId)
      ''');
    }

    if (oldVersion < 8) {
      await _addColumnIfMissing(db, 'species', 'chickToYoungDays', 'INTEGER');
      final hasOldMonths = await _columnExists(
        db,
        'species',
        'chickToYoungMonths',
      );
      if (hasOldMonths) {
        await db.execute('''
          UPDATE species
          SET chickToYoungDays = chickToYoungMonths * 30
          WHERE chickToYoungDays IS NULL
            AND chickToYoungMonths IS NOT NULL
        ''');
      }

      final clutches = await db.query('clutches', columns: ['id']);
      for (final clutch in clutches) {
        await _renumberEggsForClutchTxn(
          db,
          clutch['id'].toString(),
        );
      }
    }

    if (oldVersion < 9) {
      await _createActivityTables(db);
      await db.execute('''
        INSERT OR IGNORE INTO activity_events(
          category, eventType, eventDate, title, details,
          entityType, entityId, birdId, sourceKey
        )
        SELECT
          'Birds', event.eventType, event.eventDate,
          CASE
            WHEN COALESCE(bird.name, '') = '' THEN bird.ringNumber
            ELSE bird.ringNumber || ' — ' || bird.name
          END,
          event.details, 'Bird', event.birdId, event.birdId,
          'bird_event_' || event.id
        FROM bird_events event
        INNER JOIN birds bird ON bird.id = event.birdId
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO activity_events(
          category, eventType, eventDate, title, details,
          entityType, entityId, birdId, amount, financeType, sourceKey
        )
        SELECT
          'Finance', transactionRow.type, transactionRow.date,
          transactionRow.category,
          transactionRow.notes,
          'Finance', transactionRow.id, transactionRow.birdId,
          transactionRow.amount, transactionRow.type,
          'finance_' || transactionRow.id
        FROM finance_transactions transactionRow
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO activity_events(
          category, eventType, eventDate, title, details,
          entityType, entityId, sourceKey
        )
        SELECT
          'Breeding', 'Pair Created', pair.createdAt,
          COALESCE(pair.identifier, 'Pair'), pair.notes,
          'Pair', pair.id, 'pair_created_' || pair.id
        FROM pairs pair
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO activity_events(
          category, eventType, eventDate, title, details,
          entityType, entityId, sourceKey
        )
        SELECT
          'Breeding', 'Clutch Created', clutch.createdAt,
          COALESCE(pair.identifier, 'Pair') || ' · Clutch ' || clutch.clutchNumber,
          clutch.notes, 'Clutch', clutch.id, 'clutch_created_' || clutch.id
        FROM clutches clutch
        INNER JOIN pairs pair ON pair.id = clutch.pairId
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO activity_events(
          category, eventType, eventDate, title, details,
          entityType, entityId, sourceKey
        )
        SELECT
          'Breeding', 'Egg Added', egg.laidDate,
          COALESCE(pair.identifier, 'Pair') || ' · Clutch ' || clutch.clutchNumber ||
            ' · Egg ' || egg.eggNumber,
          egg.notes, 'Egg', egg.id, 'egg_added_' || egg.id
        FROM eggs egg
        INNER JOIN clutches clutch ON clutch.id = egg.clutchId
        INNER JOIN pairs pair ON pair.id = clutch.pairId
      ''');
    }

    if (oldVersion < 10) {
      await _addColumnIfMissing(
        db,
        'cages',
        'identityMode',
        "TEXT NOT NULL DEFAULT 'named'",
      );
      await _addColumnIfMissing(db, 'cages', 'physicalCageId', 'TEXT');
      await _addColumnIfMissing(db, 'cages', 'physicalName', 'TEXT');
      await _addColumnIfMissing(
        db,
        'cages',
        'portionIndex',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(db, 'cages', 'seriesOrder', 'INTEGER');
      await _addColumnIfMissing(
        db,
        'cages',
        'active',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(db, 'cages', 'mergedIntoId', 'TEXT');
      await _addColumnIfMissing(db, 'cages', 'soldAt', 'TEXT');
      await _addColumnIfMissing(db, 'cages', 'soldPrice', 'REAL');
      await _addColumnIfMissing(db, 'cages', 'soldBuyer', 'TEXT');
      await _addColumnIfMissing(db, 'cages', 'soldNotes', 'TEXT');
      await _addColumnIfMissing(db, 'cages', 'createdAt', 'TEXT');
      await _addColumnIfMissing(db, 'cages', 'updatedAt', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'createdAt', 'TEXT');
      await _addColumnIfMissing(db, 'birds', 'originClutchId', 'TEXT');

      final migratedAt = DateTime.now().toIso8601String();
      await db.execute('''
        UPDATE cages
        SET physicalCageId = COALESCE(physicalCageId, id),
            physicalName = COALESCE(NULLIF(physicalName, ''), identifier),
            identityMode = COALESCE(NULLIF(identityMode, ''), 'named'),
            portionIndex = COALESCE(portionIndex, 1),
            active = COALESCE(active, 1),
            createdAt = COALESCE(createdAt, ?),
            updatedAt = COALESCE(updatedAt, ?)
      ''', [migratedAt, migratedAt]);
      await db.execute('''
        UPDATE birds
        SET createdAt = COALESCE(createdAt, sourceDate, hatchDate, ?)
      ''', [migratedAt]);

      await _createCageStructureTables(db);
      await _createPairsTable(db);
      await db.execute('''
        INSERT INTO pair_sessions(pairId, startedAt, endedAt, endReason, cageId)
        SELECT pair.id, pair.createdAt, pair.endedAt, pair.endReason, male.cageId
        FROM pairs pair
        LEFT JOIN birds male ON male.id = pair.maleBirdId
        WHERE NOT EXISTS(
          SELECT 1 FROM pair_sessions session WHERE session.pairId = pair.id
        )
      ''');
      await _createUniqueIndexes(db);
    }

    if (oldVersion < 11) {
      await _addColumnIfMissing(db, 'pair_sessions', 'syncId', 'TEXT');
      await _addColumnIfMissing(db, 'bird_events', 'syncId', 'TEXT');
      await _addColumnIfMissing(db, 'activity_events', 'syncId', 'TEXT');
      // Legacy rows receive deterministic IDs. Two devices restored from the
      // same pre-sync backup will therefore recognize the same history rows
      // instead of uploading duplicate sessions and events.
      await db.execute('''
        UPDATE pair_sessions
        SET syncId = 'legacy-session|' || pairId || '|' || startedAt || '|' || id
        WHERE syncId IS NULL OR syncId = ''
      ''');
      await db.execute('''
        UPDATE bird_events
        SET syncId = 'legacy-bird-event|' || birdId || '|' || id
        WHERE syncId IS NULL OR syncId = ''
      ''');
      await db.execute('''
        UPDATE activity_events
        SET syncId = 'legacy-activity|' ||
          COALESCE(NULLIF(sourceKey, ''),
            COALESCE(entityType, '') || '|' ||
            COALESCE(entityId, '') || '|' || id)
        WHERE syncId IS NULL OR syncId = ''
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_pair_sessions_sync_id
        ON pair_sessions(syncId)
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_bird_events_sync_id
        ON bird_events(syncId)
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_activity_events_sync_id
        ON activity_events(syncId)
      ''');
      await _createSyncInfrastructure(db);
      await db.execute('''
        UPDATE sync_runtime
        SET lastUserChangeAt = COALESCE(
          lastUserChangeAt,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        WHERE id = 1
          AND (
            EXISTS(SELECT 1 FROM birds LIMIT 1)
            OR EXISTS(SELECT 1 FROM cages LIMIT 1)
            OR EXISTS(SELECT 1 FROM pairs LIMIT 1)
            OR EXISTS(SELECT 1 FROM clutches LIMIT 1)
            OR EXISTS(SELECT 1 FROM eggs LIMIT 1)
            OR EXISTS(SELECT 1 FROM finance_transactions LIMIT 1)
          )
      ''');
    }

    if (oldVersion < 12) {
      await _addColumnIfMissing(db, 'birds', 'estimatedAgeDays', 'INTEGER');
      await _addColumnIfMissing(db, 'clutches', 'expectedEggs', 'INTEGER');
      await db.execute("""
        UPDATE pairs
        SET breedingStatus = CASE
          WHEN endedAt IS NOT NULL THEN 'Inactive'
          WHEN breedingStatus = 'Breeding' OR EXISTS(
            SELECT 1 FROM clutches clutch
            WHERE clutch.pairId = pairs.id AND clutch.status = 'Active'
          ) THEN 'Active'
          ELSE 'Inactive'
        END
      """);
      await db.execute("""
        DELETE FROM bird_events
        WHERE eventType = 'Cage Changed'
      """);
      await db.execute("""
        DELETE FROM activity_events
        WHERE eventType = 'Pair Moved'
      """);
      await db.execute("""
        UPDATE birds
        SET cageId = NULL
        WHERE COALESCE(active, 1) = 0
      """);
      await db.execute("""
        UPDATE pair_sessions
        SET cageId = NULL
        WHERE endedAt IS NOT NULL
      """);
    }

    if (oldVersion < 13) {
      await db.execute('DROP INDEX IF EXISTS idx_birds_ring_unique');
      await _createUniqueIndexes(db);
    }

    if (oldVersion < 14) {
      await _createManagementTables(db);
      await _createSyncInfrastructure(db);

      final now = DateTime.now().toIso8601String();
      final mutations = await db.rawQuery('''
        SELECT DISTINCT speciesId, TRIM(mutation) AS value
        FROM birds
        WHERE TRIM(COALESCE(mutation, '')) <> ''
      ''');
      for (final row in mutations) {
        final value = row['value']?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        final duplicate = await db.query(
          'managed_bird_values',
          columns: ['id'],
          where: "kind = 'Mutation' AND ((speciesId = ?) OR (speciesId IS NULL AND ? IS NULL)) AND value = ? COLLATE NOCASE",
          whereArgs: [row['speciesId'], row['speciesId'], value],
          limit: 1,
        );
        if (duplicate.isEmpty) {
          await db.insert('managed_bird_values', {
            'id': const Uuid().v4(),
            'kind': 'Mutation',
            'speciesId': row['speciesId'],
            'value': value,
            'active': 1,
            'createdAt': now,
          });
        }
      }
      final names = await db.rawQuery('''
        SELECT DISTINCT TRIM(name) AS value
        FROM birds
        WHERE TRIM(COALESCE(name, '')) <> ''
      ''');
      for (final row in names) {
        final value = row['value']?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        final duplicate = await db.query(
          'managed_bird_values',
          columns: ['id'],
          where: "kind = 'Name' AND speciesId IS NULL AND value = ? COLLATE NOCASE",
          whereArgs: [value],
          limit: 1,
        );
        if (duplicate.isEmpty) {
          await db.insert('managed_bird_values', {
            'id': const Uuid().v4(),
            'kind': 'Name',
            'speciesId': null,
            'value': value,
            'active': 1,
            'createdAt': now,
          });
        }
      }

      final sourceBirds = await db.rawQuery('''
        SELECT id, ringNumber, name, source, sourceDate, hatchDate, parentPairId
        FROM birds
        WHERE source IN ('Purchase', 'Bred', 'Gift', 'Caught', 'Rescued')
          AND NOT (source = 'Bred' AND parentPairId IS NOT NULL AND hatchDate IS NOT NULL)
      ''');
      for (final row in sourceBirds) {
        final source = row['source']?.toString() ?? '';
        final eventType = switch (source) {
          'Purchase' => 'Purchased',
          'Bred' => 'Bred Bird Added',
          'Gift' => 'Gifted',
          'Caught' => 'Caught',
          'Rescued' => 'Rescued',
          _ => 'Added',
        };
        final eventDate = DateTime.tryParse(
              row['sourceDate']?.toString() ?? row['hatchDate']?.toString() ?? '',
            ) ??
            DateTime.now();
        final ring = row['ringNumber']?.toString().trim() ?? '';
        final name = row['name']?.toString().trim() ?? '';
        final title = name.isEmpty
            ? (ring.isEmpty ? 'Bird' : ring)
            : (ring.isEmpty ? name : '$ring — $name');
        await _addActivityEventTxn(
          db,
          category: 'Birds',
          eventType: eventType,
          eventDate: eventDate,
          title: title,
          details: source.isEmpty ? null : 'Source: $source',
          entityType: 'Bird',
          entityId: row['id']?.toString(),
          birdId: row['id']?.toString(),
          sourceKey: 'history_source_${row['id']}',
        );
      }

      final clutches = await db.rawQuery('''
        SELECT clutch.id, clutch.firstEggDate, pair.identifier AS pairIdentifier
        FROM clutches clutch
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        WHERE clutch.firstEggDate IS NOT NULL
      ''');
      for (final row in clutches) {
        final date = DateTime.tryParse(row['firstEggDate']?.toString() ?? '');
        if (date == null) continue;
        await _addActivityEventTxn(
          db,
          category: 'Breeding',
          eventType: 'First Egg Laid',
          eventDate: date,
          title: row['pairIdentifier']?.toString() ?? 'Pair',
          details: 'First egg of clutch',
          entityType: 'Clutch',
          entityId: row['id']?.toString(),
          sourceKey: 'history_first_egg_${row['id']}',
        );
      }

      final hatched = await db.rawQuery('''
        SELECT bird.id, bird.hatchDate, bird.parentPairId, pair.identifier AS pairIdentifier
        FROM birds bird
        LEFT JOIN pairs pair ON pair.id = bird.parentPairId
        WHERE bird.parentPairId IS NOT NULL AND bird.hatchDate IS NOT NULL
      ''');
      for (final row in hatched) {
        final date = DateTime.tryParse(row['hatchDate']?.toString() ?? '');
        if (date == null) continue;
        await _addActivityEventTxn(
          db,
          category: 'Breeding',
          eventType: 'Chick Hatched',
          eventDate: date,
          title: row['pairIdentifier']?.toString() ?? 'Pair',
          entityType: 'Pair',
          entityId: row['parentPairId']?.toString(),
          birdId: row['id']?.toString(),
          sourceKey: 'history_hatched_${row['id']}',
        );
      }

      await _createSyncTriggers(db);
    }

    if (oldVersion < 15) {
      await _createWorkflowTables(db);
      await _createSyncInfrastructure(db);
      await _createSyncTriggers(db);
    }
  }

  Future<void> _backfillPairIdentifiers(Database db) async {
    final pairs = await db.query(
      'pairs',
      columns: ['id', 'identifier', 'createdAt'],
      orderBy: 'createdAt ASC',
    );

    var nextNumber = 1;
    for (final pair in pairs) {
      final existing = pair['identifier']?.toString().trim() ?? '';
      if (existing.isNotEmpty) continue;

      var identifier = 'P-${nextNumber.toString().padLeft(3, '0')}';
      while ((await db.query(
        'pairs',
        columns: ['id'],
        where: 'identifier = ? COLLATE NOCASE',
        whereArgs: [identifier],
        limit: 1,
      )).isNotEmpty) {
        nextNumber++;
        identifier = 'P-${nextNumber.toString().padLeft(3, '0')}';
      }

      await db.update(
        'pairs',
        {'identifier': identifier},
        where: 'id = ?',
        whereArgs: [pair['id']],
      );
      nextNumber++;
    }

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_pairs_identifier_unique
      ON pairs(identifier COLLATE NOCASE)
      WHERE identifier IS NOT NULL
    ''');
  }

  // ---------------------------------------------------------------------------
  // Birds
  // ---------------------------------------------------------------------------

  Future<void> _linkBredBirdTxn(
    DatabaseExecutor txn, {
    required String birdId,
    required String pairId,
    required bool addBirdEvents,
  }) async {
    final rows = await txn.rawQuery('''
      SELECT
        bird.ringNumber,
        bird.name,
        bird.hatchDate,
        bird.createdAt,
        pair.identifier AS pairIdentifier,
        pair.maleBirdId,
        pair.femaleBirdId,
        species.incubationDays
      FROM birds bird
      INNER JOIN pairs pair ON pair.id = ?
      LEFT JOIN birds male ON male.id = pair.maleBirdId
      LEFT JOIN species species ON species.id = male.speciesId
      WHERE bird.id = ?
      LIMIT 1
    ''', [pairId, birdId]);
    if (rows.isEmpty) return;

    final row = rows.first;
    final hatchDate = DateTime.tryParse(row['hatchDate']?.toString() ?? '');
    final recordedAt =
        DateTime.tryParse(row['createdAt']?.toString() ?? '') ?? DateTime.now();
    final ring = row['ringNumber']?.toString() ?? 'Bird';
    final name = row['name']?.toString().trim() ?? '';
    final birdLabel = name.isEmpty ? ring : '$ring ($name)';
    final pairLabel = row['pairIdentifier']?.toString() ?? 'Pair';

    String? matchingClutchId;
    if (hatchDate != null) {
      final clutchRows = await txn.rawQuery('''
        SELECT
          clutch.id,
          clutch.firstEggDate,
          clutch.startedAt,
          clutch.incubationDaysOverride,
          MIN(egg.expectedHatchDate) AS expectedHatchDate
        FROM clutches clutch
        LEFT JOIN eggs egg ON egg.clutchId = clutch.id
        WHERE clutch.pairId = ?
        GROUP BY clutch.id
      ''', [pairId]);
      var closestDays = 999999;
      for (final clutch in clutchRows) {
        var expected = DateTime.tryParse(
          clutch['expectedHatchDate']?.toString() ?? '',
        );
        if (expected == null) {
          final base = DateTime.tryParse(
            clutch['firstEggDate']?.toString() ??
                clutch['startedAt']?.toString() ??
                '',
          );
          final incubation =
              (clutch['incubationDaysOverride'] as num?)?.toInt() ??
                  (row['incubationDays'] as num?)?.toInt();
          if (base != null && incubation != null) {
            expected = base.add(Duration(days: incubation));
          }
        }
        if (expected == null) continue;
        final difference = DateTime(
          expected.year,
          expected.month,
          expected.day,
        )
            .difference(DateTime(
              hatchDate.year,
              hatchDate.month,
              hatchDate.day,
            ))
            .inDays
            .abs();
        if (difference <= 10 && difference < closestDays) {
          closestDays = difference;
          matchingClutchId = clutch['id']?.toString();
        }
      }
    }

    await txn.update(
      'birds',
      {'originClutchId': matchingClutchId},
      where: 'id = ?',
      whereArgs: [birdId],
    );

    if (addBirdEvents) {
      final eventDate = hatchDate ?? recordedAt;
      final details = [
        'Offspring of $pairLabel',
        if (matchingClutchId != null) 'Linked to matching historical clutch',
        'Record entered ${recordedAt.toIso8601String().split('T').first}',
      ].join(' · ');
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: 'Offspring Added',
        eventDate: eventDate,
        details: details,
      );
      for (final parentId in [row['maleBirdId'], row['femaleBirdId']]) {
        if (parentId == null) continue;
        await _addBirdEventTxn(
          txn,
          birdId: parentId.toString(),
          eventType: 'Offspring Added',
          eventDate: eventDate,
          details: '$birdLabel added as offspring of $pairLabel',
        );
      }
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Offspring Added',
        eventDate: eventDate,
        title: '$pairLabel · $birdLabel',
        details: details,
        entityType: 'Pair',
        entityId: pairId,
        birdId: birdId,
        sourceKey: 'offspring_$birdId',
      );
    }
  }

  Future<void> updateBird(
    String birdId,
    Map<String, dynamic> values,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final previous = await txn.query(
        'birds',
        columns: ['parentPairId', 'source', 'cageId', 'nestClutchId', 'leftNestDate'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      final updateValues = Map<String, dynamic>.from(values);
      if (previous.isNotEmpty && updateValues.containsKey('cageId')) {
        final previousCageId = previous.first['cageId']?.toString();
        final nextCageId = updateValues['cageId']?.toString();
        final isChickInNest = previous.first['nestClutchId'] != null &&
            previous.first['leftNestDate'] == null;
        if (isChickInNest && nextCageId != previousCageId) {
          throw StateError(
            'Move this youngster from its clutch so a permanent ring can be assigned.',
          );
        }
      }
      final newPairId = updateValues['parentPairId']?.toString();
      if (updateValues['source'] != 'Bred' ||
          newPairId == null ||
          newPairId.isEmpty) {
        updateValues['originClutchId'] = null;
      }
      await txn.update(
        'birds',
        updateValues,
        where: 'id = ?',
        whereArgs: [birdId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: 'Updated',
        eventDate: DateTime.now(),
        details: 'Bird information updated',
      );
      final previousCageId = previous.isEmpty
          ? null
          : previous.first['cageId']?.toString();
      final nextCageId = updateValues.containsKey('cageId')
          ? updateValues['cageId']?.toString()
          : previousCageId;
      if (previousCageId != null &&
          previousCageId.isNotEmpty &&
          nextCageId != previousCageId) {
        await _addBirdEventTxn(
          txn,
          birdId: birdId,
          eventType: 'Cage Changed',
          eventDate: DateTime.now(),
          details: 'Changed cage',
        );
      }
      final pairId = updateValues['parentPairId']?.toString();
      final wasPairId = previous.isEmpty
          ? null
          : previous.first['parentPairId']?.toString();
      if (updateValues['source'] == 'Bred' &&
          pairId != null &&
          pairId.isNotEmpty) {
        await _linkBredBirdTxn(
          txn,
          birdId: birdId,
          pairId: pairId,
          addBirdEvents: pairId != wasPairId,
        );
      }
    });
  }

  Future<void> insertBird(Map<String, dynamic> bird) async {
    final db = await database;
    await db.transaction((txn) async {
      final values = Map<String, dynamic>.from(bird);
      values['createdAt'] ??= DateTime.now().toIso8601String();
      await txn.insert(
        'birds',
        values,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final birdId = values['id'].toString();
      final source = values['source']?.toString() ?? '';
      final eventDate = DateTime.tryParse(
            values['sourceDate']?.toString() ?? values['hatchDate']?.toString() ?? '',
          ) ??
          DateTime.now();
      final eventType = switch (source) {
        'Purchase' => 'Purchased',
        'Bred' => 'Bred Bird Added',
        'Gift' => 'Gifted',
        'Caught' => 'Caught',
        'Rescued' => 'Rescued',
        _ => 'Added',
      };
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: eventType,
        eventDate: eventDate,
        details: source.isEmpty ? 'Bird record created' : 'Source: $source',
      );

      if (source == 'Purchase') {
        final price = (values['purchasePrice'] as num?)?.toDouble();
        if (price == null || price <= 0) {
          throw StateError('Purchase price is required for a purchased bird.');
        }
        final transactionId = 'purchase_${birdId}_${DateTime.now().microsecondsSinceEpoch}';
        final seller = values['sourcePerson']?.toString().trim() ?? '';
        final notes = values['notes']?.toString().trim() ?? '';
        final financeNotes = [
          if (seller.isNotEmpty) 'Seller: $seller',
          if (notes.isNotEmpty) notes,
        ].join(' · ');
        await txn.insert('finance_transactions', {
          'id': transactionId,
          'type': 'Expense',
          'category': 'Bird Purchase',
          'amount': price,
          'date': eventDate.toIso8601String(),
          'notes': financeNotes,
          'birdId': birdId,
          'createdAt': DateTime.now().toIso8601String(),
        });
        await _addActivityEventTxn(
          txn,
          category: 'Finance',
          eventType: 'Expense',
          eventDate: eventDate,
          title: 'Bird Purchase',
          details: financeNotes,
          entityType: 'Finance',
          entityId: transactionId,
          birdId: birdId,
          amount: price,
          financeType: 'Expense',
          sourceKey: 'finance_$transactionId',
        );
      }

      final pairId = values['parentPairId']?.toString();
      if (values['source'] == 'Bred' && pairId != null && pairId.isNotEmpty) {
        await _linkBredBirdTxn(
          txn,
          birdId: birdId,
          pairId: pairId,
          addBirdEvents: true,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> _queryBirds({String? birdId}) async {
    await synchronizeAutomaticSaleStatuses();
    final db = await database;
    final whereClause = birdId == null ? '' : 'WHERE b.id = ?';

    return db.rawQuery(
      '''
      SELECT
        b.*,
        s.name AS speciesName,
        s.chickToYoungDays,
        s.adultAgeMonths,
        s.incubationDays,
        c.identifier AS cageIdentifier,
        p.id AS pairId,
        partner.id AS partnerBirdId,
        partner.ringNumber AS partnerRingNumber,
        partner.name AS partnerName,
        partner.gender AS partnerGender,
        parentMale.id AS parentMaleBirdId,
        parentMale.ringNumber AS parentMaleRingNumber,
        parentMale.name AS parentMaleName,
        parentMale.gender AS parentMaleGender,
        parentFemale.id AS parentFemaleBirdId,
        parentFemale.ringNumber AS parentFemaleRingNumber,
        parentFemale.name AS parentFemaleName,
        parentFemale.gender AS parentFemaleGender
      FROM birds b
      LEFT JOIN species s ON s.id = b.speciesId
      LEFT JOIN cages c ON c.id = b.cageId
      LEFT JOIN pairs p
        ON p.endedAt IS NULL
        AND (p.maleBirdId = b.id OR p.femaleBirdId = b.id)
      LEFT JOIN birds partner
        ON partner.id = CASE
          WHEN p.maleBirdId = b.id THEN p.femaleBirdId
          ELSE p.maleBirdId
        END
      LEFT JOIN pairs parentPair ON parentPair.id = b.parentPairId
      LEFT JOIN birds parentMale ON parentMale.id = parentPair.maleBirdId
      LEFT JOIN birds parentFemale ON parentFemale.id = parentPair.femaleBirdId
      $whereClause
      ORDER BY LENGTH(b.ringNumber), b.ringNumber COLLATE NOCASE ASC
      ''',
      birdId == null ? const [] : [birdId],
    );
  }

  Future<List<Map<String, dynamic>>> getBirds() {
    return _queryBirds();
  }

  Future<void> synchronizeAutomaticSaleStatuses() async {
    final db = await database;
    await db.transaction((txn) async {
      await _setSyncSuppressed(txn, true);
      try {
        final pairedRows = await txn.rawQuery('''
          SELECT DISTINCT bird.id
          FROM birds bird
          INNER JOIN pairs pair
            ON pair.endedAt IS NULL
            AND (pair.maleBirdId = bird.id OR pair.femaleBirdId = bird.id)
          WHERE COALESCE(bird.active, 1) = 1
            AND bird.saleStatus != 'Not for Sale'
            AND bird.saleStatus != 'Sold'
        ''');
        for (final row in pairedRows) {
          final id = row['id'].toString();
          await txn.update(
            'birds',
            {
              'saleStatus': 'Not for Sale',
              'reservedBuyer': null,
              'reservedPrice': null,
              'reservedAt': null,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          await _addBirdEventTxn(
            txn,
            birdId: id,
            eventType: 'Sale Status Changed',
            eventDate: DateTime.now(),
            details:
                'Automatically set to Not for Sale because the bird is paired',
          );
        }

      } finally {
        await _setSyncSuppressed(txn, false);
      }
    });
  }

  Future<Map<String, dynamic>?> getBirdById(String birdId) async {
    final result = await _queryBirds(birdId: birdId);
    return result.isEmpty ? null : result.first;
  }

  // ---------------------------------------------------------------------------
  // Species rules
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getSpecies() async {
    final db = await database;

    return db.query(
      'species',
      where: 'active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<void> insertSpecies(Map<String, dynamic> values) async {
    final db = await database;

    await db.insert(
      'species',
      values,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateSpecies(
    String speciesId,
    Map<String, dynamic> values,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.update(
        'species',
        values,
        where: 'id = ?',
        whereArgs: [speciesId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final incubationDays = values['incubationDays'] as int?;
      if (incubationDays != null) {
        await txn.rawUpdate('''
          UPDATE eggs
          SET expectedHatchDate = datetime(
            laidDate,
            '+' || ? || ' days'
          )
          WHERE status IN ('Incubating', 'Fertile')
            AND clutchId IN (
              SELECT clutch.id
              FROM clutches clutch
              INNER JOIN pairs pair ON pair.id = clutch.pairId
              INNER JOIN birds male ON male.id = pair.maleBirdId
              WHERE male.speciesId = ?
            )
        ''', [incubationDays, speciesId]);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Cages
  // ---------------------------------------------------------------------------

  Future<int> _nextSeriesOrderTxn(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery(
      'SELECT MAX(seriesOrder) AS maxOrder FROM cages WHERE identityMode = ?',
      ['series'],
    );
    return ((rows.first['maxOrder'] as num?)?.toInt() ?? 0) + 1;
  }

  Future<void> _renumberActiveSeriesTxn(DatabaseExecutor txn) async {
    final allSeries = await txn.query(
      'cages',
      columns: ['id', 'portionIndex', 'active', 'mergedIntoId'],
      where: "identityMode = 'series'",
    );

    for (final cage in allSeries) {
      await txn.update(
        'cages',
        {'identifier': '__series__${cage['id']}'},
        where: 'id = ?',
        whereArgs: [cage['id']],
      );
    }

    final activeSeries = await txn.query(
      'cages',
      columns: ['id'],
      where: "identityMode = 'series' AND COALESCE(active, 1) = 1 "
          'AND mergedIntoId IS NULL',
      orderBy: 'seriesOrder ASC, createdAt ASC, id ASC',
    );

    for (var index = 0; index < activeSeries.length; index++) {
      await txn.update(
        'cages',
        {
          'identifier': 'Cage${index + 1}',
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [activeSeries[index]['id']],
      );
    }

    for (final cage in allSeries) {
      final isActive = cage['active'] != 0;
      final mergedIntoId = cage['mergedIntoId']?.toString();
      if (isActive && (mergedIntoId == null || mergedIntoId.isEmpty)) continue;
      final prefix = isActive ? 'Merged' : 'Sold';
      final portion = (cage['portionIndex'] as num?)?.toInt() ?? 1;
      final id = cage['id'].toString();
      final suffix = id.length > 6 ? id.substring(0, 6) : id;
      await txn.update(
        'cages',
        {'identifier': '$prefix portion $portion · $suffix'},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> updateCage(
    String cageId,
    Map<String, dynamic> values,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'cages',
        where: 'id = ?',
        whereArgs: [cageId],
        limit: 1,
      );
      if (existing.isEmpty) throw StateError('Cage could not be found.');

      final current = existing.first;
      final identityMode = current['identityMode']?.toString() ?? 'named';
      final updateValues = Map<String, dynamic>.from(values)
        ..['updatedAt'] = DateTime.now().toIso8601String();

      if (identityMode == 'series') {
        updateValues.remove('identifier');
        final physicalCageId = current['physicalCageId']?.toString() ?? cageId;
        await txn.update(
          'cages',
          updateValues,
          where: 'physicalCageId = ?',
          whereArgs: [physicalCageId],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        await txn.update(
          'cages',
          updateValues,
          where: 'id = ?',
          whereArgs: [cageId],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      final rows = await txn.query(
        'cages',
        columns: ['identifier'],
        where: 'id = ?',
        whereArgs: [cageId],
        limit: 1,
      );
      await _addActivityEventTxn(
        txn,
        category: 'Cages',
        eventType: 'Cage Updated',
        eventDate: DateTime.now(),
        title: rows.isEmpty ? 'Cage' : rows.first['identifier'].toString(),
        details: 'Cage information updated',
        entityType: 'Cage',
        entityId: cageId,
      );
    });
  }

  Future<void> insertCage(Map<String, dynamic> cage) async {
    await insertCageConfiguration([cage]);
  }

  Future<void> insertCageConfiguration(
    List<Map<String, dynamic>> cageRows,
  ) async {
    if (cageRows.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      var nextSeriesOrder = await _nextSeriesOrderTxn(txn);
      final now = DateTime.now().toIso8601String();

      for (final original in cageRows) {
        final cage = Map<String, dynamic>.from(original);
        final mode = cage['identityMode']?.toString() ?? 'named';
        cage['identityMode'] = mode;
        cage['physicalCageId'] ??= cage['id'];
        cage['physicalName'] ??= cage['identifier'];
        cage['portionIndex'] ??= 1;
        cage['active'] ??= 1;
        cage['createdAt'] ??= now;
        cage['updatedAt'] ??= now;
        if (mode == 'series') {
          cage['seriesOrder'] ??= nextSeriesOrder++;
          cage['identifier'] = '__series__${cage['id']}';
        }
        await txn.insert(
          'cages',
          cage,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      await _renumberActiveSeriesTxn(txn);
      for (final cage in cageRows) {
        final row = await txn.query(
          'cages',
          columns: ['identifier', 'physicalName', 'notes'],
          where: 'id = ?',
          whereArgs: [cage['id']],
          limit: 1,
        );
        await _addActivityEventTxn(
          txn,
          category: 'Cages',
          eventType: 'Cage Added',
          eventDate: DateTime.now(),
          title: row.isEmpty ? 'Cage' : row.first['identifier'].toString(),
          details: row.isEmpty
              ? cage['notes']?.toString()
              : [
                  row.first['physicalName']?.toString() ?? '',
                  row.first['notes']?.toString() ?? '',
                ].where((value) => value.trim().isNotEmpty).join(' · '),
          entityType: 'Cage',
          entityId: cage['id']?.toString(),
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCages() async {
    final db = await database;
    return db.rawQuery('''
      SELECT cage.*,
        (SELECT COUNT(*) FROM cages merged
          WHERE merged.mergedIntoId = cage.id
            AND COALESCE(merged.active, 1) = 1) AS mergedCount,
        (SELECT COUNT(*) FROM birds bird
          WHERE bird.cageId = cage.id
            AND COALESCE(bird.active, 1) = 1) AS birdCount
      FROM cages cage
      WHERE COALESCE(cage.active, 1) = 1
        AND cage.mergedIntoId IS NULL
      ORDER BY
        CASE WHEN cage.identityMode = 'series' THEN 0 ELSE 1 END,
        cage.seriesOrder ASC,
        cage.identifier COLLATE NOCASE ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> getBirdCageSummary() async {
    final db = await database;
    return db.rawQuery('''
      SELECT * FROM (
        SELECT
          cage.*,
          (
            SELECT COUNT(*)
            FROM birds bird
            WHERE bird.cageId = cage.id
              AND COALESCE(bird.active, 1) = 1
          ) AS birdCount,
          (
            SELECT COUNT(*)
            FROM pairs pair
            INNER JOIN birds male ON male.id = pair.maleBirdId
            INNER JOIN birds female ON female.id = pair.femaleBirdId
            WHERE pair.endedAt IS NULL
              AND male.cageId = cage.id
              AND female.cageId = cage.id
              AND COALESCE(male.active, 1) = 1
              AND COALESCE(female.active, 1) = 1
          ) AS pairCount,
          (
            SELECT COUNT(*)
            FROM eggs egg
            INNER JOIN clutches clutch
              ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
            INNER JOIN pairs pair ON pair.id = clutch.pairId
            INNER JOIN birds male ON male.id = pair.maleBirdId
            WHERE clutch.status = 'Active'
              AND male.cageId = cage.id
              AND egg.status IN ('Incubating', 'Fertile')
          ) AS activeEggCount,
          (
            SELECT COUNT(*)
            FROM eggs egg
            INNER JOIN clutches clutch
              ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
            INNER JOIN pairs pair ON pair.id = clutch.pairId
            INNER JOIN birds male ON male.id = pair.maleBirdId
            WHERE clutch.status = 'Active'
              AND male.cageId = cage.id
              AND egg.status IN ('Incubating', 'Fertile')
          ) AS unresolvedEggCount,
          (
            SELECT COUNT(*)
            FROM birds chick
            INNER JOIN clutches clutch ON clutch.id = chick.nestClutchId
            INNER JOIN pairs pair ON pair.id = clutch.pairId
            INNER JOIN birds male ON male.id = pair.maleBirdId
            WHERE male.cageId = cage.id
              AND chick.leftNestDate IS NULL
              AND COALESCE(chick.active, 1) = 1
          ) AS chicksInNest,
          (
            SELECT MIN(egg.expectedHatchDate)
            FROM eggs egg
            INNER JOIN clutches clutch
              ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
            INNER JOIN pairs pair ON pair.id = clutch.pairId
            INNER JOIN birds male ON male.id = pair.maleBirdId
            WHERE clutch.status = 'Active'
              AND male.cageId = cage.id
              AND egg.status IN ('Incubating', 'Fertile')
          ) AS nextExpectedHatchDate,
          (SELECT COUNT(*) FROM cages merged
            WHERE merged.mergedIntoId = cage.id
              AND COALESCE(merged.active, 1) = 1) AS mergedCount
        FROM cages cage
        WHERE COALESCE(cage.active, 1) = 1
          AND cage.mergedIntoId IS NULL
      ) summary
      WHERE birdCount > 0
      ORDER BY
        CASE WHEN identityMode = 'series' THEN 0 ELSE 1 END,
        seriesOrder ASC,
        identifier COLLATE NOCASE ASC
    ''');
  }

  Future<int> getCurrentBirdCount() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM birds WHERE COALESCE(active, 1) = 1
    ''')) ?? 0;
  }

  Future<void> assignBirdToCage(
    String birdId,
    String cageId,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final cage = await txn.query(
        'cages',
        columns: ['identifier', 'active', 'mergedIntoId'],
        where: 'id = ?',
        whereArgs: [cageId],
        limit: 1,
      );
      if (cage.isEmpty || cage.first['active'] == 0 ||
          cage.first['mergedIntoId'] != null) {
        throw StateError('Select an active, visible cage.');
      }
      final previous = await txn.query(
        'birds',
        columns: ['cageId', 'nestClutchId', 'leftNestDate'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      if (previous.isNotEmpty &&
          previous.first['nestClutchId'] != null &&
          previous.first['leftNestDate'] == null) {
        throw StateError(
          'Move this youngster from its clutch so a permanent ring can be assigned.',
        );
      }
      final previousCageId =
          previous.isEmpty ? null : previous.first['cageId']?.toString();
      await txn.update(
        'birds',
        {'cageId': cageId},
        where: 'id = ?',
        whereArgs: [birdId],
      );
      if (previousCageId != null &&
          previousCageId.isNotEmpty &&
          previousCageId != cageId) {
        await _addBirdEventTxn(
          txn,
          birdId: birdId,
          eventType: 'Cage Changed',
          eventDate: DateTime.now(),
          details: 'Changed cage',
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getBirdsInCage(
    String cageId,
  ) async {
    final db = await database;
    return db.query(
      'birds',
      where: 'cageId = ? AND COALESCE(active, 1) = 1',
      whereArgs: [cageId],
      orderBy: 'LENGTH(ringNumber), ringNumber COLLATE NOCASE ASC',
    );
  }

  Future<void> setCageMergeLinks(
    String cageId,
    Set<String> linkedCageIds,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final currentRows = await txn.query(
        'cages',
        columns: ['id', 'identityMode', 'physicalCageId'],
        where: 'id = ?',
        whereArgs: [cageId],
        limit: 1,
      );
      if (currentRows.isEmpty) throw StateError('Cage could not be found.');
      final current = currentRows.first;
      if (current['identityMode'] != 'series') {
        throw StateError('Only numbered cage portions can be grouped.');
      }
      final physicalCageId = current['physicalCageId']?.toString();
      if (physicalCageId == null || physicalCageId.isEmpty) {
        throw StateError('This cage portion has no parent cage.');
      }

      final desiredMembers = <String>{cageId};
      for (final otherId in linkedCageIds) {
        if (otherId == cageId) continue;
        final otherRows = await txn.query(
          'cages',
          columns: ['id', 'identityMode', 'physicalCageId', 'active'],
          where: 'id = ?',
          whereArgs: [otherId],
          limit: 1,
        );
        if (otherRows.isEmpty ||
            otherRows.first['active'] == 0 ||
            otherRows.first['identityMode'] != 'series' ||
            otherRows.first['physicalCageId']?.toString() != physicalCageId) {
          throw StateError(
            'Merge groups can contain only portions of the same whole cage.',
          );
        }
        desiredMembers.add(otherId);
      }

      // A saved selection defines one complete group. Remove every existing
      // edge touching a selected member first, so moving a portion out of an
      // older group cannot leave an indirect link behind. Unselected members
      // of that older group keep their own mutual links.
      final selectedIds = desiredMembers.toList();
      final placeholders = List.filled(selectedIds.length, '?').join(',');
      await txn.delete(
        'cage_merge_links',
        where: 'cageAId IN ($placeholders) OR cageBId IN ($placeholders)',
        whereArgs: [...selectedIds, ...selectedIds],
      );

      // Store a complete graph for the group. This makes group membership
      // stable regardless of which member is edited later.
      final now = DateTime.now().toIso8601String();
      for (var left = 0; left < selectedIds.length; left++) {
        for (var right = left + 1; right < selectedIds.length; right++) {
          final ids = [selectedIds[left], selectedIds[right]]..sort();
          await txn.insert(
            'cage_merge_links',
            {'cageAId': ids[0], 'cageBId': ids[1], 'createdAt': now},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
  }

  Future<Set<String>> getCageMergeLinkIds(String cageId) async {
    final db = await database;
    final currentRows = await db.query(
      'cages',
      columns: ['physicalCageId'],
      where: 'id = ?',
      whereArgs: [cageId],
      limit: 1,
    );
    if (currentRows.isEmpty) return <String>{};
    final physicalCageId = currentRows.first['physicalCageId']?.toString();
    if (physicalCageId == null || physicalCageId.isEmpty) return <String>{};

    final components = await _getMergeAssignmentComponents(
      db,
      physicalCageId,
    );
    for (final component in components) {
      if (component.contains(cageId)) {
        return component.where((id) => id != cageId).toSet();
      }
    }
    return <String>{};
  }

  Future<List<Set<String>>> _getMergeAssignmentComponents(
    DatabaseExecutor executor,
    String physicalCageId, {
    bool visibleOnly = false,
  }) async {
    final cages = await executor.query(
      'cages',
      columns: ['id'],
      where: "physicalCageId = ? AND identityMode = 'series' "
          'AND COALESCE(active, 1) = 1 '
          '${visibleOnly ? 'AND mergedIntoId IS NULL' : ''}',
      whereArgs: [physicalCageId],
    );
    final ids = cages.map((row) => row['id'].toString()).toSet();
    if (ids.isEmpty) return const <Set<String>>[];

    final links = await executor.rawQuery('''
      SELECT link.cageAId, link.cageBId
      FROM cage_merge_links link
      INNER JOIN cages a ON a.id = link.cageAId
      INNER JOIN cages b ON b.id = link.cageBId
      WHERE a.physicalCageId = ?
        AND b.physicalCageId = ?
        AND COALESCE(a.active, 1) = 1
        AND COALESCE(b.active, 1) = 1
    ''', [physicalCageId, physicalCageId]);

    final graph = <String, Set<String>>{
      for (final id in ids) id: <String>{},
    };
    for (final link in links) {
      final a = link['cageAId'].toString();
      final b = link['cageBId'].toString();
      if (!ids.contains(a) || !ids.contains(b)) continue;
      graph[a]!.add(b);
      graph[b]!.add(a);
    }

    final visited = <String>{};
    final components = <Set<String>>[];
    for (final id in ids) {
      if (!visited.add(id)) continue;
      final component = <String>{};
      final queue = <String>[id];
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        component.add(current);
        for (final neighbour in graph[current] ?? const <String>{}) {
          if (visited.add(neighbour)) queue.add(neighbour);
        }
      }
      components.add(component);
    }
    return components;
  }

  Future<List<Map<String, dynamic>>> getAssignedMergeableCages(
    String cageId,
  ) async {
    final db = await database;
    final currentRows = await db.query(
      'cages',
      columns: ['physicalCageId'],
      where: 'id = ?',
      whereArgs: [cageId],
      limit: 1,
    );
    if (currentRows.isEmpty) return const [];
    final physicalCageId = currentRows.first['physicalCageId']?.toString();
    if (physicalCageId == null) return const [];
    final components = await _getMergeAssignmentComponents(
      db,
      physicalCageId,
    );
    Set<String>? component;
    for (final item in components) {
      if (item.contains(cageId)) {
        component = item;
        break;
      }
    }
    if (component == null || component.length <= 1) return const [];
    final ids = component.where((id) => id != cageId).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.query(
      'cages',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'seriesOrder ASC, createdAt ASC, id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getMergeSelectionGroups(
    String cageId,
  ) async {
    final db = await database;
    final currentRows = await db.query(
      'cages',
      where: 'id = ?',
      whereArgs: [cageId],
      limit: 1,
    );
    if (currentRows.isEmpty) return const [];
    final current = currentRows.first;
    if (current['identityMode'] != 'series' || current['mergedIntoId'] != null) {
      return const [];
    }
    final physicalCageId = current['physicalCageId']?.toString();
    if (physicalCageId == null || physicalCageId.isEmpty) return const [];

    final visibleRows = await db.query(
      'cages',
      where: "physicalCageId = ? AND identityMode = 'series' "
          'AND COALESCE(active, 1) = 1 AND mergedIntoId IS NULL',
      whereArgs: [physicalCageId],
      orderBy: 'seriesOrder ASC, createdAt ASC, id ASC',
    );
    if (visibleRows.length <= 1) return const [];
    final byId = <String, Map<String, dynamic>>{
      for (final row in visibleRows) row['id'].toString(): row,
    };
    final components = await _getMergeAssignmentComponents(
      db,
      physicalCageId,
      visibleOnly: true,
    );
    final currentComponent = components.firstWhere(
      (component) => component.contains(cageId),
      orElse: () => <String>{cageId},
    );

    final result = <Map<String, dynamic>>[];
    Future<void> addGroup(Set<String> memberSet, {required bool expanded}) async {
      final sorted = memberSet.where(byId.containsKey).toList()
        ..sort((a, b) {
          final left = (byId[a]!['seriesOrder'] as num?)?.toInt() ?? 0;
          final right = (byId[b]!['seriesOrder'] as num?)?.toInt() ?? 0;
          return left.compareTo(right);
        });
      final groups = expanded
          ? sorted.map((id) => <String>[id]).toList()
          : <List<String>>[sorted];
      for (final ids in groups) {
        if (ids.isEmpty) continue;
        final placeholders = List.filled(ids.length, '?').join(',');
        final birdCount = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM birds '
              'WHERE cageId IN ($placeholders) AND COALESCE(active, 1) = 1',
              ids,
            )) ??
            0;
        final pairCount = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*)
          FROM pairs pair
          INNER JOIN birds male ON male.id = pair.maleBirdId
          INNER JOIN birds female ON female.id = pair.femaleBirdId
          WHERE pair.endedAt IS NULL
            AND male.cageId IN ($placeholders)
            AND female.cageId IN ($placeholders)
        ''', [...ids, ...ids])) ??
            0;
        final labels = ids.map((id) => byId[id]!['identifier'].toString()).toList();
        result.add({
          'label': labels.join('+'),
          'memberIds': ids,
          'birdCount': birdCount,
          'pairCount': pairCount,
          'isCurrent': ids.length == 1 && ids.first == cageId,
          'isGroup': ids.length > 1,
          'sortOrder': ids
              .map((id) => (byId[id]!['seriesOrder'] as num?)?.toInt() ?? 0)
              .reduce((a, b) => a < b ? a : b),
        });
      }
    }

    await addGroup(currentComponent, expanded: true);
    for (final component in components) {
      if (identical(component, currentComponent) ||
          component.contains(cageId)) {
        continue;
      }
      await addGroup(component, expanded: false);
    }
    result.sort(
      (a, b) => (a['sortOrder'] as int).compareTo(b['sortOrder'] as int),
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> getMergeCandidates(String cageId) {
    return getMergeSelectionGroups(cageId);
  }

  Future<List<Map<String, dynamic>>> getMergedCagesForTarget(
    String cageId,
  ) async {
    final db = await database;
    return db.query(
      'cages',
      where: 'mergedIntoId = ? AND COALESCE(active, 1) = 1',
      whereArgs: [cageId],
      orderBy: 'seriesOrder ASC, identifier COLLATE NOCASE ASC',
    );
  }

  Future<void> mergeCage({
    required String sourceCageId,
    required String targetCageId,
  }) {
    return mergeCageGroup(
      sourceCageIds: <String>[sourceCageId],
      targetCageId: targetCageId,
    );
  }

  Future<void> mergeCageGroup({
    required List<String> sourceCageIds,
    required String targetCageId,
  }) async {
    final initialSources = sourceCageIds.toSet()..remove(targetCageId);
    if (initialSources.isEmpty) {
      throw StateError('Select at least one other cage portion.');
    }

    final db = await database;
    await db.transaction((txn) async {
      final targetRows = await txn.query(
        'cages',
        where: 'id = ?',
        whereArgs: [targetCageId],
        limit: 1,
      );
      if (targetRows.isEmpty) throw StateError('Target cage could not be found.');
      final target = targetRows.first;
      if (target['active'] == 0 ||
          target['mergedIntoId'] != null ||
          target['identityMode'] != 'series') {
        throw StateError('Select an active numbered cage portion to keep.');
      }
      final physicalCageId = target['physicalCageId']?.toString();
      if (physicalCageId == null || physicalCageId.isEmpty) {
        throw StateError('The target portion has no parent cage.');
      }

      final allSourceIds = <String>{...initialSources};
      var changed = true;
      while (changed) {
        changed = false;
        final parents = allSourceIds.toList();
        if (parents.isEmpty) break;
        final placeholders = List.filled(parents.length, '?').join(',');
        final children = await txn.query(
          'cages',
          columns: ['id'],
          where: 'mergedIntoId IN ($placeholders)',
          whereArgs: parents,
        );
        for (final child in children) {
          if (allSourceIds.add(child['id'].toString())) changed = true;
        }
      }

      final sourceList = allSourceIds.toList();
      final placeholders = List.filled(sourceList.length, '?').join(',');
      final sourceRows = await txn.query(
        'cages',
        where: 'id IN ($placeholders)',
        whereArgs: sourceList,
      );
      if (sourceRows.length != sourceList.length) {
        throw StateError('One or more selected cage portions could not be found.');
      }
      for (final source in sourceRows) {
        if (source['active'] == 0 ||
            source['identityMode'] != 'series' ||
            source['physicalCageId']?.toString() != physicalCageId) {
          throw StateError(
            'Only portions from the same whole cage can be merged.',
          );
        }
      }

      final birdCount = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM birds '
            'WHERE cageId IN ($placeholders) AND COALESCE(active, 1) = 1',
            sourceList,
          )) ??
          0;
      final pairCount = Sqflite.firstIntValue(await txn.rawQuery('''
        SELECT COUNT(*)
        FROM pairs pair
        INNER JOIN birds male ON male.id = pair.maleBirdId
        INNER JOIN birds female ON female.id = pair.femaleBirdId
        WHERE pair.endedAt IS NULL
          AND male.cageId IN ($placeholders)
          AND female.cageId IN ($placeholders)
      ''', [...sourceList, ...sourceList])) ??
          0;
      final sourceLabels = sourceRows
          .map((row) => row['identifier']?.toString() ?? 'Cage')
          .toList();
      final targetLabel = target['identifier']?.toString() ?? 'Cage';
      final now = DateTime.now().toIso8601String();

      await txn.update(
        'birds',
        {'cageId': targetCageId},
        where: 'cageId IN ($placeholders)',
        whereArgs: sourceList,
      );
      await txn.update(
        'cages',
        {'mergedIntoId': targetCageId, 'updatedAt': now},
        where: 'id IN ($placeholders)',
        whereArgs: sourceList,
      );
      await txn.rawUpdate('''
        UPDATE pair_sessions
        SET cageId = ?
        WHERE endedAt IS NULL
          AND pairId IN (
            SELECT pair.id
            FROM pairs pair
            INNER JOIN birds male ON male.id = pair.maleBirdId
            INNER JOIN birds female ON female.id = pair.femaleBirdId
            WHERE pair.endedAt IS NULL
              AND male.cageId = ?
              AND female.cageId = ?
          )
      ''', [targetCageId, targetCageId, targetCageId]);

      await _renumberActiveSeriesTxn(txn);
      final refreshedTarget = await txn.query(
        'cages',
        columns: ['identifier'],
        where: 'id = ?',
        whereArgs: [targetCageId],
        limit: 1,
      );
      await _addActivityEventTxn(
        txn,
        category: 'Cages',
        eventType: 'Cages Merged',
        eventDate: DateTime.now(),
        title: refreshedTarget.isEmpty
            ? targetLabel
            : refreshedTarget.first['identifier'].toString(),
        details: '${sourceLabels.join(', ')} merged into $targetLabel · '
            '$birdCount bird${birdCount == 1 ? '' : 's'} · '
            '$pairCount pair${pairCount == 1 ? '' : 's'}',
        entityType: 'Cage',
        entityId: targetCageId,
      );
    });
  }

  Future<void> unmergeCage(String sourceCageId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT source.*, target.identifier AS targetIdentifier
        FROM cages source
        LEFT JOIN cages target ON target.id = source.mergedIntoId
        WHERE source.id = ?
        LIMIT 1
      ''', [sourceCageId]);
      if (rows.isEmpty || rows.first['mergedIntoId'] == null) {
        throw StateError('This cage is not currently merged.');
      }
      final targetId = rows.first['mergedIntoId'].toString();
      final targetLabel = rows.first['targetIdentifier']?.toString() ?? 'Cage';
      await txn.update(
        'cages',
        {
          'mergedIntoId': null,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sourceCageId],
      );
      await _renumberActiveSeriesTxn(txn);
      final restored = await txn.query(
        'cages',
        columns: ['identifier'],
        where: 'id = ?',
        whereArgs: [sourceCageId],
        limit: 1,
      );
      await _addActivityEventTxn(
        txn,
        category: 'Cages',
        eventType: 'Cages Unmerged',
        eventDate: DateTime.now(),
        title: targetLabel,
        details: '${restored.first['identifier']} restored from $targetLabel',
        entityType: 'Cage',
        entityId: targetId,
      );
    });
  }

  Future<void> sellCage({
    required String cageId,
    required DateTime soldAt,
    required double price,
    String? buyer,
    String? notes,
    required String financeId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final cages = await txn.query(
        'cages',
        where: 'id = ?',
        whereArgs: [cageId],
        limit: 1,
      );
      if (cages.isEmpty) throw StateError('Cage could not be found.');
      final birdCount = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM birds WHERE cageId = ? AND COALESCE(active, 1) = 1',
        [cageId],
      )) ?? 0;
      if (birdCount > 0) {
        throw StateError('Move all birds before selling this cage.');
      }
      final mergedCount = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM cages WHERE mergedIntoId = ? AND COALESCE(active, 1) = 1',
        [cageId],
      )) ?? 0;
      if (mergedCount > 0 || cages.first['mergedIntoId'] != null) {
        throw StateError('Unmerge this cage before selling it.');
      }
      final label = cages.first['identifier'].toString();
      await txn.update(
        'cages',
        {
          'active': 0,
          'soldAt': soldAt.toIso8601String(),
          'soldPrice': price,
          'soldBuyer': buyer?.trim(),
          'soldNotes': notes?.trim(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [cageId],
      );
      await txn.insert('finance_transactions', {
        'id': financeId,
        'type': 'Income',
        'category': 'Cage Sale',
        'amount': price,
        'date': soldAt.toIso8601String(),
        'notes': [
          'Sold $label',
          if ((buyer?.trim() ?? '').isNotEmpty) 'Buyer: ${buyer!.trim()}',
          if ((notes?.trim() ?? '').isNotEmpty) notes!.trim(),
        ].join(' · '),
        'birdId': null,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await _renumberActiveSeriesTxn(txn);
      await _addActivityEventTxn(
        txn,
        category: 'Cages',
        eventType: 'Cage Sold',
        eventDate: soldAt,
        title: label,
        details: [
          if ((buyer?.trim() ?? '').isNotEmpty) 'Buyer: ${buyer!.trim()}',
          'Price: $price',
          if ((notes?.trim() ?? '').isNotEmpty) notes!.trim(),
        ].join(' · '),
        entityType: 'Cage',
        entityId: cageId,
        amount: price,
        financeType: 'Income',
      );
      await _addActivityEventTxn(
        txn,
        category: 'Finance',
        eventType: 'Income',
        eventDate: soldAt,
        title: 'Cage Sale',
        details: 'Sold $label',
        entityType: 'Finance',
        entityId: financeId,
        amount: price,
        financeType: 'Income',
        sourceKey: 'finance_$financeId',
      );
    });
  }

  Future<List<String>> _physicalCageIds(
    DatabaseExecutor executor,
    String cageId,
  ) async {
    final rows = await executor.query(
      'cages',
      columns: ['id', 'physicalCageId'],
      where: 'id = ?',
      whereArgs: [cageId],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    final physicalId = rows.first['physicalCageId']?.toString();
    if (physicalId == null || physicalId.isEmpty) return [cageId];
    final portions = await executor.query(
      'cages',
      columns: ['id'],
      where: 'physicalCageId = ?',
      whereArgs: [physicalId],
    );
    return portions.map((row) => row['id'].toString()).toList();
  }

  Future<Map<String, int>> getCageDeleteImpact(String cageId) async {
    final db = await database;
    final ids = await _physicalCageIds(db, cageId);
    if (ids.isEmpty) {
      return const {'birds': 0, 'mergeLinks': 0, 'mergedCages': 0, 'portions': 0};
    }
    final placeholders = List.filled(ids.length, '?').join(',');
    final birds = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM birds WHERE COALESCE(active, 1) = 1 '
          'AND cageId IN ($placeholders)',
          ids,
        )) ??
        0;
    final mergeLinks = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM cage_merge_links '
          'WHERE cageAId IN ($placeholders) OR cageBId IN ($placeholders)',
          [...ids, ...ids],
        )) ??
        0;
    final mergedCages = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM cages WHERE mergedIntoId IN ($placeholders)',
          ids,
        )) ??
        0;
    return {
      'birds': birds,
      'mergeLinks': mergeLinks,
      'mergedCages': mergedCages,
      'portions': ids.length,
    };
  }

  Future<void> deleteCageCompletely(String cageId) async {
    final db = await database;
    await db.transaction((txn) async {
      final ids = await _physicalCageIds(txn, cageId);
      if (ids.isEmpty) return;
      final placeholders = List.filled(ids.length, '?').join(',');

      // Old removed records must never keep a stale current position.
      await txn.rawUpdate(
        'UPDATE birds SET cageId = NULL WHERE COALESCE(active, 1) = 0 '
        'AND cageId IN ($placeholders)',
        ids,
      );
      final occupied = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM birds WHERE COALESCE(active, 1) = 1 '
            'AND cageId IN ($placeholders)',
            ids,
          )) ??
          0;
      if (occupied > 0) {
        throw StateError(
          'Move all current birds out of this physical cage before deleting it.',
        );
      }

      await txn.rawUpdate(
        'UPDATE pair_sessions SET cageId = NULL WHERE cageId IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM cage_merge_links WHERE cageAId IN ($placeholders) '
        'OR cageBId IN ($placeholders)',
        [...ids, ...ids],
      );
      await txn.rawUpdate(
        'UPDATE cages SET mergedIntoId = NULL WHERE mergedIntoId IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        "DELETE FROM activity_events WHERE entityType = 'Cage' "
        'AND entityId IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM cages WHERE id IN ($placeholders)',
        ids,
      );
      await _renumberActiveSeriesTxn(txn);
    });
  }

  // ---------------------------------------------------------------------------
  // Pairs
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getAvailableBirdsForPair(
      String cageId,
      ) async {
    final db = await database;

    return db.rawQuery(
      '''
      SELECT b.*
      FROM birds b
      WHERE b.cageId = ?
        AND COALESCE(b.active, 1) = 1
        AND NOT EXISTS(
          SELECT 1
          FROM pairs p
          WHERE p.endedAt IS NULL
            AND (
              p.maleBirdId = b.id
              OR p.femaleBirdId = b.id
            )
        )
      ORDER BY b.ringNumber ASC
      ''',
      [cageId],
    );
  }

  Future<void> createPair({
    required String id,
    required String maleBirdId,
    required String femaleBirdId,
    String? identifier,
    String? notes,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      if (maleBirdId == femaleBirdId) {
        throw StateError('A bird cannot be paired with itself.');
      }

      final selectedBirds = await txn.query(
        'birds',
        columns: ['id', 'gender', 'speciesId', 'cageId', 'active'],
        where: 'id IN (?, ?)',
        whereArgs: [maleBirdId, femaleBirdId],
      );

      if (selectedBirds.length != 2) {
        throw StateError('One or both selected birds could not be found.');
      }

      final maleBird = selectedBirds.firstWhere(
        (bird) => bird['id'] == maleBirdId,
      );
      final femaleBird = selectedBirds.firstWhere(
        (bird) => bird['id'] == femaleBirdId,
      );

      if (maleBird['gender'] != 'Male' || femaleBird['gender'] != 'Female') {
        throw StateError('Select one Male bird and one Female bird.');
      }
      if (maleBird['speciesId'] == null ||
          maleBird['speciesId'] != femaleBird['speciesId']) {
        throw StateError('Both birds must be the same species.');
      }
      if (maleBird['cageId'] == null ||
          maleBird['cageId'] != femaleBird['cageId']) {
        throw StateError('Both birds must be in the same cage.');
      }
      if (maleBird['active'] == 0 || femaleBird['active'] == 0) {
        throw StateError('Removed birds cannot be paired.');
      }

      final existingActivePair = await txn.rawQuery('''
        SELECT id
        FROM pairs
        WHERE endedAt IS NULL
          AND (
            maleBirdId IN (?, ?)
            OR femaleBirdId IN (?, ?)
          )
        LIMIT 1
      ''', [maleBirdId, femaleBirdId, maleBirdId, femaleBirdId]);
      if (existingActivePair.isNotEmpty) {
        throw StateError('One of these birds already belongs to a pair.');
      }

      final historicalPair = await txn.query(
        'pairs',
        where: 'maleBirdId = ? AND femaleBirdId = ?',
        whereArgs: [maleBirdId, femaleBirdId],
        orderBy: 'createdAt ASC',
        limit: 1,
      );

      final pairedAt = DateTime.now();
      final cageId = maleBird['cageId']?.toString();
      late final String pairId;
      late final String finalIdentifier;
      late final bool reactivated;

      if (historicalPair.isNotEmpty) {
        pairId = historicalPair.first['id'].toString();
        finalIdentifier = historicalPair.first['identifier']?.toString() ?? 'Pair';
        reactivated = true;
        await txn.update(
          'pairs',
          {
            'endedAt': null,
            'endReason': null,
            'notes': (notes?.trim().isNotEmpty ?? false)
                ? notes!.trim()
                : historicalPair.first['notes'],
            'breedingStatus': 'Inactive',
          },
          where: 'id = ?',
          whereArgs: [pairId],
        );
      } else {
        pairId = id;
        reactivated = false;
        var generatedIdentifier = identifier?.trim() ?? '';
        if (generatedIdentifier.isEmpty) {
          final result = await txn.rawQuery('''
            SELECT MAX(CAST(SUBSTR(identifier, 3) AS INTEGER)) AS maxNumber
            FROM pairs
            WHERE identifier LIKE 'P-%'
          ''');
          final maxNumber = (result.first['maxNumber'] as num?)?.toInt() ?? 0;
          generatedIdentifier =
              'P-${(maxNumber + 1).toString().padLeft(3, '0')}';
        }
        finalIdentifier = generatedIdentifier;
        await txn.insert('pairs', {
          'id': pairId,
          'identifier': finalIdentifier,
          'maleBirdId': maleBirdId,
          'femaleBirdId': femaleBirdId,
          'createdAt': pairedAt.toIso8601String(),
          'endedAt': null,
          'endReason': null,
          'notes': notes?.trim(),
          'breedingStatus': 'Inactive',
        });
      }

      await txn.insert('pair_sessions', {
        'syncId': const Uuid().v4(),
        'pairId': pairId,
        'startedAt': pairedAt.toIso8601String(),
        'endedAt': null,
        'endReason': null,
        'cageId': cageId,
      });

      await txn.update(
        'birds',
        {
          'saleStatus': 'Not for Sale',
          'reservedBuyer': null,
          'reservedPrice': null,
          'reservedAt': null,
        },
        where: 'id IN (?, ?)',
        whereArgs: [maleBirdId, femaleBirdId],
      );

      final eventType = reactivated ? 'Re-paired' : 'Paired';
      final details = reactivated
          ? 'Reactivated previous pair $finalIdentifier'
          : 'Created pair $finalIdentifier';
      await _addBirdEventTxn(
        txn,
        birdId: maleBirdId,
        eventType: eventType,
        eventDate: pairedAt,
        details: details,
      );
      await _addBirdEventTxn(
        txn,
        birdId: femaleBirdId,
        eventType: eventType,
        eventDate: pairedAt,
        details: details,
      );
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: reactivated ? 'Pair Re-activated' : 'Pair Created',
        eventDate: pairedAt,
        title: finalIdentifier,
        details: reactivated
            ? 'The same two birds were paired again. Previous history remains attached.'
            : notes?.trim(),
        entityType: 'Pair',
        entityId: pairId,
      );
    });
  }

  Future<List<Map<String, dynamic>>> getPairsForCage(
      String cageId,
      ) async {
    final db = await database;

    return db.rawQuery(
      '''
      SELECT
        p.id,
        p.identifier,
        p.maleBirdId,
        p.femaleBirdId,
        p.createdAt,
        p.endedAt,
        p.endReason,

        male.ringNumber AS maleRingNumber,
        male.name AS maleName,
        male.gender AS maleGender,
        male.cageId AS maleCageId,
        male.active AS maleActive,
        species.name AS speciesName,

        female.ringNumber AS femaleRingNumber,
        female.name AS femaleName,
        female.gender AS femaleGender,
        female.cageId AS femaleCageId,
        female.active AS femaleActive,

        CASE
          WHEN COALESCE(male.active, 1) = 0
            OR COALESCE(female.active, 1) = 0
            THEN 'Unpaired'

          WHEN male.cageId IS NOT NULL
            AND male.cageId = female.cageId
            THEN 'Active'

          ELSE 'Separated'
        END AS pairStatus

      FROM pairs p

      INNER JOIN birds male
        ON male.id = p.maleBirdId

      INNER JOIN birds female
        ON female.id = p.femaleBirdId

      LEFT JOIN species species
        ON species.id = male.speciesId

      WHERE p.endedAt IS NULL
        AND (
          male.cageId = ?
          OR female.cageId = ?
        )

      ORDER BY p.createdAt DESC
      ''',
      [
        cageId,
        cageId,
      ],
    );
  }


  Future<List<Map<String, dynamic>>> getActivePairsForSelection() async {
    final db = await database;

    return db.rawQuery('''
      SELECT
        p.id,
        p.identifier,
        c.id AS cageId,
        c.identifier AS cageIdentifier,
        male.ringNumber AS maleRingNumber,
        male.name AS maleName,
        male.gender AS maleGender,
        female.ringNumber AS femaleRingNumber,
        female.name AS femaleName,
        female.gender AS femaleGender,
        species.name AS speciesName
      FROM pairs p
      INNER JOIN birds male ON male.id = p.maleBirdId
      INNER JOIN birds female ON female.id = p.femaleBirdId
      LEFT JOIN cages c ON c.id = male.cageId
      LEFT JOIN species species ON species.id = male.speciesId
      WHERE p.endedAt IS NULL
        AND COALESCE(male.active, 1) = 1
        AND COALESCE(female.active, 1) = 1
        AND male.cageId IS NOT NULL
        AND male.cageId = female.cageId
      ORDER BY c.identifier ASC, p.createdAt ASC
    ''');
  }

  Future<void> endPair({
    required String pairId,
    required String reason,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'pairs',
        columns: ['identifier'],
        where: 'id = ?',
        whereArgs: [pairId],
        limit: 1,
      );
      final now = DateTime.now();
      await txn.update(
        'pairs',
        {
          'endedAt': now.toIso8601String(),
          'endReason': reason,
          'breedingStatus': 'Inactive',
        },
        where: 'id = ? AND endedAt IS NULL',
        whereArgs: [pairId],
      );
      await txn.update(
        'pair_sessions',
        {
          'endedAt': now.toIso8601String(),
          'endReason': reason,
          'cageId': null,
        },
        where: 'pairId = ? AND endedAt IS NULL',
        whereArgs: [pairId],
      );
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Pair Ended',
        eventDate: now,
        title: rows.isEmpty ? 'Pair' : rows.first['identifier'].toString(),
        details: reason,
        entityType: 'Pair',
        entityId: pairId,
      );
    });
  }

  Future<Map<String, dynamic>?> getActivePairMoveInfo(String birdId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        pair.id AS pairId,
        pair.identifier AS pairIdentifier,
        pair.maleBirdId,
        pair.femaleBirdId,
        male.cageId AS cageId,
        cage.identifier AS cageIdentifier,
        CASE WHEN pair.maleBirdId = ? THEN female.id ELSE male.id END
          AS partnerBirdId,
        CASE WHEN pair.maleBirdId = ? THEN female.ringNumber ELSE male.ringNumber END
          AS partnerRingNumber,
        CASE WHEN pair.maleBirdId = ? THEN female.name ELSE male.name END
          AS partnerName,
        CASE WHEN pair.maleBirdId = ? THEN female.gender ELSE male.gender END
          AS partnerGender,
        (
          SELECT COUNT(*) FROM clutches clutch
          WHERE clutch.pairId = pair.id AND clutch.status = 'Active'
        ) AS activeClutchCount,
        (
          SELECT COUNT(*)
          FROM birds chick
          INNER JOIN clutches clutch ON clutch.id = chick.nestClutchId
          WHERE clutch.pairId = pair.id
            AND chick.leftNestDate IS NULL
            AND COALESCE(chick.active, 1) = 1
        ) AS chicksInNest
      FROM pairs pair
      INNER JOIN birds male ON male.id = pair.maleBirdId
      INNER JOIN birds female ON female.id = pair.femaleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      WHERE pair.endedAt IS NULL
        AND (pair.maleBirdId = ? OR pair.femaleBirdId = ?)
      LIMIT 1
    ''', [birdId, birdId, birdId, birdId, birdId, birdId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> moveWholePairToCage({
    required String pairId,
    required String cageId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final pairRows = await txn.query(
        'pairs',
        columns: ['identifier', 'maleBirdId', 'femaleBirdId'],
        where: 'id = ? AND endedAt IS NULL',
        whereArgs: [pairId],
        limit: 1,
      );
      if (pairRows.isEmpty) throw StateError('Active pair could not be found.');
      final cageRows = await txn.query(
        'cages',
        columns: ['identifier', 'active', 'mergedIntoId'],
        where: 'id = ?',
        whereArgs: [cageId],
        limit: 1,
      );
      if (cageRows.isEmpty || cageRows.first['active'] == 0 ||
          cageRows.first['mergedIntoId'] != null) {
        throw StateError('Select an active, visible cage.');
      }
      final pair = pairRows.first;
      final memberIds = [
        pair['maleBirdId'].toString(),
        pair['femaleBirdId'].toString(),
      ];
      final previousCages = <String, String?>{};
      for (final id in memberIds) {
        final rows = await txn.query(
          'birds',
          columns: ['cageId'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        previousCages[id] =
            rows.isEmpty ? null : rows.first['cageId']?.toString();
      }
      await txn.update(
        'birds',
        {'cageId': cageId},
        where: 'id IN (?, ?)',
        whereArgs: [pair['maleBirdId'], pair['femaleBirdId']],
      );
      for (final id in memberIds) {
        final previousCage = previousCages[id];
        if (previousCage != null &&
            previousCage.isNotEmpty &&
            previousCage != cageId) {
          await _addBirdEventTxn(
            txn,
            birdId: id,
            eventType: 'Cage Changed',
            eventDate: DateTime.now(),
            details: 'Changed cage',
          );
        }
      }
      await txn.update(
        'pair_sessions',
        {'cageId': cageId},
        where: 'pairId = ? AND endedAt IS NULL',
        whereArgs: [pairId],
      );
    });
  }

  Future<void> unpairAndMoveBird({
    required String pairId,
    required String birdId,
    required String cageId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final pairRows = await txn.query(
        'pairs',
        columns: ['identifier'],
        where: 'id = ? AND endedAt IS NULL',
        whereArgs: [pairId],
        limit: 1,
      );
      if (pairRows.isEmpty) throw StateError('Active pair could not be found.');
      final cageRows = await txn.query(
        'cages',
        columns: ['identifier', 'active', 'mergedIntoId'],
        where: 'id = ?',
        whereArgs: [cageId],
        limit: 1,
      );
      if (cageRows.isEmpty || cageRows.first['active'] == 0 ||
          cageRows.first['mergedIntoId'] != null) {
        throw StateError('Select an active, visible cage.');
      }
      final previousBird = await txn.query(
        'birds',
        columns: ['cageId'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      final previousCageId = previousBird.isEmpty
          ? null
          : previousBird.first['cageId']?.toString();
      final now = DateTime.now();
      const reason = 'Unpaired because one bird was moved';
      await txn.update(
        'pairs',
        {
          'endedAt': now.toIso8601String(),
          'endReason': reason,
          'breedingStatus': 'Inactive',
        },
        where: 'id = ?',
        whereArgs: [pairId],
      );
      await txn.update(
        'pair_sessions',
        {
          'endedAt': now.toIso8601String(),
          'endReason': reason,
          'cageId': null,
        },
        where: 'pairId = ? AND endedAt IS NULL',
        whereArgs: [pairId],
      );
      await txn.update(
        'birds',
        {'cageId': cageId},
        where: 'id = ?',
        whereArgs: [birdId],
      );
      if (previousCageId != null &&
          previousCageId.isNotEmpty &&
          previousCageId != cageId) {
        await _addBirdEventTxn(
          txn,
          birdId: birdId,
          eventType: 'Cage Changed',
          eventDate: now,
          details: 'Changed cage',
        );
      }
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Pair Ended',
        eventDate: now,
        title: pairRows.first['identifier']?.toString() ?? 'Pair',
        details: reason,
        entityType: 'Pair',
        entityId: pairId,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Breeding
  // ---------------------------------------------------------------------------

  Future<Map<String, int>> getBreedingSummary() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM pairs WHERE endedAt IS NULL) AS allPairs,
        (SELECT COUNT(*) FROM pairs
          WHERE endedAt IS NULL AND breedingStatus = 'Active') AS activePairs,
        (
          SELECT COUNT(*)
          FROM eggs e
          INNER JOIN clutches c
            ON c.id = COALESCE(e.currentClutchId, e.clutchId)
          WHERE c.status = 'Active'
            AND e.status IN ('Incubating', 'Fertile')
        ) AS totalEggs,
        (
          SELECT COUNT(*)
          FROM birds b
          WHERE COALESCE(b.active, 1) = 1
            AND b.nestClutchId IS NOT NULL
            AND b.leftNestDate IS NULL
        ) AS chicksInNest,
        (
          SELECT COUNT(*)
          FROM birds b
          WHERE COALESCE(b.active, 1) = 1
            AND LOWER(COALESCE(b.source, '')) = 'bred'
            AND b.hatchDate IS NOT NULL
            AND date(b.hatchDate) >= date('now', '-3 months')
        ) AS recentYoungsters,
        (
          SELECT COUNT(*)
          FROM birds b
          WHERE COALESCE(b.active, 1) = 1
            AND b.saleStatus = 'Reserved'
        ) AS reservedForSale
    ''');

    final row = result.first;
    return {
      'allPairs': (row['allPairs'] as num?)?.toInt() ?? 0,
      'activePairs': (row['activePairs'] as num?)?.toInt() ?? 0,
      'totalEggs': (row['totalEggs'] as num?)?.toInt() ?? 0,
      'chicksInNest': (row['chicksInNest'] as num?)?.toInt() ?? 0,
      'recentYoungsters': (row['recentYoungsters'] as num?)?.toInt() ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> getBreedingPairs({
    bool activeOnly = false,
  }) async {
    final db = await database;

    return db.rawQuery('''
      SELECT
        p.id,
        p.identifier,
        p.createdAt,
        p.endedAt,
        p.endReason,
        p.notes,
        p.breedingStatus,
        male.id AS maleBirdId,
        male.ringNumber AS maleRingNumber,
        male.name AS maleName,
        male.gender AS maleGender,
        female.id AS femaleBirdId,
        female.ringNumber AS femaleRingNumber,
        female.name AS femaleName,
        female.gender AS femaleGender,
        cage.id AS cageId,
        cage.identifier AS cageIdentifier,
        species.name AS speciesName,
        COUNT(DISTINCT CASE
          WHEN clutch.status = 'Active' THEN clutch.id
        END) AS activeClutchCount,
        (
          SELECT COALESCE(SUM(activeClutch.expectedEggs), 0)
          FROM clutches activeClutch
          WHERE activeClutch.pairId = p.id
            AND activeClutch.status = 'Active'
        ) AS expectedEggCount,
        COUNT(DISTINCT CASE
          WHEN clutch.status = 'Active'
            AND egg.status IN ('Incubating', 'Fertile') THEN egg.id
        END) AS activeEggCount,
        COUNT(DISTINCT CASE
          WHEN clutch.status = 'Active'
            AND chick.leftNestDate IS NULL
            AND COALESCE(chick.active, 1) = 1 THEN chick.id
        END) AS chicksInNest,
        COUNT(DISTINCT CASE
          WHEN clutch.status = 'Active'
            AND egg.status IN ('Incubating', 'Fertile') THEN egg.id
        END) AS unresolvedEggCount,
        COUNT(DISTINCT CASE
          WHEN clutch.status = 'Active'
            AND egg.status = 'Hatched' THEN egg.id
        END) AS hatchedEggCount,
        MIN(CASE
          WHEN clutch.status = 'Active'
            AND egg.status IN ('Incubating', 'Fertile')
          THEN egg.expectedHatchDate
        END) AS nextExpectedHatchDate
      FROM pairs p
      INNER JOIN birds male ON male.id = p.maleBirdId
      INNER JOIN birds female ON female.id = p.femaleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      LEFT JOIN species species ON species.id = male.speciesId
      LEFT JOIN clutches clutch ON clutch.pairId = p.id
      LEFT JOIN eggs egg
        ON COALESCE(egg.currentClutchId, egg.clutchId) = clutch.id
      LEFT JOIN birds chick ON chick.nestClutchId = clutch.id
      WHERE p.endedAt IS NULL
        ${activeOnly ? "AND p.breedingStatus = 'Active'" : ""}
      GROUP BY p.id
      ORDER BY
        CASE WHEN p.endedAt IS NULL THEN 0 ELSE 1 END,
        CASE WHEN COUNT(DISTINCT CASE WHEN clutch.status = 'Active' THEN clutch.id END) = 0
          THEN 1 ELSE 0 END,
        cage.identifier COLLATE NOCASE ASC,
        p.identifier COLLATE NOCASE ASC
    ''');
  }

  Future<Map<String, dynamic>?> getBreedingPairById(String pairId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        p.*,
        male.ringNumber AS maleRingNumber,
        male.name AS maleName,
        male.mutation AS maleMutation,
        male.gender AS maleGender,
        female.ringNumber AS femaleRingNumber,
        female.name AS femaleName,
        female.mutation AS femaleMutation,
        female.gender AS femaleGender,
        cage.id AS cageId,
        cage.identifier AS cageIdentifier,
        species.id AS speciesId,
        species.name AS speciesName,
        species.incubationDays,
        species.clutchWindowDays
      FROM pairs p
      INNER JOIN birds male ON male.id = p.maleBirdId
      INNER JOIN birds female ON female.id = p.femaleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      LEFT JOIN species species ON species.id = male.speciesId
      WHERE p.id = ?
      LIMIT 1
    ''', [pairId]);

    return result.isEmpty ? null : result.first;
  }

  Future<List<Map<String, dynamic>>> getClutchesForPair(
    String pairId,
  ) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        clutch.*,
        COUNT(DISTINCT originalEgg.id) AS totalEggs,
        COUNT(DISTINCT CASE
          WHEN currentEgg.status IN ('Incubating', 'Fertile')
            THEN currentEgg.id
        END) AS activeEggs,
        COUNT(DISTINCT CASE
          WHEN originalEgg.status = 'Hatched' THEN originalEgg.id
        END) AS hatchedEggs,
        COUNT(DISTINCT CASE
          WHEN chick.leftNestDate IS NULL
            AND COALESCE(chick.active, 1) = 1 THEN chick.id
        END) AS chicksInNest,
        COUNT(DISTINCT CASE
          WHEN currentEgg.clutchId != clutch.id THEN currentEgg.id
        END) AS fosteredEggs,
        MIN(CASE
          WHEN currentEgg.status IN ('Incubating', 'Fertile')
          THEN currentEgg.expectedHatchDate
        END) AS nextExpectedHatchDate
      FROM clutches clutch
      LEFT JOIN eggs originalEgg ON originalEgg.clutchId = clutch.id
      LEFT JOIN eggs currentEgg
        ON COALESCE(currentEgg.currentClutchId, currentEgg.clutchId) = clutch.id
      LEFT JOIN birds chick ON chick.nestClutchId = clutch.id
      WHERE clutch.pairId = ?
      GROUP BY clutch.id
      ORDER BY clutch.clutchNumber DESC, clutch.startedAt DESC
    ''', [pairId]);
  }

  Future<List<Map<String, dynamic>>> getActiveClutchesForPair(
    String pairId,
  ) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        clutch.*,
        COUNT(DISTINCT egg.id) AS activeEggs,
        COUNT(DISTINCT chick.id) AS chicksInNest
      FROM clutches clutch
      LEFT JOIN eggs egg
        ON COALESCE(egg.currentClutchId, egg.clutchId) = clutch.id
        AND egg.status IN ('Incubating', 'Fertile')
      LEFT JOIN birds chick
        ON chick.nestClutchId = clutch.id
        AND chick.leftNestDate IS NULL
        AND COALESCE(chick.active, 1) = 1
      WHERE clutch.pairId = ? AND clutch.status = 'Active'
      GROUP BY clutch.id
      ORDER BY clutch.clutchNumber DESC
    ''', [pairId]);
  }

  Future<Map<String, dynamic>?> getClutchById(String clutchId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        clutch.*,
        pair.identifier AS pairIdentifier,
        cage.id AS cageId,
        cage.identifier AS cageIdentifier,
        male.ringNumber AS maleRingNumber,
        male.name AS maleName,
        male.gender AS maleGender,
        female.ringNumber AS femaleRingNumber,
        female.name AS femaleName,
        female.gender AS femaleGender,
        species.id AS speciesId,
        species.name AS speciesName,
        COALESCE(clutch.incubationDaysOverride, species.incubationDays)
          AS incubationDays,
        species.clutchWindowDays
      FROM clutches clutch
      INNER JOIN pairs pair ON pair.id = clutch.pairId
      INNER JOIN birds male ON male.id = pair.maleBirdId
      INNER JOIN birds female ON female.id = pair.femaleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      LEFT JOIN species species ON species.id = male.speciesId
      WHERE clutch.id = ?
      LIMIT 1
    ''', [clutchId]);
    return result.isEmpty ? null : result.first;
  }

  Future<String> _createClutchTxn(
    Transaction txn, {
    required String pairId,
    required DateTime startedAt,
    String? notes,
  }) async {
    final numberResult = await txn.rawQuery(
      'SELECT MAX(clutchNumber) AS maxNumber FROM clutches WHERE pairId = ?',
      [pairId],
    );
    final nextNumber =
        ((numberResult.first['maxNumber'] as num?)?.toInt() ?? 0) + 1;
    final id = 'clutch_${DateTime.now().microsecondsSinceEpoch}_$nextNumber';

    await txn.insert('clutches', {
      'id': id,
      'pairId': pairId,
      'clutchNumber': nextNumber,
      'startedAt': startedAt.toIso8601String(),
      'firstEggDate': null,
      'endedAt': null,
      'status': 'Active',
      'expectedEggs': null,
      'incubationDaysOverride': null,
      'notes': notes?.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });

    final pairRows = await txn.query(
      'pairs',
      columns: ['identifier'],
      where: 'id = ?',
      whereArgs: [pairId],
      limit: 1,
    );
    final pairLabel = pairRows.isEmpty
        ? 'Pair'
        : pairRows.first['identifier']?.toString() ?? 'Pair';
    await _addActivityEventTxn(
      txn,
      category: 'Breeding',
      eventType: 'Clutch Created',
      eventDate: startedAt,
      title: '$pairLabel · Clutch $nextNumber',
      details: notes?.trim(),
      entityType: 'Clutch',
      entityId: id,
    );

    return id;
  }

  Future<String> createClutch({
    required String pairId,
    required DateTime startedAt,
    String? notes,
  }) async {
    final db = await database;
    return db.transaction(
      (txn) => _createClutchTxn(
        txn,
        pairId: pairId,
        startedAt: startedAt,
        notes: notes,
      ),
    );
  }

  Future<void> startClutch({
    required String id,
    required String pairId,
    required DateTime startedAt,
    String? notes,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final numberResult = await txn.rawQuery(
        'SELECT MAX(clutchNumber) AS maxNumber FROM clutches WHERE pairId = ?',
        [pairId],
      );
      final nextNumber =
          ((numberResult.first['maxNumber'] as num?)?.toInt() ?? 0) + 1;
      await txn.insert('clutches', {
        'id': id,
        'pairId': pairId,
        'clutchNumber': nextNumber,
        'startedAt': startedAt.toIso8601String(),
        'firstEggDate': null,
        'endedAt': null,
        'status': 'Active',
        'expectedEggs': null,
        'incubationDaysOverride': null,
        'notes': notes?.trim(),
        'createdAt': DateTime.now().toIso8601String(),
      });
      final pairRows = await txn.query(
        'pairs',
        columns: ['identifier'],
        where: 'id = ?',
        whereArgs: [pairId],
        limit: 1,
      );
      final pairLabel = pairRows.isEmpty
          ? 'Pair'
          : pairRows.first['identifier']?.toString() ?? 'Pair';
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Clutch Created',
        eventDate: startedAt,
        title: '$pairLabel · Clutch $nextNumber',
        details: notes?.trim(),
        entityType: 'Clutch',
        entityId: id,
      );
    });
  }

  Future<String> addEggAutomatically({
    required String eggId,
    required String pairId,
    required DateTime laidDate,
    String? selectedClutchId,
    bool createNewClutch = false,
    String? notes,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      String clutchId = selectedClutchId?.trim() ?? '';

      if (createNewClutch) {
        clutchId = await _createClutchTxn(
          txn,
          pairId: pairId,
          startedAt: laidDate,
        );
      } else if (clutchId.isEmpty) {
        final ruleResult = await txn.rawQuery('''
          SELECT COALESCE(species.clutchWindowDays, 15) AS clutchWindowDays
          FROM pairs pair
          INNER JOIN birds male ON male.id = pair.maleBirdId
          LEFT JOIN species species ON species.id = male.speciesId
          WHERE pair.id = ?
          LIMIT 1
        ''', [pairId]);
        final windowDays =
            (ruleResult.isEmpty
                ? null
                : ruleResult.first['clutchWindowDays'] as num?)
            ?.toInt() ??
        15;
        final earliest = laidDate.subtract(Duration(days: windowDays));
        final active = await txn.query(
          'clutches',
          columns: ['id'],
          where: '''
            pairId = ? AND status = 'Active'
            AND firstEggDate IS NOT NULL
            AND date(firstEggDate) BETWEEN date(?) AND date(?)
          ''',
          whereArgs: [
            pairId,
            earliest.toIso8601String(),
            laidDate.toIso8601String(),
          ],
          orderBy: 'firstEggDate DESC',
          limit: 1,
        );
        if (active.isNotEmpty) {
          clutchId = active.first['id'].toString();
        } else {
          clutchId = await _createClutchTxn(
            txn,
            pairId: pairId,
            startedAt: laidDate,
          );
        }
      }

      final clutchResult = await txn.rawQuery('''
        SELECT
          clutch.firstEggDate,
          COALESCE(clutch.incubationDaysOverride, species.incubationDays)
            AS incubationDays
        FROM clutches clutch
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        INNER JOIN birds male ON male.id = pair.maleBirdId
        LEFT JOIN species species ON species.id = male.speciesId
        WHERE clutch.id = ? AND clutch.status = 'Active'
        LIMIT 1
      ''', [clutchId]);

      if (clutchResult.isEmpty) {
        throw StateError('Active clutch could not be found.');
      }

      final numberResult = await txn.rawQuery(
        'SELECT MAX(eggNumber) AS maxNumber FROM eggs WHERE clutchId = ?',
        [clutchId],
      );
      final maxNumber =
          (numberResult.first['maxNumber'] as num?)?.toInt() ?? 0;
      final incubationDays =
          (clutchResult.first['incubationDays'] as num?)?.toInt();
      final expectedHatchDate = incubationDays == null
          ? null
          : laidDate.add(Duration(days: incubationDays));

      await txn.insert('eggs', {
        'id': eggId,
        'clutchId': clutchId,
        'currentClutchId': null,
        'eggNumber': maxNumber + 1,
        'laidDate': laidDate.toIso8601String(),
        'expectedHatchDate': expectedHatchDate?.toIso8601String(),
        'status': 'Incubating',
        'hatchedBirdId': null,
        'notes': notes?.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
        'fosteredAt': null,
        'fosterNotes': null,
      });

      await _renumberEggsForClutchTxn(txn, clutchId);
      await txn.update(
        'pairs',
        {'breedingStatus': 'Active'},
        where: 'id = ?',
        whereArgs: [pairId],
      );
      final expectation = await txn.rawQuery(
        'SELECT expectedEggs FROM clutches WHERE id = ?',
        [clutchId],
      );
      final expectedEggs = expectation.isEmpty
          ? null
          : (expectation.first['expectedEggs'] as num?)?.toInt();
      if (expectedEggs != null) {
        final biologicalEggCount = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM eggs WHERE clutchId = ?',
              [clutchId],
            )) ??
            0;
        if (biologicalEggCount >= expectedEggs) {
          await txn.update(
            'clutches',
            {'expectedEggs': null},
            where: 'id = ?',
            whereArgs: [clutchId],
          );
        }
      }
      final earliestEgg = await txn.rawQuery(
        'SELECT MIN(laidDate) AS firstEggDate FROM eggs WHERE clutchId = ?',
        [clutchId],
      );
      final firstEggDate = earliestEgg.first['firstEggDate']?.toString();
      if (firstEggDate != null && firstEggDate.isNotEmpty) {
        await txn.update(
          'clutches',
          {
            'firstEggDate': firstEggDate,
            'startedAt': firstEggDate,
          },
          where: 'id = ?',
          whereArgs: [clutchId],
        );
      }

      final labels = await txn.rawQuery('''
        SELECT pair.identifier AS pairIdentifier, clutch.clutchNumber
        FROM clutches clutch
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        WHERE clutch.id = ?
        LIMIT 1
      ''', [clutchId]);
      final labelRow = labels.isEmpty ? null : labels.first;
      if (maxNumber == 0) {
        await _addActivityEventTxn(
          txn,
          category: 'Breeding',
          eventType: 'First Egg Laid',
          eventDate: laidDate,
          title: labelRow?['pairIdentifier']?.toString() ?? 'Pair',
          details: 'First egg of clutch',
          entityType: 'Clutch',
          entityId: clutchId,
          sourceKey: 'history_first_egg_$clutchId',
        );
      }

      return clutchId;
    });
  }

  Future<void> setExpectedEggs({
    required String clutchId,
    int? expectedEggs,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      var target = expectedEggs;
      if (target != null && target <= 0) {
        target = null;
      }
      if (target != null) {
        final actual = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM eggs WHERE clutchId = ?',
              [clutchId],
            )) ??
            0;
        if (target <= actual) target = null;
      }
      await txn.update(
        'clutches',
        {'expectedEggs': target},
        where: 'id = ? AND status = ?',
        whereArgs: [clutchId, 'Active'],
      );
    });
  }

  Future<void> makePairActive(String pairId) async {
    final db = await database;
    await db.update(
      'pairs',
      {'breedingStatus': 'Active'},
      where: 'id = ? AND endedAt IS NULL',
      whereArgs: [pairId],
    );
  }

  Future<void> _renumberEggsForClutchTxn(
    DatabaseExecutor executor,
    String clutchId,
  ) async {
    final eggs = await executor.query(
      'eggs',
      columns: ['id'],
      where: 'clutchId = ?',
      whereArgs: [clutchId],
      orderBy: 'date(laidDate) ASC, laidDate ASC, id ASC',
    );
    if (eggs.isEmpty) return;

    await executor.rawUpdate(
      'UPDATE eggs SET eggNumber = eggNumber + 100000 WHERE clutchId = ?',
      [clutchId],
    );
    for (var index = 0; index < eggs.length; index++) {
      await executor.update(
        'eggs',
        {'eggNumber': index + 1},
        where: 'id = ?',
        whereArgs: [eggs[index]['id']],
      );
    }
  }

  Future<void> addEgg({
    required String id,
    required String clutchId,
    required DateTime laidDate,
    String? notes,
  }) async {
    final clutch = await getClutchById(clutchId);
    if (clutch == null) {
      throw StateError('Active clutch could not be found.');
    }
    await addEggAutomatically(
      eggId: id,
      pairId: clutch['pairId'].toString(),
      laidDate: laidDate,
      selectedClutchId: clutchId,
      notes: notes,
    );
  }

  Future<List<Map<String, dynamic>>> getEggsForClutch(
    String clutchId,
  ) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        egg.*,
        originalClutch.clutchNumber AS originalClutchNumber,
        originalPair.id AS biologicalPairId,
        originalPair.identifier AS biologicalPairIdentifier,
        currentClutch.clutchNumber AS currentClutchNumber,
        currentPair.id AS currentPairId,
        currentPair.identifier AS currentPairIdentifier,
        currentCage.identifier AS currentCageIdentifier,
        chick.ringNumber AS chickRingNumber,
        chick.name AS chickName,
        CASE WHEN egg.currentClutchId IS NOT NULL THEN 1 ELSE 0 END AS isFostered
      FROM eggs egg
      INNER JOIN clutches originalClutch ON originalClutch.id = egg.clutchId
      INNER JOIN pairs originalPair ON originalPair.id = originalClutch.pairId
      LEFT JOIN clutches currentClutch
        ON currentClutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
      LEFT JOIN pairs currentPair ON currentPair.id = currentClutch.pairId
      LEFT JOIN birds currentMale ON currentMale.id = currentPair.maleBirdId
      LEFT JOIN cages currentCage ON currentCage.id = currentMale.cageId
      LEFT JOIN birds chick ON chick.id = egg.hatchedBirdId
      WHERE egg.clutchId = ?
         OR COALESCE(egg.currentClutchId, egg.clutchId) = ?
      ORDER BY egg.laidDate ASC, egg.eggNumber ASC
    ''', [clutchId, clutchId]);
  }

  Future<List<Map<String, dynamic>>> getChicksForClutch(
    String clutchId,
  ) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        bird.*,
        species.name AS speciesName,
        cage.identifier AS cageIdentifier,
        parentPair.identifier AS biologicalPairIdentifier,
        currentClutch.clutchNumber AS currentClutchNumber,
        currentPair.identifier AS currentPairIdentifier
      FROM birds bird
      LEFT JOIN species species ON species.id = bird.speciesId
      LEFT JOIN cages cage ON cage.id = bird.cageId
      LEFT JOIN pairs parentPair ON parentPair.id = bird.parentPairId
      LEFT JOIN clutches currentClutch ON currentClutch.id = bird.nestClutchId
      LEFT JOIN pairs currentPair ON currentPair.id = currentClutch.pairId
      WHERE bird.nestClutchId = ?
      ORDER BY bird.hatchDate ASC, bird.ringNumber ASC
    ''', [clutchId]);
  }

  Future<void> updateEggStatus({
    required String eggId,
    required String status,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'eggs',
        columns: ['clutchId', 'currentClutchId'],
        where: 'id = ?',
        whereArgs: [eggId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final now = DateTime.now();
      await txn.update(
        'eggs',
        {
          'status': status,
          'updatedAt': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [eggId],
      );
      final labels = await txn.rawQuery('''
        SELECT egg.eggNumber, clutch.clutchNumber,
          pair.identifier AS pairIdentifier
        FROM eggs egg
        INNER JOIN clutches clutch ON clutch.id = egg.clutchId
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        WHERE egg.id = ?
        LIMIT 1
      ''', [eggId]);
      final label = labels.isEmpty ? null : labels.first;
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Egg $status',
        eventDate: now,
        title: "${label?['pairIdentifier'] ?? 'Pair'} · "
            "Clutch ${label?['clutchNumber'] ?? '?'} · "
            "Egg ${label?['eggNumber'] ?? '?'}",
        entityType: 'Egg',
        entityId: eggId,
      );
      await _evaluateClutchClosure(txn, rows.first['clutchId'].toString());
      final current = rows.first['currentClutchId']?.toString();
      if (current != null && current.isNotEmpty) {
        await _evaluateClutchClosure(txn, current);
      }
    });
  }

  Future<void> hatchEgg({
    required String eggId,
    required String birdId,
    required String ringNumber,
    required DateTime hatchDate,
    String? name,
    String? eyeColor,
    String? downColor,
    String? notes,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final results = await txn.rawQuery('''
        SELECT
          egg.clutchId,
          COALESCE(egg.currentClutchId, egg.clutchId) AS currentClutchId,
          originalClutch.pairId AS biologicalPairId,
          currentClutch.pairId AS currentPairId,
          male.speciesId,
          male.cageId
        FROM eggs egg
        INNER JOIN clutches originalClutch ON originalClutch.id = egg.clutchId
        INNER JOIN clutches currentClutch
          ON currentClutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
        INNER JOIN pairs currentPair ON currentPair.id = currentClutch.pairId
        INNER JOIN birds male ON male.id = currentPair.maleBirdId
        WHERE egg.id = ? AND egg.hatchedBirdId IS NULL
        LIMIT 1
      ''', [eggId]);
      if (results.isEmpty) {
        throw StateError('This egg is already hatched or could not be found.');
      }
      final row = results.first;
      await txn.insert('birds', {
        'id': birdId,
        'ringNumber': ringNumber.trim(),
        'name': name?.trim(),
        'gender': 'Unknown',
        'mutation': null,
        'eyeColor': eyeColor?.trim().isEmpty == true ? null : eyeColor?.trim(),
        'downColor': downColor?.trim().isEmpty == true ? null : downColor?.trim(),
        'hatchDate': hatchDate.toIso8601String(),
        'speciesId': row['speciesId'],
        'ageGroup': 'Chick',
        'source': 'Bred',
        'sourceDate': hatchDate.toIso8601String(),
        'sourcePerson': null,
        'sourcePlace': null,
        'sourceDetails': null,
        'parentPairId': row['biologicalPairId'],
        'purchasePrice': null,
        'notes': notes?.trim(),
        'active': 1,
        'cageId': row['cageId'],
        'nestClutchId': row['currentClutchId'],
        'leftNestDate': null,
        'saleStatus': 'Available',
      });
      await txn.update(
        'eggs',
        {
          'status': 'Hatched',
          'hatchedBirdId': birdId,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [eggId],
      );
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: 'Hatched',
        eventDate: hatchDate,
        details: 'Hatched from egg in clutch ${row['clutchId']}',
      );
      final pairRows = await txn.query(
        'pairs',
        columns: ['identifier'],
        where: 'id = ?',
        whereArgs: [row['biologicalPairId']],
        limit: 1,
      );
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Chick Hatched',
        eventDate: hatchDate,
        title: pairRows.isEmpty
            ? 'Pair'
            : pairRows.first['identifier']?.toString() ?? 'Pair',
        entityType: 'Pair',
        entityId: row['biologicalPairId']?.toString(),
        birdId: birdId,
        sourceKey: 'history_hatched_$birdId',
      );
      await _evaluateClutchClosure(txn, row['clutchId'].toString());
      if (row['currentClutchId'].toString() != row['clutchId'].toString()) {
        await _evaluateClutchClosure(
          txn,
          row['currentClutchId'].toString(),
        );
      }
    });
  }

  Future<String> ensureActiveClutchForPair(String pairId) async {
    final db = await database;
    return db.transaction((txn) async {
      final active = await txn.query(
        'clutches',
        columns: ['id'],
        where: "pairId = ? AND status = 'Active'",
        whereArgs: [pairId],
        orderBy: 'clutchNumber DESC',
        limit: 1,
      );
      if (active.isNotEmpty) return active.first['id'].toString();
      return _createClutchTxn(
        txn,
        pairId: pairId,
        startedAt: DateTime.now(),
        notes: 'Created automatically for fostering',
      );
    });
  }

  Future<void> fosterEgg({
    required String eggId,
    required String targetClutchId,
    String? notes,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'eggs',
        columns: ['clutchId', 'currentClutchId', 'status'],
        where: 'id = ?',
        whereArgs: [eggId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Egg could not be found.');
      if (rows.first['status'] == 'Hatched') {
        throw StateError('A hatched egg cannot be fostered. Foster the chick.');
      }
      final oldCurrent =
          rows.first['currentClutchId']?.toString() ??
              rows.first['clutchId'].toString();
      final original = rows.first['clutchId'].toString();
      final now = DateTime.now();
      await txn.update(
        'eggs',
        {
          'currentClutchId': targetClutchId == original ? null : targetClutchId,
          'fosteredAt': now.toIso8601String(),
          'fosterNotes': notes?.trim(),
          'updatedAt': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [eggId],
      );
      final targetRows = await txn.rawQuery('''
        SELECT pair.identifier AS pairIdentifier, clutch.clutchNumber
        FROM clutches clutch
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        WHERE clutch.id = ?
        LIMIT 1
      ''', [targetClutchId]);
      final target = targetRows.isEmpty ? null : targetRows.first;
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Egg Fostered',
        eventDate: now,
        title: "Egg moved to ${target?['pairIdentifier'] ?? 'Pair'} · "
            "Clutch ${target?['clutchNumber'] ?? '?'}",
        details: notes?.trim(),
        entityType: 'Egg',
        entityId: eggId,
      );
      await _evaluateClutchClosure(txn, original);
      if (oldCurrent != original) {
        await _evaluateClutchClosure(txn, oldCurrent);
      }
    });
  }

  Future<void> fosterChick({
    required String birdId,
    required String targetClutchId,
    String? notes,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final birdRows = await txn.query(
        'birds',
        columns: ['nestClutchId'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      if (birdRows.isEmpty) throw StateError('Chick could not be found.');
      final target = await txn.rawQuery('''
        SELECT male.cageId
        FROM clutches clutch
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        INNER JOIN birds male ON male.id = pair.maleBirdId
        WHERE clutch.id = ? AND clutch.status = 'Active'
        LIMIT 1
      ''', [targetClutchId]);
      if (target.isEmpty) throw StateError('Target clutch is not active.');
      final oldClutch = birdRows.first['nestClutchId']?.toString();
      await txn.update(
        'birds',
        {
          'nestClutchId': targetClutchId,
          'cageId': target.first['cageId'],
          'leftNestDate': null,
          'fosteredAt': DateTime.now().toIso8601String(),
          'fosterNotes': notes?.trim(),
        },
        where: 'id = ?',
        whereArgs: [birdId],
      );
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: 'Fostered',
        eventDate: DateTime.now(),
        details: notes?.trim() ?? 'Moved to another foster clutch',
      );
      if (oldClutch != null && oldClutch.isNotEmpty) {
        await _evaluateClutchClosure(txn, oldClutch);
      }
    });
  }

  Future<void> moveChickFromNest({
    required String birdId,
    required String cageId,
    required String saleStatus,
    required String permanentRingNumber,
  }) async {
    if (!const {'Available', 'Reserved', 'Not for Sale'}.contains(saleStatus)) {
      throw StateError('Choose a valid sale status.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final cageRows = await txn.query(
        'cages',
        columns: ['identifier', 'active', 'mergedIntoId'],
        where: 'id = ?',
        whereArgs: [cageId],
        limit: 1,
      );
      if (cageRows.isEmpty ||
          cageRows.first['active'] == 0 ||
          cageRows.first['mergedIntoId'] != null) {
        throw StateError('Select an active, visible cage.');
      }
      final rows = await txn.query(
        'birds',
        columns: ['nestClutchId', 'speciesId', 'ringNumber'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final clutchId = rows.first['nestClutchId']?.toString();
      final speciesId = rows.first['speciesId']?.toString();
      final oldRing = rows.first['ringNumber']?.toString().trim() ?? '';
      final permanentRing = permanentRingNumber.trim();
      if (speciesId == null || speciesId.isEmpty || permanentRing.isEmpty) {
        throw StateError('Choose a permanent ring before moving this chick.');
      }
      final ringNumber = int.tryParse(permanentRing);
      if (ringNumber == null) {
        throw StateError('Permanent ring must come from Ring Management.');
      }
      final allowed = await txn.rawQuery('''
        SELECT id FROM ring_ranges
        WHERE speciesId = ? AND COALESCE(active, 1) = 1
          AND ? BETWEEN startNumber AND endNumber
        LIMIT 1
      ''', [speciesId, ringNumber]);
      if (allowed.isEmpty) {
        throw StateError('That ring is not allowed for this species.');
      }
      final duplicate = await txn.rawQuery('''
        SELECT id FROM birds
        WHERE id <> ?
          AND (
            LOWER(TRIM(COALESCE(ringNumber, ''))) = LOWER(?)
            OR (
              TRIM(COALESCE(ringNumber, '')) <> ''
              AND TRIM(ringNumber) NOT GLOB '*[^0-9]*'
              AND CAST(TRIM(ringNumber) AS INTEGER) = ?
            )
          )
        LIMIT 1
      ''', [birdId, permanentRing, ringNumber]);
      if (duplicate.isNotEmpty) {
        throw StateError('That ring is already allotted to another bird.');
      }
      final eggRows = await txn.query(
        'eggs',
        columns: ['clutchId', 'currentClutchId'],
        where: 'hatchedBirdId = ?',
        whereArgs: [birdId],
      );
      await txn.update(
        'birds',
        {
          'cageId': cageId,
          'ringNumber': permanentRing,
          'leftNestDate': DateTime.now().toIso8601String(),
          'saleStatus': saleStatus,
          'reservedBuyer': null,
          'reservedPrice': null,
          'reservedAt': null,
        },
        where: 'id = ?',
        whereArgs: [birdId],
      );
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: 'Left Nest',
        eventDate: DateTime.now(),
        details: [
          'Moved from nest to ${cageRows.first['identifier']}',
          'Permanent ring: $permanentRing',
          if (oldRing.isNotEmpty && oldRing != permanentRing)
            'Temporary chick ID: $oldRing',
        ].join(' · '),
      );
      final clutchIds = <String>{};
      if (clutchId != null && clutchId.isNotEmpty) clutchIds.add(clutchId);
      for (final egg in eggRows) {
        clutchIds.add(egg['clutchId'].toString());
        final current = egg['currentClutchId']?.toString();
        if (current != null && current.isNotEmpty) clutchIds.add(current);
      }
      for (final id in clutchIds) {
        await _evaluateClutchClosure(txn, id);
      }
    });
  }

  Future<void> markChickDied(String birdId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'birds',
        columns: ['nestClutchId'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final eggRows = await txn.query(
        'eggs',
        columns: ['clutchId', 'currentClutchId'],
        where: 'hatchedBirdId = ?',
        whereArgs: [birdId],
      );
      final now = DateTime.now();
      await txn.update(
        'birds',
        {
          'active': 0,
          'removedAt': now.toIso8601String(),
          'removalReason': 'Died',
          'cageId': null,
          'leftNestDate': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [birdId],
      );
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: 'Died',
        eventDate: now,
        details: 'Marked died while in nest',
      );
      final clutchIds = <String>{};
      final clutchId = rows.first['nestClutchId']?.toString();
      if (clutchId != null && clutchId.isNotEmpty) clutchIds.add(clutchId);
      for (final egg in eggRows) {
        clutchIds.add(egg['clutchId'].toString());
        final current = egg['currentClutchId']?.toString();
        if (current != null && current.isNotEmpty) clutchIds.add(current);
      }
      for (final id in clutchIds) {
        await _evaluateClutchClosure(txn, id);
      }
    });
  }

  Future<void> _evaluateClutchClosure(
    Transaction txn,
    String clutchId,
  ) async {
    final clutchRows = await txn.query(
      'clutches',
      columns: ['pairId', 'status'],
      where: 'id = ?',
      whereArgs: [clutchId],
      limit: 1,
    );
    if (clutchRows.isEmpty || clutchRows.first['status'] != 'Active') return;

    final unresolvedEggs = Sqflite.firstIntValue(await txn.rawQuery('''
      SELECT COUNT(*)
      FROM eggs egg
      WHERE (egg.clutchId = ? OR egg.currentClutchId = ?)
        AND egg.status IN ('Incubating', 'Fertile')
    ''', [clutchId, clutchId])) ?? 0;

    final chicksInNest = Sqflite.firstIntValue(await txn.rawQuery('''
      SELECT COUNT(DISTINCT bird.id)
      FROM birds bird
      LEFT JOIN eggs egg ON egg.hatchedBirdId = bird.id
      WHERE COALESCE(bird.active, 1) = 1
        AND bird.leftNestDate IS NULL
        AND (
          bird.nestClutchId = ?
          OR egg.clutchId = ?
          OR egg.currentClutchId = ?
        )
    ''', [clutchId, clutchId, clutchId])) ?? 0;

    final relatedEggs = Sqflite.firstIntValue(await txn.rawQuery('''
      SELECT COUNT(*)
      FROM eggs egg
      WHERE egg.clutchId = ? OR egg.currentClutchId = ?
    ''', [clutchId, clutchId])) ?? 0;

    final relatedChicks = Sqflite.firstIntValue(await txn.rawQuery('''
      SELECT COUNT(*)
      FROM birds bird
      WHERE bird.nestClutchId = ?
    ''', [clutchId])) ?? 0;

    if ((relatedEggs > 0 || relatedChicks > 0) &&
        unresolvedEggs == 0 &&
        chicksInNest == 0) {
      final completedAt = DateTime.now();
      await txn.update(
        'clutches',
        {
          'status': 'Completed',
          'endedAt': completedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [clutchId],
      );
      final labels = await txn.rawQuery('''
        SELECT pair.identifier AS pairIdentifier, clutch.clutchNumber
        FROM clutches clutch
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        WHERE clutch.id = ?
        LIMIT 1
      ''', [clutchId]);
      final label = labels.isEmpty ? null : labels.first;
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Clutch Completed',
        eventDate: completedAt,
        title: "${label?['pairIdentifier'] ?? 'Pair'} · "
            "Clutch ${label?['clutchNumber'] ?? '?'}",
        details: 'All eggs and chicks resolved',
        entityType: 'Clutch',
        entityId: clutchId,
      );
      await _recalculatePairStatus(
        txn,
        clutchRows.first['pairId'].toString(),
      );
    }
  }

  Future<void> _recalculatePairStatus(
    Transaction txn,
    String pairId,
  ) async {
    final active = Sqflite.firstIntValue(await txn.rawQuery('''
      SELECT COUNT(*) FROM clutches
      WHERE pairId = ? AND status = 'Active'
    ''', [pairId])) ?? 0;
    await txn.update(
      'pairs',
      {'breedingStatus': active > 0 ? 'Active' : 'Inactive'},
      where: 'id = ?',
      whereArgs: [pairId],
    );
  }

  Future<void> completeClutch(String clutchId) async {
    final db = await database;
    await db.transaction((txn) async {
      final clutch = await txn.query(
        'clutches',
        columns: ['pairId'],
        where: 'id = ?',
        whereArgs: [clutchId],
        limit: 1,
      );
      if (clutch.isEmpty) return;
      final completedAt = DateTime.now();
      await txn.update(
        'clutches',
        {
          'status': 'Completed',
          'endedAt': completedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [clutchId],
      );
      final labels = await txn.rawQuery('''
        SELECT pair.identifier AS pairIdentifier, clutch.clutchNumber
        FROM clutches clutch
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        WHERE clutch.id = ?
        LIMIT 1
      ''', [clutchId]);
      final label = labels.isEmpty ? null : labels.first;
      await _addActivityEventTxn(
        txn,
        category: 'Breeding',
        eventType: 'Clutch Completed',
        eventDate: completedAt,
        title: "${label?['pairIdentifier'] ?? 'Pair'} · "
            "Clutch ${label?['clutchNumber'] ?? '?'}",
        details: 'Completed manually',
        entityType: 'Clutch',
        entityId: clutchId,
      );
      await _recalculatePairStatus(txn, clutch.first['pairId'].toString());
    });
  }

  // ---------------------------------------------------------------------------
  // Bird lifecycle, sale and history
  // ---------------------------------------------------------------------------

  Future<void> _addActivityEventTxn(
    DatabaseExecutor executor, {
    required String category,
    required String eventType,
    required DateTime eventDate,
    required String title,
    String? details,
    String? entityType,
    String? entityId,
    String? birdId,
    double? amount,
    String? financeType,
    String? sourceKey,
  }) async {
    await executor.insert(
      'activity_events',
      {
        'syncId': const Uuid().v4(),
        'category': category,
        'eventType': eventType,
        'eventDate': eventDate.toIso8601String(),
        'title': title.trim().isEmpty ? eventType : title.trim(),
        'details': details?.trim(),
        'entityType': entityType,
        'entityId': entityId,
        'birdId': birdId,
        'amount': amount,
        'financeType': financeType,
        'sourceKey': sourceKey,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _addBirdEventTxn(
    DatabaseExecutor executor, {
    required String birdId,
    required String eventType,
    required DateTime eventDate,
    String? details,
    bool addActivity = true,
  }) async {
    await executor.insert('bird_events', {
      'syncId': const Uuid().v4(),
      'birdId': birdId,
      'eventType': eventType,
      'eventDate': eventDate.toIso8601String(),
      'details': details?.trim(),
    });

    final birdRows = await executor.rawQuery('''
      SELECT bird.ringNumber, bird.name, cage.identifier AS cageIdentifier
      FROM birds bird
      LEFT JOIN cages cage ON cage.id = bird.cageId
      WHERE bird.id = ?
      LIMIT 1
    ''', [birdId]);
    final row = birdRows.isEmpty ? null : birdRows.first;
    final ring = row?['ringNumber']?.toString() ?? 'Bird';
    final name = row?['name']?.toString().trim() ?? '';
    final cage = row?['cageIdentifier']?.toString().trim() ?? '';
    final extra = <String>[
      if (cage.isNotEmpty) 'Cage $cage',
      if (details?.trim().isNotEmpty == true) details!.trim(),
    ].join(' · ');

    if (addActivity) {
      await _addActivityEventTxn(
        executor,
        category: 'Birds',
        eventType: eventType,
        eventDate: eventDate,
        title: name.isEmpty ? ring : '$ring — $name',
        details: extra.isEmpty ? null : extra,
        entityType: 'Bird',
        entityId: birdId,
        birdId: birdId,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getBirdEvents(String birdId) async {
    final db = await database;
    return db.query(
      'bird_events',
      where: 'birdId = ?',
      whereArgs: [birdId],
      orderBy: 'eventDate DESC, id DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllBirdEvents({
    int limit = 300,
  }) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        event.*,
        bird.ringNumber,
        bird.name AS birdName,
        cage.identifier AS cageIdentifier
      FROM bird_events event
      INNER JOIN birds bird ON bird.id = event.birdId
      LEFT JOIN cages cage ON cage.id = bird.cageId
      ORDER BY event.eventDate DESC, event.id DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<void> updateBirdSaleStatus({
    required String birdId,
    required String status,
    String? buyer,
    double? price,
    DateTime? date,
    String? notes,
    bool releaseRing = false,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final birdRows = await txn.query(
        'birds',
        columns: ['nestClutchId', 'ringNumber'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      final eggRows = await txn.query(
        'eggs',
        columns: ['clutchId', 'currentClutchId'],
        where: 'hatchedBirdId = ?',
        whereArgs: [birdId],
      );
      final now = date ?? DateTime.now();
      final values = <String, dynamic>{'saleStatus': status};

      if (status == 'Reserved') {
        values.addAll({
          'reservedBuyer': buyer?.trim(),
          'reservedPrice': price,
          'reservedAt': now.toIso8601String(),
        });
      } else if (status == 'Sold') {
        if (price == null || price <= 0) {
          throw StateError('Sold price is required.');
        }
        values.addAll({
          'soldBuyer': buyer?.trim(),
          'soldPrice': price,
          'soldAt': now.toIso8601String(),
          'soldNotes': notes?.trim(),
          'active': 0,
          'removedAt': now.toIso8601String(),
          'removalReason': 'Sold',
          'cageId': null,
        });
        final saleTransactionId =
            'sale_${birdId}_${now.microsecondsSinceEpoch}';
        final saleNotes = notes?.trim().isNotEmpty == true
            ? notes!.trim()
            : 'Bird sold${buyer?.trim().isNotEmpty == true ? ' to ${buyer!.trim()}' : ''}';
        await txn.insert('finance_transactions', {
          'id': saleTransactionId,
          'type': 'Income',
          'category': 'Bird Sale',
          'amount': price,
          'date': now.toIso8601String(),
          'notes': saleNotes,
          'birdId': birdId,
          'createdAt': DateTime.now().toIso8601String(),
        });
        await _addActivityEventTxn(
          txn,
          category: 'Finance',
          eventType: 'Income',
          eventDate: now,
          title: 'Bird Sale',
          details: saleNotes,
          entityType: 'Finance',
          entityId: saleTransactionId,
          birdId: birdId,
          amount: price,
          financeType: 'Income',
          sourceKey: 'finance_$saleTransactionId',
        );
        final affectedPairs = await txn.query(
          'pairs',
          columns: ['id'],
          where: 'endedAt IS NULL AND (maleBirdId = ? OR femaleBirdId = ?)',
          whereArgs: [birdId, birdId],
        );
        await txn.update(
          'pairs',
          {
            'endedAt': now.toIso8601String(),
            'endReason': 'Bird sold',
            'breedingStatus': 'Inactive',
          },
          where: 'endedAt IS NULL AND (maleBirdId = ? OR femaleBirdId = ?)',
          whereArgs: [birdId, birdId],
        );
        for (final pairRow in affectedPairs) {
          await txn.update(
            'pair_sessions',
            {
              'endedAt': now.toIso8601String(),
              'endReason': 'Bird sold',
              'cageId': null,
            },
            where: 'pairId = ? AND endedAt IS NULL',
            whereArgs: [pairRow['id']],
          );
        }
      } else {
        values.addAll({
          'reservedBuyer': null,
          'reservedPrice': null,
          'reservedAt': null,
        });
      }

      await txn.update(
        'birds',
        values,
        where: 'id = ?',
        whereArgs: [birdId],
      );
      final eventDetails = <String>[
        if (buyer?.trim().isNotEmpty == true) 'Buyer: ${buyer!.trim()}',
        if (price != null) 'Price: $price',
        if (notes?.trim().isNotEmpty == true) notes!.trim(),
      ].join(' · ');
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: status,
        eventDate: now,
        details: eventDetails.isEmpty ? null : eventDetails,
      );
      if (status == 'Sold' && releaseRing) {
        final oldRing = birdRows.isEmpty
            ? ''
            : birdRows.first['ringNumber']?.toString().trim() ?? '';
        if (oldRing.isNotEmpty) {
          await txn.update(
            'birds',
            {'ringNumber': ''},
            where: 'id = ?',
            whereArgs: [birdId],
          );
          await _addBirdEventTxn(
            txn,
            birdId: birdId,
            eventType: 'Ring Removed',
            eventDate: now,
            details: 'Ring $oldRing removed during sale and released for reuse.',
          );
        }
      }
      if (status == 'Sold') {
        final clutchIds = <String>{};
        if (birdRows.isNotEmpty) {
          final nest = birdRows.first['nestClutchId']?.toString();
          if (nest != null && nest.isNotEmpty) clutchIds.add(nest);
        }
        for (final egg in eggRows) {
          clutchIds.add(egg['clutchId'].toString());
          final current = egg['currentClutchId']?.toString();
          if (current != null && current.isNotEmpty) clutchIds.add(current);
        }
        for (final id in clutchIds) {
          await _evaluateClutchClosure(txn, id);
        }
      }
    });
  }

  Future<void> markBirdRemoved({
    required String birdId,
    required String reason,
    String? notes,
    bool releaseRing = false,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now();
      final rows = await txn.query(
        'birds',
        columns: ['nestClutchId', 'ringNumber'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      final eggRows = await txn.query(
        'eggs',
        columns: ['clutchId', 'currentClutchId'],
        where: 'hatchedBirdId = ?',
        whereArgs: [birdId],
      );
      await txn.update(
        'birds',
        {
          'active': 0,
          'removedAt': now.toIso8601String(),
          'removalReason': reason,
          'cageId': null,
          'leftNestDate': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [birdId],
      );
      final affectedPairs = await txn.query(
        'pairs',
        columns: ['id'],
        where: 'endedAt IS NULL AND (maleBirdId = ? OR femaleBirdId = ?)',
        whereArgs: [birdId, birdId],
      );
      await txn.update(
        'pairs',
        {
          'endedAt': now.toIso8601String(),
          'endReason': reason,
          'breedingStatus': 'Inactive',
        },
        where: 'endedAt IS NULL AND (maleBirdId = ? OR femaleBirdId = ?)',
        whereArgs: [birdId, birdId],
      );
      for (final pairRow in affectedPairs) {
        await txn.update(
          'pair_sessions',
          {
            'endedAt': now.toIso8601String(),
            'endReason': reason,
            'cageId': null,
          },
          where: 'pairId = ? AND endedAt IS NULL',
          whereArgs: [pairRow['id']],
        );
      }
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: reason == 'Other' ? 'Removed' : reason,
        eventDate: now,
        details: [
          if (reason == 'Other') 'Removal reason: Other',
          if (notes?.trim().isNotEmpty == true) notes!.trim(),
        ].join(' · '),
      );
      if (releaseRing && rows.isNotEmpty) {
        final oldRing = rows.first['ringNumber']?.toString().trim() ?? '';
        if (oldRing.isNotEmpty) {
          await txn.update(
            'birds',
            {'ringNumber': ''},
            where: 'id = ?',
            whereArgs: [birdId],
          );
          await _addBirdEventTxn(
            txn,
            birdId: birdId,
            eventType: 'Ring Removed',
            eventDate: now,
            details: 'Removed ring $oldRing. The ring number is available for reuse.',
          );
        }
      }
      final clutchIds = <String>{};
      if (rows.isNotEmpty) {
        final clutchId = rows.first['nestClutchId']?.toString();
        if (clutchId != null && clutchId.isNotEmpty) clutchIds.add(clutchId);
      }
      for (final egg in eggRows) {
        clutchIds.add(egg['clutchId'].toString());
        final current = egg['currentClutchId']?.toString();
        if (current != null && current.isNotEmpty) clutchIds.add(current);
      }
      for (final id in clutchIds) {
        await _evaluateClutchClosure(txn, id);
      }
    });
  }

  Future<void> releaseBirdRing(String birdId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'birds',
        columns: ['ringNumber', 'active'],
        where: 'id = ?',
        whereArgs: [birdId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Bird could not be found.');
      if ((rows.first['active'] as num?)?.toInt() != 0) {
        throw StateError('Ring can only be removed from a sold or removed bird.');
      }
      final oldRing = rows.first['ringNumber']?.toString().trim() ?? '';
      if (oldRing.isEmpty) return;
      await txn.update(
        'birds',
        {'ringNumber': ''},
        where: 'id = ?',
        whereArgs: [birdId],
      );
      await _addBirdEventTxn(
        txn,
        birdId: birdId,
        eventType: 'Ring Removed',
        eventDate: DateTime.now(),
        details: 'Removed ring $oldRing. The ring number is available for reuse.',
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Finance
  // ---------------------------------------------------------------------------

  Future<void> addFinanceTransaction(Map<String, dynamic> values) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'finance_transactions',
        values,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      final type = values['type']?.toString() ?? 'Income';
      final category = values['category']?.toString() ?? type;
      final amount = (values['amount'] as num?)?.toDouble();
      final eventDate = DateTime.tryParse(values['date']?.toString() ?? '') ??
          DateTime.now();
      await _addActivityEventTxn(
        txn,
        category: 'Finance',
        eventType: type,
        eventDate: eventDate,
        title: category,
        details: values['notes']?.toString(),
        entityType: 'Finance',
        entityId: values['id']?.toString(),
        birdId: values['birdId']?.toString(),
        amount: amount,
        financeType: type,
        sourceKey: values['id'] == null ? null : 'finance_${values['id']}',
      );
    });
  }

  Future<List<Map<String, dynamic>>> getFinanceTransactions() async {
    final db = await database;
    return db.rawQuery('''
      SELECT transactionRow.*, bird.ringNumber, bird.name AS birdName,
        bird.gender AS birdGender
      FROM finance_transactions transactionRow
      LEFT JOIN birds bird ON bird.id = transactionRow.birdId
      ORDER BY transactionRow.date DESC, transactionRow.createdAt DESC
    ''');
  }

  Future<Map<String, double>> getFinanceSummary() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'Income' THEN amount ELSE 0 END), 0)
          AS income,
        COALESCE(SUM(CASE WHEN type = 'Expense' THEN amount ELSE 0 END), 0)
          AS expense
      FROM finance_transactions
    ''');
    final income = (result.first['income'] as num?)?.toDouble() ?? 0;
    final expense = (result.first['expense'] as num?)?.toDouble() ?? 0;
    return {
      'income': income,
      'expense': expense,
      'balance': income - expense,
    };
  }

  Future<Map<String, double>> getFinancePeriodSummary() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE
          WHEN type = 'Income'
            AND strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')
          THEN amount ELSE 0 END), 0) AS monthIncome,
        COALESCE(SUM(CASE
          WHEN type = 'Expense'
            AND strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')
          THEN amount ELSE 0 END), 0) AS monthExpense,
        COALESCE(SUM(CASE
          WHEN type = 'Income'
            AND strftime('%Y', date) = strftime('%Y', 'now', 'localtime')
          THEN amount ELSE 0 END), 0) AS yearIncome,
        COALESCE(SUM(CASE
          WHEN type = 'Expense'
            AND strftime('%Y', date) = strftime('%Y', 'now', 'localtime')
          THEN amount ELSE 0 END), 0) AS yearExpense
      FROM finance_transactions
    ''');
    final row = result.first;
    final monthIncome = (row['monthIncome'] as num?)?.toDouble() ?? 0;
    final monthExpense = (row['monthExpense'] as num?)?.toDouble() ?? 0;
    final yearIncome = (row['yearIncome'] as num?)?.toDouble() ?? 0;
    final yearExpense = (row['yearExpense'] as num?)?.toDouble() ?? 0;
    return {
      'monthIncome': monthIncome,
      'monthExpense': monthExpense,
      'monthBalance': monthIncome - monthExpense,
      'yearIncome': yearIncome,
      'yearExpense': yearExpense,
      'yearBalance': yearIncome - yearExpense,
    };
  }

  Future<Map<String, double>> getFeedAnalytics() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE
          WHEN category = 'Feed'
            AND strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')
          THEN COALESCE(quantity, 0) ELSE 0 END), 0) AS monthKg,
        COALESCE(SUM(CASE
          WHEN category = 'Feed'
            AND date >= date('now', 'localtime', '-90 day')
          THEN COALESCE(quantity, 0) ELSE 0 END), 0) AS ninetyDayKg,
        COALESCE(SUM(CASE
          WHEN category = 'Feed'
            AND strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')
          THEN amount ELSE 0 END), 0) AS monthCost,
        COALESCE(SUM(CASE
          WHEN category = 'Feed'
            AND date >= date('now', 'localtime', '-90 day')
          THEN amount ELSE 0 END), 0) AS ninetyDayCost
      FROM finance_transactions
      WHERE type = 'Expense'
    ''');
    final row = rows.first;
    double value(String key) => (row[key] as num?)?.toDouble() ?? 0;
    return {
      'monthKg': value('monthKg'),
      'rollingMonthlyKg': value('ninetyDayKg') / 3,
      'monthCost': value('monthCost'),
      'rollingMonthlyCost': value('ninetyDayCost') / 3,
    };
  }

  Future<List<Map<String, dynamic>>> getSaleLocations({
    bool activeOnly = true,
  }) async {
    final db = await database;
    return db.query(
      'sale_locations',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<String> upsertSaleLocation(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw StateError('Sale location is required.');
    final db = await database;
    final existing = await db.query(
      'sale_locations',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [clean],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id'].toString();
      await db.update(
        'sale_locations',
        {'active': 1, 'name': clean},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    final id = const Uuid().v4();
    await db.insert('sale_locations', {
      'id': id,
      'name': clean,
      'active': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> removeSaleLocation(String id) async {
    final db = await database;
    await db.update(
      'sale_locations',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String> createSaleOuting({
    required List<String> birdIds,
    required DateTime outingDate,
    required String locationName,
    String? notes,
  }) async {
    if (birdIds.isEmpty) throw StateError('Select at least one bird.');
    final locationId = await upsertSaleLocation(locationName);
    final db = await database;
    final outingId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final birdId in birdIds) {
        final rows = await txn.query(
          'birds',
          columns: ['active', 'saleStatus'],
          where: 'id = ?',
          whereArgs: [birdId],
          limit: 1,
        );
        if (rows.isEmpty || (rows.first['active'] as num?)?.toInt() == 0) {
          throw StateError('One selected bird is no longer active.');
        }
        final status = rows.first['saleStatus']?.toString() ?? 'Not for Sale';
        if (!const {'Available', 'Reserved'}.contains(status)) {
          throw StateError('Only birds currently For Sale can be taken out.');
        }
      }

      await txn.insert('sale_outings', {
        'id': outingId,
        'outingDate': outingDate.toIso8601String(),
        'locationId': locationId,
        'status': 'Open',
        'notes': notes?.trim(),
        'createdAt': now,
      });
      for (final birdId in birdIds) {
        await txn.insert('sale_outing_birds', {
          'id': const Uuid().v4(),
          'outingId': outingId,
          'birdId': birdId,
          'status': 'Taken',
          'soldPrice': null,
          'updatedAt': now,
        });
        await txn.update(
          'birds',
          {
            'saleStatus': 'Taken for Sale',
            'reservedBuyer': null,
            'reservedPrice': null,
            'reservedAt': null,
          },
          where: 'id = ?',
          whereArgs: [birdId],
        );
      }
    });
    return outingId;
  }

  Future<List<Map<String, dynamic>>> getSaleOutings({
    bool openOnly = false,
  }) async {
    final db = await database;
    return db.rawQuery('''
      SELECT outing.*, location.name AS locationName,
        COUNT(item.id) AS takenCount,
        SUM(CASE WHEN item.status = 'Sold' THEN 1 ELSE 0 END) AS soldCount,
        SUM(CASE WHEN item.status = 'Returned' THEN 1 ELSE 0 END) AS returnedCount,
        SUM(CASE WHEN item.status = 'Taken' THEN 1 ELSE 0 END) AS stillOutCount,
        COALESCE(SUM(CASE WHEN item.status = 'Sold' THEN item.soldPrice ELSE 0 END), 0)
          AS soldAmount
      FROM sale_outings outing
      LEFT JOIN sale_locations location ON location.id = outing.locationId
      LEFT JOIN sale_outing_birds item ON item.outingId = outing.id
      ${openOnly ? "WHERE outing.status = 'Open'" : ''}
      GROUP BY outing.id
      ORDER BY outing.outingDate DESC, outing.createdAt DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getSaleOutingBirds(
    String outingId, {
    String? status,
  }) async {
    final db = await database;
    final whereStatus = status == null ? '' : 'AND item.status = ?';
    return db.rawQuery('''
      SELECT item.id AS outingBirdId, item.status AS outingStatus,
        item.soldPrice AS outingSoldPrice, bird.*, species.name AS speciesName,
        cage.identifier AS cageIdentifier
      FROM sale_outing_birds item
      INNER JOIN birds bird ON bird.id = item.birdId
      LEFT JOIN species species ON species.id = bird.speciesId
      LEFT JOIN cages cage ON cage.id = bird.cageId
      WHERE item.outingId = ? $whereStatus
      ORDER BY species.name COLLATE NOCASE ASC,
        bird.mutation COLLATE NOCASE ASC,
        bird.ringNumber COLLATE NOCASE ASC
    ''', [outingId, ?status]);
  }

  Future<void> returnSaleOutingBirds(String outingId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sale_outing_birds',
        columns: ['id', 'birdId'],
        where: "outingId = ? AND status = 'Taken'",
        whereArgs: [outingId],
      );
      for (final row in rows) {
        await txn.update(
          'sale_outing_birds',
          {'status': 'Returned', 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        await txn.update(
          'birds',
          {'saleStatus': 'Available'},
          where: "id = ? AND COALESCE(active, 1) = 1 AND saleStatus = 'Taken for Sale'",
          whereArgs: [row['birdId']],
        );
      }
      await txn.update(
        'sale_outings',
        {'status': 'Completed'},
        where: 'id = ?',
        whereArgs: [outingId],
      );
    });
  }

  Future<void> recordOutingSoldBirds({
    required String outingId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final item in items) {
        final birdId = item['birdId']?.toString();
        final price = (item['price'] as num?)?.toDouble();
        if (birdId == null) continue;
        await txn.update(
          'sale_outing_birds',
          {'status': 'Sold', 'soldPrice': price, 'updatedAt': now},
          where: "outingId = ? AND birdId = ? AND status = 'Taken'",
          whereArgs: [outingId, birdId],
        );
      }
      final remaining = Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT COUNT(*) FROM sale_outing_birds WHERE outingId = ? AND status = 'Taken'",
        [outingId],
      ));
      if ((remaining ?? 0) == 0) {
        await txn.update(
          'sale_outings',
          {'status': 'Completed'},
          where: 'id = ?',
          whereArgs: [outingId],
        );
      }
    });
  }

  Future<Map<String, int>> getSaleWorkspaceSummary() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM birds
          WHERE COALESCE(active, 1) = 1 AND saleStatus IN ('Available', 'Reserved')) AS forSale,
        (SELECT COUNT(*) FROM birds
          WHERE COALESCE(active, 1) = 1 AND saleStatus = 'Taken for Sale') AS taken,
        (SELECT COUNT(*) FROM birds
          WHERE COALESCE(active, 1) = 0 AND saleStatus = 'Sold') AS sold,
        (SELECT COUNT(*) FROM sale_outing_birds WHERE status = 'Returned') AS returned
    ''');
    final row = rows.first;
    int value(String key) => (row[key] as num?)?.toInt() ?? 0;
    return {
      'forSale': value('forSale'),
      'taken': value('taken'),
      'sold': value('sold'),
      'returned': value('returned'),
    };
  }

  Future<List<Map<String, dynamic>>> getSalePriceGuides() async {
    final db = await database;
    return db.rawQuery('''
      SELECT guide.*, species.name AS speciesName
      FROM sale_price_guides guide
      INNER JOIN species species ON species.id = guide.speciesId
      ORDER BY species.name COLLATE NOCASE, guide.mutation COLLATE NOCASE, guide.ageGroup
    ''');
  }

  Future<void> setSalePriceGuide({
    required String speciesId,
    required String mutation,
    required String ageGroup,
    required double price,
  }) async {
    if (price <= 0) throw StateError('Estimated price must be greater than zero.');
    final db = await database;
    final cleanMutation = mutation.trim();
    final existing = await db.query(
      'sale_price_guides',
      columns: ['id'],
      where: 'speciesId = ? AND mutation = ? COLLATE NOCASE AND ageGroup = ? COLLATE NOCASE',
      whereArgs: [speciesId, cleanMutation, ageGroup],
      limit: 1,
    );
    final values = {
      'speciesId': speciesId,
      'mutation': cleanMutation,
      'ageGroup': ageGroup,
      'price': price,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (existing.isEmpty) {
      await db.insert('sale_price_guides', {'id': const Uuid().v4(), ...values});
    } else {
      await db.update(
        'sale_price_guides',
        values,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<void> addBreedingObservation({
    required String pairId,
    required String observationType,
    required DateTime observedAt,
    String? clutchId,
    String? notes,
  }) async {
    final db = await database;
    await db.insert('breeding_observations', {
      'id': const Uuid().v4(),
      'pairId': pairId,
      'clutchId': clutchId,
      'observationType': observationType,
      'observedAt': observedAt.toIso8601String(),
      'resolved': 0,
      'notes': notes?.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getBreedingObservations(
    String pairId, {
    int limit = 20,
  }) async {
    final db = await database;
    return db.query(
      'breeding_observations',
      where: 'pairId = ?',
      whereArgs: [pairId],
      orderBy: 'observedAt DESC, createdAt DESC',
      limit: limit,
    );
  }

  Future<void> resolveBreedingObservation(String id) async {
    final db = await database;
    await db.update(
      'breeding_observations',
      {'resolved': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Dashboard, activity and notifications
  // ---------------------------------------------------------------------------

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTime _addMonths(DateTime date, int months) {
    final target = DateTime(date.year, date.month + months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(target.year, target.month, day);
  }

  Future<List<Map<String, dynamic>>> synchronizeBirdAgeGroups() async {
    final db = await database;
    final changed = <Map<String, dynamic>>[];

    await db.transaction((txn) async {
      await _setSyncSuppressed(txn, true);
      try {
        final birds = await txn.rawQuery('''
        SELECT
          bird.id,
          bird.ringNumber,
          bird.name,
          bird.hatchDate,
          bird.sourceDate,
          bird.estimatedAgeDays,
          bird.ageGroup,
          species.name AS speciesName,
          species.chickToYoungDays,
          species.adultAgeMonths,
          cage.identifier AS cageIdentifier,
          pair.identifier AS pairIdentifier
        FROM birds bird
        LEFT JOIN species species ON species.id = bird.speciesId
        LEFT JOIN cages cage ON cage.id = bird.cageId
        LEFT JOIN pairs pair ON pair.id = bird.parentPairId
        WHERE COALESCE(bird.active, 1) = 1
          AND (
            bird.hatchDate IS NOT NULL
            OR (bird.sourceDate IS NOT NULL AND bird.estimatedAgeDays IS NOT NULL)
          )
      ''');

      final today = _dateOnly(DateTime.now());
      for (final bird in birds) {
        final hatchDate = DateTime.tryParse(bird['hatchDate']?.toString() ?? '');
        final sourceDate = DateTime.tryParse(bird['sourceDate']?.toString() ?? '');
        final estimatedAgeDays = (bird['estimatedAgeDays'] as num?)?.toInt();
        final effectiveBirthDate = hatchDate ??
            (sourceDate != null && estimatedAgeDays != null
                ? sourceDate.subtract(Duration(days: estimatedAgeDays))
                : null);
        if (effectiveBirthDate == null) continue;

        final chickDays = (bird['chickToYoungDays'] as num?)?.toInt();
        final adultMonths = (bird['adultAgeMonths'] as num?)?.toInt();
        String? calculated;
        DateTime? transitionDate;

        if (adultMonths != null && adultMonths > 0) {
          final adultDate = _addMonths(_dateOnly(effectiveBirthDate), adultMonths);
          if (!today.isBefore(adultDate)) {
            calculated = 'Adult';
            transitionDate = adultDate;
          }
        }
        if (calculated == null && chickDays != null && chickDays > 0) {
          final youngDate = _dateOnly(effectiveBirthDate).add(Duration(days: chickDays));
          if (!today.isBefore(youngDate)) {
            calculated = 'Young';
            transitionDate = youngDate;
          } else {
            calculated = 'Chick';
          }
        }

        if (calculated == null || calculated == bird['ageGroup']) continue;
        await txn.update(
          'birds',
          {'ageGroup': calculated},
          where: 'id = ?',
          whereArgs: [bird['id']],
        );
        final hasName = bird['name']?.toString().trim().isNotEmpty ?? false;
        final label = hasName
            ? '${bird['ringNumber']} — ${bird['name']}'
            : bird['ringNumber']?.toString() ?? 'Bird';
        final eventType = calculated == 'Adult' ? 'Became Adult' : 'Became Young';
        await _addBirdEventTxn(
          txn,
          birdId: bird['id'].toString(),
          eventType: eventType,
          eventDate: DateTime.now(),
          details: transitionDate == null
              ? 'Age group updated automatically'
              : 'Age group updated automatically on ${transitionDate.toIso8601String().split('T').first}',
        );
        changed.add({
          'alertKey': 'age_${bird['id']}_$calculated',
          'kind': 'age',
          'severity': 'info',
          'title': '$label is now $calculated',
          'body': [
            if (bird['cageIdentifier']?.toString().trim().isNotEmpty ?? false)
              'Cage ${bird['cageIdentifier']}',
            if (bird['pairIdentifier']?.toString().trim().isNotEmpty ?? false)
              'Pair ${bird['pairIdentifier']}',
            bird['speciesName']?.toString() ?? '',
          ].where((part) => part.isNotEmpty).join(' → '),
          'dueDate': transitionDate?.toIso8601String(),
          'entityType': 'Bird',
          'entityId': bird['id'],
        });
      }
      } finally {
        await _setSyncSuppressed(txn, false);
      }
    });
    return changed;
  }

  Future<Map<String, int>> getDashboardSummary() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM birds WHERE COALESCE(active, 1) = 1) AS birds,
        (SELECT COUNT(*) FROM cages
          WHERE COALESCE(active, 1) = 1 AND mergedIntoId IS NULL) AS cages,
        (SELECT COUNT(*) FROM pairs WHERE endedAt IS NULL AND breedingStatus = 'Active') AS pairs,
        (
          SELECT COALESCE(SUM(
            CASE
              WHEN COALESCE(activeClutch.expectedEggs, 0) > activeClutch.actualEggs
                THEN COALESCE(activeClutch.expectedEggs, 0)
              ELSE activeClutch.actualEggs
            END
          ), 0)
          FROM (
            SELECT
              clutch.id,
              clutch.expectedEggs,
              COUNT(CASE
                WHEN egg.status IN ('Incubating', 'Fertile') THEN egg.id
              END) AS actualEggs
            FROM clutches clutch
            LEFT JOIN eggs egg
              ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
            WHERE clutch.status = 'Active'
            GROUP BY clutch.id, clutch.expectedEggs
          ) activeClutch
        ) AS eggs,
        (
          SELECT COUNT(*) FROM birds
          WHERE COALESCE(active, 1) = 1
            AND nestClutchId IS NOT NULL
            AND leftNestDate IS NULL
        ) AS chicks,
        (
          SELECT COUNT(*) FROM birds
          WHERE COALESCE(active, 1) = 1
            AND saleStatus = 'Reserved'
        ) AS reserved,
        (
          SELECT COUNT(*) FROM birds
          WHERE COALESCE(active, 1) = 1
            AND saleStatus IN ('Available', 'Reserved')
        ) AS saleList,
        (
          SELECT COUNT(*) FROM birds
          WHERE COALESCE(active, 1) = 1
            AND saleStatus = 'Taken for Sale'
        ) AS takenForSale,
        (
          SELECT COUNT(*) FROM breeding_observations
          WHERE resolved = 0
        ) AS observations
    ''');
    final row = rows.first;
    int value(String key) => (row[key] as num?)?.toInt() ?? 0;
    return {
      'birds': value('birds'),
      'cages': value('cages'),
      'pairs': value('pairs'),
      'eggs': value('eggs'),
      'chicks': value('chicks'),
      'reserved': value('reserved'),
      'saleList': value('saleList'),
      'takenForSale': value('takenForSale'),
      'observations': value('observations'),
    };
  }

  Future<List<Map<String, dynamic>>> getPairsWithIncubatingEggs() async {
    final rows = await getBreedingPairs();
    return rows
        .where((row) => ((row['activeEggCount'] as num?)?.toInt() ?? 0) > 0)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getCagesWithChicks() async {
    final db = await database;
    return db.rawQuery('''
      SELECT cage.*,
        COUNT(DISTINCT bird.id) AS chickCount
      FROM cages cage
      INNER JOIN birds bird ON bird.cageId = cage.id
      WHERE COALESCE(cage.active, 1) = 1
        AND cage.mergedIntoId IS NULL
        AND COALESCE(bird.active, 1) = 1
        AND bird.nestClutchId IS NOT NULL
        AND bird.leftNestDate IS NULL
      GROUP BY cage.id
      HAVING COUNT(DISTINCT bird.id) > 0
      ORDER BY cage.identifier COLLATE NOCASE ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> getSaleListBirds() async {
    await synchronizeAutomaticSaleStatuses();
    final db = await database;
    return db.rawQuery('''
      SELECT bird.*, species.name AS speciesName, cage.identifier AS cageIdentifier,
        CASE WHEN pair.id IS NULL THEN 0 ELSE 1 END AS isPaired
      FROM birds bird
      LEFT JOIN species species ON species.id = bird.speciesId
      LEFT JOIN cages cage ON cage.id = bird.cageId
      LEFT JOIN pairs pair
        ON pair.endedAt IS NULL
        AND (pair.maleBirdId = bird.id OR pair.femaleBirdId = bird.id)
      WHERE COALESCE(bird.active, 1) = 1
        AND bird.saleStatus IN ('Available', 'Reserved')
      GROUP BY bird.id
      ORDER BY
        CASE bird.saleStatus WHEN 'Available' THEN 0 ELSE 1 END,
        COALESCE(bird.hatchDate, bird.sourceDate, bird.createdAt) DESC,
        bird.ringNumber COLLATE NOCASE ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> getAvailableEggsForSale() async {
    final db = await database;
    return db.rawQuery('''
      SELECT egg.*,
        clutch.clutchNumber,
        pair.id AS pairId,
        pair.identifier AS pairIdentifier,
        cage.identifier AS cageIdentifier
      FROM eggs egg
      INNER JOIN clutches clutch
        ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
      INNER JOIN pairs pair ON pair.id = clutch.pairId
      INNER JOIN birds male ON male.id = pair.maleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      WHERE clutch.status = 'Active'
        AND pair.endedAt IS NULL
        AND egg.status IN ('Incubating', 'Fertile')
      ORDER BY cage.identifier COLLATE NOCASE ASC,
        pair.identifier COLLATE NOCASE ASC,
        egg.expectedHatchDate ASC,
        egg.eggNumber ASC
    ''');
  }

  Future<void> sellEgg({
    required String eggId,
    required double price,
    required DateTime soldAt,
    String? notes,
  }) async {
    if (price <= 0) throw StateError('Sale amount is required.');
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT egg.id, egg.eggNumber, egg.clutchId, egg.currentClutchId,
          pair.identifier AS pairIdentifier
        FROM eggs egg
        INNER JOIN clutches clutch
          ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
        INNER JOIN pairs pair ON pair.id = clutch.pairId
        WHERE egg.id = ?
          AND clutch.status = 'Active'
          AND egg.status IN ('Incubating', 'Fertile')
        LIMIT 1
      ''', [eggId]);
      if (rows.isEmpty) throw StateError('This egg is no longer available for sale.');
      final row = rows.first;
      await txn.update(
        'eggs',
        {'status': 'Sold', 'updatedAt': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [eggId],
      );
      final transactionId = 'egg_sale_${eggId}_${soldAt.microsecondsSinceEpoch}';
      final label = '${row['pairIdentifier'] ?? 'Pair'} · Egg ${row['eggNumber'] ?? '?'}';
      await txn.insert('finance_transactions', {
        'id': transactionId,
        'type': 'Income',
        'category': 'Egg Sale',
        'amount': price,
        'date': soldAt.toIso8601String(),
        'notes': [label, if (notes?.trim().isNotEmpty == true) notes!.trim()].join(' · '),
        'birdId': null,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await _addActivityEventTxn(
        txn,
        category: 'Finance',
        eventType: 'Income',
        eventDate: soldAt,
        title: 'Egg Sale',
        details: label,
        entityType: 'Egg',
        entityId: eggId,
        amount: price,
        financeType: 'Income',
        sourceKey: 'finance_$transactionId',
      );
      await _evaluateClutchClosure(txn, row['clutchId'].toString());
      final current = row['currentClutchId']?.toString();
      if (current != null && current.isNotEmpty && current != row['clutchId'].toString()) {
        await _evaluateClutchClosure(txn, current);
      }
    });
  }

  Future<Set<String>> _dismissedDashboardKeys() async {
    final db = await database;
    final rows = await db.query(
      'dismissed_dashboard_alerts',
      columns: ['alertKey'],
    );
    return rows.map((row) => row['alertKey'].toString()).toSet();
  }

  Future<void> dismissDashboardAlert(String alertKey) async {
    final db = await database;
    await db.insert(
      'dismissed_dashboard_alerts',
      {'alertKey': alertKey, 'dismissedAt': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearDismissedDashboardAlerts() async {
    final db = await database;
    await db.delete('dismissed_dashboard_alerts');
  }

  Future<List<Map<String, dynamic>>> getDashboardAlerts() async {
    final ageChanges = await synchronizeBirdAgeGroups();
    final db = await database;
    final alerts = <Map<String, dynamic>>[...ageChanges];
    final today = _dateOnly(DateTime.now());

    final eggRows = await db.rawQuery('''
      SELECT
        egg.id,
        egg.eggNumber,
        egg.expectedHatchDate,
        clutch.id AS clutchId,
        clutch.clutchNumber,
        pair.id AS pairId,
        pair.identifier AS pairIdentifier,
        cage.identifier AS cageIdentifier
      FROM eggs egg
      INNER JOIN clutches clutch
        ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
      INNER JOIN pairs pair ON pair.id = clutch.pairId
      INNER JOIN birds male ON male.id = pair.maleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      WHERE clutch.status = 'Active'
        AND egg.status IN ('Incubating', 'Fertile')
        AND egg.expectedHatchDate IS NOT NULL
      ORDER BY pair.id, egg.expectedHatchDate ASC, egg.eggNumber ASC
    ''');

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in eggRows) {
      final expected =
          DateTime.tryParse(row['expectedHatchDate']?.toString() ?? '');
      if (expected == null) continue;
      final days = _dateOnly(expected).difference(today).inDays;
      if (days > 5) continue;
      final enriched = Map<String, dynamic>.from(row)..['days'] = days;
      grouped.putIfAbsent(row['pairId'].toString(), () => []).add(enriched);
    }

    for (final rows in grouped.values) {
      if (rows.isEmpty) continue;
      final urgent = rows.where((row) => (row['days'] as int) <= 0).toList();
      List<Map<String, dynamic>> visible;
      if (urgent.isNotEmpty) {
        visible = urgent;
      } else {
        final nearest = rows
            .map((row) => row['days'] as int)
            .reduce((a, b) => a < b ? a : b);
        visible = rows.where((row) => row['days'] == nearest).toList();
      }
      visible.sort((a, b) {
        final dayCompare =
            (a['days'] as int).compareTo(b['days'] as int);
        if (dayCompare != 0) return dayCompare;
        return ((a['eggNumber'] as num?)?.toInt() ?? 0)
            .compareTo((b['eggNumber'] as num?)?.toInt() ?? 0);
      });

      final mostUrgentDays = visible
          .map((row) => row['days'] as int)
          .reduce((a, b) => a < b ? a : b);
      final headline = mostUrgentDays < 0
          ? 'Overdue'
          : mostUrgentDays == 0
              ? 'Hatch today'
              : mostUrgentDays == 1
                  ? 'Hatch tomorrow'
                  : 'Hatch in $mostUrgentDays days';
      final severity = mostUrgentDays < 0
          ? 'overdue'
          : mostUrgentDays == 0
              ? 'due'
              : mostUrgentDays == 1
                  ? 'urgent'
                  : mostUrgentDays <= 3
                      ? 'warning'
                      : 'notice';

      String eggLine(Map<String, dynamic> row) {
        final days = row['days'] as int;
        final status = days < 0
            ? 'Overdue by ${-days} day${days == -1 ? '' : 's'}'
            : days == 0
                ? 'About to hatch today'
                : days == 1
                    ? 'Hatch tomorrow'
                    : 'Hatch in $days days';
        return 'Egg ${row['eggNumber']} — $status';
      }

      final first = visible.first;
      final cage = first['cageIdentifier']?.toString().trim();
      final cageLabel = cage == null || cage.isEmpty
          ? 'No cage'
          : cage.toLowerCase().startsWith('cage')
              ? cage
              : 'Cage $cage';
      final pairLabel = first['pairIdentifier']?.toString() ?? 'Pair';
      final lines = visible.map(eggLine).toList();
      final keyParts =
          visible.map((row) => '${row['id']}:${row['days']}').join('|');
      alerts.add({
        'alertKey': 'pair_hatch_${first['pairId']}_$keyParts',
        'kind': 'pair_hatch',
        'severity': severity,
        'title': '$cageLabel — $headline',
        'pairLabel': pairLabel,
        'eggLines': lines,
        'body': ['Pair $pairLabel', ...lines].join('\n'),
        'dueDate': first['expectedHatchDate'],
        'entityType': 'Pair',
        'entityId': first['pairId'],
        'sortDays': mostUrgentDays,
      });
    }

    final dismissed = await _dismissedDashboardKeys();
    alerts.removeWhere((alert) =>
        alert['kind'] != 'pair_hatch' &&
        dismissed.contains(alert['alertKey']));

    // Needs Attention is ordered by actual urgency, not pair/database order.
    // Pair hatch cards use their most urgent visible egg as the sort key.
    alerts.sort((a, b) {
      final aIsHatch = a['kind'] == 'pair_hatch';
      final bIsHatch = b['kind'] == 'pair_hatch';
      if (aIsHatch && bIsHatch) {
        final aDays = (a['sortDays'] as num?)?.toInt() ?? 999999;
        final bDays = (b['sortDays'] as num?)?.toInt() ?? 999999;
        final dayCompare = aDays.compareTo(bDays);
        if (dayCompare != 0) return dayCompare;
        return (a['title']?.toString() ?? '')
            .compareTo(b['title']?.toString() ?? '');
      }
      if (aIsHatch != bIsHatch) return aIsHatch ? -1 : 1;

      final aDate = DateTime.tryParse(a['dueDate']?.toString() ?? '');
      final bDate = DateTime.tryParse(b['dueDate']?.toString() ?? '');
      if (aDate != null && bDate != null) return aDate.compareTo(bDate);
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return 0;
    });
    return alerts;
  }

  Future<List<Map<String, dynamic>>> getActivityEvents({
    String? category,
    String? birdId,
    int limit = 300,
  }) async {
    final db = await database;
    final clauses = <String>[
      "((category = 'Birds' AND eventType IN ("
          "'Purchased','Bird Purchased','Birds Purchased','Sold','Bird Sold','Birds Sold',"
          "'Died','Gifted','Gift','Flew Away','Removed','Ring Removed','Bred Bird Added',"
          "'Caught','Rescued'"
          ")) OR (category = 'Breeding' AND eventType IN ("
          "'Pair Created','Pair Re-activated','Pair Ended','First Egg Laid','Chick Hatched'"
          ")))",
    ];
    final args = <Object?>[];
    if (category != null && category != 'All') {
      clauses.add('category = ?');
      args.add(category);
    }
    if (birdId != null) {
      clauses.add('''
        (birdId = ?
          OR (entityType = 'Pair' AND entityId IN (
            SELECT id FROM pairs WHERE maleBirdId = ? OR femaleBirdId = ?
          ))
          OR (entityType = 'Clutch' AND entityId IN (
            SELECT clutch.id
            FROM clutches clutch
            INNER JOIN pairs pair ON pair.id = clutch.pairId
            WHERE pair.maleBirdId = ? OR pair.femaleBirdId = ?
          )))
      ''');
      args.addAll([birdId, birdId, birdId, birdId, birdId]);
    }
    args.add(limit);
    return db.rawQuery('''
      SELECT * FROM activity_events
      WHERE ${clauses.join(' AND ')}
      ORDER BY eventDate DESC, id DESC
      LIMIT ?
    ''', args);
  }

  Future<Map<String, int>> getBirdDeleteImpact(String birdId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM bird_events WHERE birdId = ?) AS events,
        (SELECT COUNT(*) FROM finance_transactions WHERE birdId = ?) AS finance,
        (SELECT COUNT(*) FROM pairs
          WHERE maleBirdId = ? OR femaleBirdId = ?) AS pairs,
        (SELECT COUNT(*) FROM clutches
          WHERE pairId IN (
            SELECT id FROM pairs WHERE maleBirdId = ? OR femaleBirdId = ?
          )) AS clutches,
        (SELECT COUNT(*) FROM birds
          WHERE parentPairId IN (
            SELECT id FROM pairs WHERE maleBirdId = ? OR femaleBirdId = ?
          )) AS offspring
    ''', [
      birdId,
      birdId,
      birdId,
      birdId,
      birdId,
      birdId,
      birdId,
      birdId,
    ]);
    final row = rows.first;
    int value(String key) => (row[key] as num?)?.toInt() ?? 0;
    return {
      'events': value('events'),
      'finance': value('finance'),
      'pairs': value('pairs'),
      'clutches': value('clutches'),
      'offspring': value('offspring'),
    };
  }

  Future<void> deleteBirdCompletely(String birdId) async {
    final db = await database;
    await db.transaction((txn) async {
      final pairRows = await txn.query(
        'pairs',
        columns: ['id'],
        where: 'maleBirdId = ? OR femaleBirdId = ?',
        whereArgs: [birdId, birdId],
      );
      final pairIds = pairRows.map((row) => row['id'].toString()).toList();
      final clutchIds = <String>[];

      for (final pairId in pairIds) {
        final rows = await txn.query(
          'clutches',
          columns: ['id'],
          where: 'pairId = ?',
          whereArgs: [pairId],
        );
        clutchIds.addAll(rows.map((row) => row['id'].toString()));
      }

      for (final clutchId in clutchIds) {
        await txn.update(
          'birds',
          {
            'nestClutchId': null,
            'originClutchId': null,
          },
          where: 'nestClutchId = ? OR originClutchId = ?',
          whereArgs: [clutchId, clutchId],
        );
        await txn.delete(
          'activity_events',
          where: "entityType = 'Clutch' AND entityId = ?",
          whereArgs: [clutchId],
        );
        await txn.delete(
          'eggs',
          where: 'clutchId = ? OR currentClutchId = ?',
          whereArgs: [clutchId, clutchId],
        );
        await txn.delete('clutches', where: 'id = ?', whereArgs: [clutchId]);
      }

      for (final pairId in pairIds) {
        await txn.update(
          'birds',
          {'parentPairId': null},
          where: 'parentPairId = ?',
          whereArgs: [pairId],
        );
        await txn.delete('pair_sessions', where: 'pairId = ?', whereArgs: [pairId]);
        await txn.delete(
          'activity_events',
          where: "entityType = 'Pair' AND entityId = ?",
          whereArgs: [pairId],
        );
        await txn.delete('pairs', where: 'id = ?', whereArgs: [pairId]);
      }

      final financeRows = await txn.query(
        'finance_transactions',
        columns: ['id'],
        where: 'birdId = ?',
        whereArgs: [birdId],
      );
      for (final row in financeRows) {
        final financeId = row['id'].toString();
        await txn.delete(
          'activity_events',
          where: "entityType = 'Finance' AND entityId = ?",
          whereArgs: [financeId],
        );
      }
      await txn.delete('finance_transactions', where: 'birdId = ?', whereArgs: [birdId]);
      await txn.update(
        'eggs',
        {'hatchedBirdId': null},
        where: 'hatchedBirdId = ?',
        whereArgs: [birdId],
      );
      await txn.delete('bird_events', where: 'birdId = ?', whereArgs: [birdId]);
      await txn.delete(
        'activity_events',
        where: 'birdId = ? OR (entityType = ? AND entityId = ?)',
        whereArgs: [birdId, 'Bird', birdId],
      );
      await txn.delete('birds', where: 'id = ?', whereArgs: [birdId]);
    });
  }

  Future<Map<String, dynamic>> getHatchNotificationSummary() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT egg.id, egg.expectedHatchDate
      FROM eggs egg
      INNER JOIN clutches clutch
        ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
      INNER JOIN pairs pair ON pair.id = clutch.pairId
      WHERE clutch.status = 'Active'
        AND pair.endedAt IS NULL
        AND egg.status IN ('Incubating', 'Fertile')
        AND egg.expectedHatchDate IS NOT NULL
      ORDER BY egg.expectedHatchDate ASC, egg.id ASC
    ''');
    final today = _dateOnly(DateTime.now());
    var dueToday = 0;
    final overdue = <int, int>{};
    final signatureParts = <String>[];
    for (final row in rows) {
      final date = DateTime.tryParse(row['expectedHatchDate']?.toString() ?? '');
      if (date == null) continue;
      final due = _dateOnly(date);
      final days = today.difference(due).inDays;
      if (days < 0) continue;
      signatureParts.add('${row['id']}:${due.toIso8601String()}');
      if (days == 0) {
        dueToday++;
      } else {
        overdue[days] = (overdue[days] ?? 0) + 1;
      }
    }
    final overdueCount = overdue.values.fold<int>(0, (sum, count) => sum + count);
    return {
      'dueToday': dueToday,
      'overdueCount': overdueCount,
      'total': dueToday + overdueCount,
      'overdueByDays': overdue,
      'eggSignature': signatureParts.join('|'),
    };
  }

  Future<List<Map<String, dynamic>>> getNotificationCandidates() async {
    final db = await database;
    final result = <Map<String, dynamic>>[];
    final today = _dateOnly(DateTime.now());

    final eggs = await db.rawQuery('''
      SELECT
        egg.id,
        egg.eggNumber,
        egg.expectedHatchDate,
        clutch.id AS clutchId,
        pair.id AS pairId,
        pair.identifier AS pairIdentifier,
        cage.identifier AS cageIdentifier
      FROM eggs egg
      INNER JOIN clutches clutch
        ON clutch.id = COALESCE(egg.currentClutchId, egg.clutchId)
      INNER JOIN pairs pair ON pair.id = clutch.pairId
      INNER JOIN birds male ON male.id = pair.maleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      WHERE clutch.status = 'Active'
        AND egg.status IN ('Incubating', 'Fertile')
        AND egg.expectedHatchDate IS NOT NULL
      ORDER BY pair.id, egg.expectedHatchDate ASC, egg.eggNumber ASC
    ''');

    final byPair = <String, List<Map<String, dynamic>>>{};
    for (final egg in eggs) {
      final expected =
          DateTime.tryParse(egg['expectedHatchDate']?.toString() ?? '');
      if (expected == null) continue;
      final row = Map<String, dynamic>.from(egg)
        ..['expectedDate'] = _dateOnly(expected)
        ..['days'] = _dateOnly(expected).difference(today).inDays;
      byPair.putIfAbsent(egg['pairId'].toString(), () => []).add(row);
    }

    for (final rows in byPair.values) {
      if (rows.isEmpty) continue;
      final due = rows.where((row) => (row['days'] as int) <= 0).toList();
      final first = rows.first;
      final cage = first['cageIdentifier']?.toString().trim();
      final cageLabel = cage == null || cage.isEmpty
          ? 'No cage'
          : cage.toLowerCase().startsWith('cage')
              ? cage
              : 'Cage $cage';
      final pairLabel = first['pairIdentifier']?.toString() ?? 'Pair';

      if (due.isNotEmpty) {
        due.sort((a, b) => (a['days'] as int).compareTo(b['days'] as int));
        final bodyLines = due.map((row) {
          final days = row['days'] as int;
          return 'Egg ${row['eggNumber']} — ${days < 0 ? 'overdue by ${-days} day${days == -1 ? '' : 's'}' : 'hatch today'}';
        }).toList();
        result.add({
          'key': 'pair_${first['pairId']}_hatch_due',
          'title': '$cageLabel — Hatch check',
          'body': ['Pair $pairLabel', ...bodyLines].join('\n'),
          'scheduledFor': today.toIso8601String(),
          'persistent': true,
        });
        continue;
      }

      final nearestDays = rows
          .map((row) => row['days'] as int)
          .reduce((a, b) => a < b ? a : b);
      final nearest =
          rows.where((row) => row['days'] == nearestDays).toList();
      final hatchDate = nearest.first['expectedDate'] as DateTime;
      final eggLabels =
          nearest.map((row) => 'Egg ${row['eggNumber']}').join(', ');
      final body = 'Pair $pairLabel · $eggLabels';
      result.add({
        'key': 'pair_${first['pairId']}_${hatchDate.toIso8601String()}_day_before',
        'title': '$cageLabel — Hatch tomorrow',
        'body': body,
        'scheduledFor':
            hatchDate.subtract(const Duration(days: 1)).toIso8601String(),
        'persistent': false,
      });
      result.add({
        'key': 'pair_${first['pairId']}_${hatchDate.toIso8601String()}_hatch_day',
        'title': '$cageLabel — Hatch today',
        'body': body,
        'scheduledFor': hatchDate.toIso8601String(),
        'persistent': true,
      });
    }

    final birds = await db.rawQuery('''
      SELECT
        bird.id,
        bird.ringNumber,
        bird.name,
        bird.hatchDate,
        species.chickToYoungDays,
        species.adultAgeMonths,
        cage.identifier AS cageIdentifier,
        pair.identifier AS pairIdentifier
      FROM birds bird
      INNER JOIN species species ON species.id = bird.speciesId
      LEFT JOIN cages cage ON cage.id = bird.cageId
      LEFT JOIN pairs pair ON pair.id = bird.parentPairId
      WHERE COALESCE(bird.active, 1) = 1
        AND bird.hatchDate IS NOT NULL
    ''');
    for (final bird in birds) {
      final hatch = DateTime.tryParse(bird['hatchDate'].toString());
      if (hatch == null) continue;
      final hasName = bird['name']?.toString().trim().isNotEmpty ?? false;
      final label = hasName
          ? '${bird['ringNumber']} — ${bird['name']}'
          : bird['ringNumber']?.toString() ?? 'Bird';
      final location = [
        if (bird['cageIdentifier'] != null)
          'Cage ${bird['cageIdentifier']}',
        if (bird['pairIdentifier'] != null)
          'Pair ${bird['pairIdentifier']}',
      ].join(' → ');
      final youngDays = (bird['chickToYoungDays'] as num?)?.toInt();
      if (youngDays != null && youngDays > 0) {
        result.add({
          'key': 'age_${bird['id']}_young',
          'title': '$label becomes Young today',
          'body': location,
          'scheduledFor': _dateOnly(hatch)
              .add(Duration(days: youngDays))
              .toIso8601String(),
          'persistent': false,
        });
      }
      final adultMonths = (bird['adultAgeMonths'] as num?)?.toInt();
      if (adultMonths != null && adultMonths > 0) {
        result.add({
          'key': 'age_${bird['id']}_adult',
          'title': '$label becomes Adult today',
          'body': location,
          'scheduledFor':
              _addMonths(_dateOnly(hatch), adultMonths).toIso8601String(),
          'persistent': false,
        });
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getOffspringForBird(String birdId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        child.*,
        species.name AS speciesName,
        species.chickToYoungDays,
        species.adultAgeMonths,
        cage.identifier AS cageIdentifier,
        pair.id AS biologicalPairId,
        pair.identifier AS pairIdentifier,
        CASE WHEN pair.maleBirdId = ? THEN pair.femaleBirdId ELSE pair.maleBirdId END AS spouseBirdId,
        CASE WHEN pair.maleBirdId = ? THEN female.ringNumber ELSE male.ringNumber END AS spouseRingNumber,
        CASE WHEN pair.maleBirdId = ? THEN female.name ELSE male.name END AS spouseName,
        CASE WHEN pair.maleBirdId = ? THEN female.gender ELSE male.gender END AS spouseGender,
        CASE
          WHEN COALESCE(child.active, 1) = 1 THEN 'Present'
          WHEN LOWER(COALESCE(child.removalReason, '')) = 'died' THEN 'Died'
          WHEN LOWER(COALESCE(child.removalReason, '')) = 'sold'
            OR child.saleStatus = 'Sold' THEN 'Sold'
          WHEN LOWER(COALESCE(child.removalReason, '')) = 'gifted' THEN 'Gifted'
          WHEN LOWER(COALESCE(child.removalReason, '')) = 'flew away' THEN 'Flew Away'
          ELSE COALESCE(child.removalReason, 'Removed')
        END AS currentStatus
      FROM pairs pair
      INNER JOIN birds male ON male.id = pair.maleBirdId
      INNER JOIN birds female ON female.id = pair.femaleBirdId
      INNER JOIN birds child ON child.parentPairId = pair.id
      LEFT JOIN species species ON species.id = child.speciesId
      LEFT JOIN cages cage ON cage.id = child.cageId
      WHERE pair.maleBirdId = ? OR pair.femaleBirdId = ?
      ORDER BY
        CASE WHEN COALESCE(child.active, 1) = 1 THEN 0 ELSE 1 END,
        COALESCE(child.hatchDate, child.sourceDate, child.createdAt) DESC,
        child.ringNumber COLLATE NOCASE ASC
    ''', [birdId, birdId, birdId, birdId, birdId, birdId]);
  }

  Future<Map<String, int>> getBirdRelationSummary(String birdId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM bird_events
          WHERE birdId = ? AND eventType = 'Cage Changed') AS cageChanges,
        (SELECT COUNT(DISTINCT CASE
            WHEN maleBirdId = ? THEN femaleBirdId ELSE maleBirdId END)
          FROM pairs
          WHERE maleBirdId = ? OR femaleBirdId = ?) AS spouses,
        (SELECT COUNT(*) FROM clutches
          WHERE pairId IN (
            SELECT id FROM pairs WHERE maleBirdId = ? OR femaleBirdId = ?
          )) AS clutches,
        (SELECT COUNT(*) FROM birds
          WHERE parentPairId IN (
            SELECT id FROM pairs WHERE maleBirdId = ? OR femaleBirdId = ?
          )) AS offspring
    ''', [
      birdId,
      birdId,
      birdId,
      birdId,
      birdId,
      birdId,
      birdId,
      birdId,
    ]);
    final row = rows.first;
    int value(String key) => (row[key] as num?)?.toInt() ?? 0;
    return {
      'cageChanges': value('cageChanges'),
      'spouses': value('spouses'),
      'clutches': value('clutches'),
      'offspring': value('offspring'),
    };
  }

  Future<List<Map<String, dynamic>>> getBirdSpouses(String birdId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        pair.id AS pairId,
        pair.identifier AS pairIdentifier,
        pair.createdAt,
        pair.endedAt,
        CASE WHEN pair.maleBirdId = ? THEN female.id ELSE male.id END AS spouseBirdId,
        CASE WHEN pair.maleBirdId = ? THEN female.ringNumber ELSE male.ringNumber END AS spouseRingNumber,
        CASE WHEN pair.maleBirdId = ? THEN female.name ELSE male.name END AS spouseName,
        CASE WHEN pair.maleBirdId = ? THEN female.gender ELSE male.gender END AS spouseGender,
        CASE WHEN pair.maleBirdId = ? THEN female.mutation ELSE male.mutation END AS spouseMutation,
        CASE WHEN pair.maleBirdId = ? THEN female.active ELSE male.active END AS spouseActive,
        CASE WHEN pair.maleBirdId = ? THEN female.removalReason ELSE male.removalReason END AS spouseRemovalReason,
        CASE WHEN pair.maleBirdId = ? THEN female.saleStatus ELSE male.saleStatus END AS spouseSaleStatus,
        CASE WHEN pair.maleBirdId = ? THEN femaleSpecies.name ELSE maleSpecies.name END AS spouseSpeciesName
      FROM pairs pair
      INNER JOIN birds male ON male.id = pair.maleBirdId
      INNER JOIN birds female ON female.id = pair.femaleBirdId
      LEFT JOIN species maleSpecies ON maleSpecies.id = male.speciesId
      LEFT JOIN species femaleSpecies ON femaleSpecies.id = female.speciesId
      WHERE pair.maleBirdId = ? OR pair.femaleBirdId = ?
      ORDER BY CASE WHEN pair.endedAt IS NULL THEN 0 ELSE 1 END,
               COALESCE(pair.endedAt, pair.createdAt) DESC
    ''', [
      birdId, birdId, birdId, birdId, birdId, birdId, birdId, birdId, birdId,
      birdId, birdId,
    ]);
  }

  Future<Map<String, Map<String, dynamic>>> quickEditBirds({
    required List<String> birdIds,
    required Map<String, dynamic> changes,
  }) async {
    if (birdIds.isEmpty) return {};
    const allowed = {'name', 'mutation', 'gender'};
    final safe = <String, dynamic>{};
    for (final entry in changes.entries) {
      if (allowed.contains(entry.key)) safe[entry.key] = entry.value;
    }
    if (safe.isEmpty) throw StateError('Choose at least one field to edit.');
    final db = await database;
    final previous = <String, Map<String, dynamic>>{};
    await db.transaction((txn) async {
      for (final id in birdIds) {
        final rows = await txn.query(
          'birds',
          columns: ['id', 'name', 'mutation', 'gender'],
          where: 'id = ? AND COALESCE(active, 1) = 1',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        previous[id] = Map<String, dynamic>.from(rows.first);
        await txn.update('birds', safe, where: 'id = ?', whereArgs: [id]);
        await _addBirdEventTxn(
          txn,
          birdId: id,
          eventType: 'Quick Edited',
          eventDate: DateTime.now(),
          details: 'Updated ${safe.keys.join(', ')}',
        );
      }
    });
    return previous;
  }

  Future<void> undoQuickEditBirds(
    Map<String, Map<String, dynamic>> previous,
  ) async {
    if (previous.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in previous.entries) {
        final row = entry.value;
        await txn.update(
          'birds',
          {
            'name': row['name'],
            'mutation': row['mutation'],
            'gender': row['gender'],
          },
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        await _addBirdEventTxn(
          txn,
          birdId: entry.key,
          eventType: 'Quick Edit Undone',
          eventDate: DateTime.now(),
          details: 'Restored values from the previous bulk edit',
        );
      }
    });
  }

  Future<void> insertPurchasedBirdBatch(
    List<Map<String, dynamic>> birds,
  ) async {
    if (birds.isEmpty) throw StateError('Add at least one bird.');
    final db = await database;
    await db.transaction((txn) async {
      var total = 0.0;
      DateTime? purchaseDate;
      String seller = '';
      String notes = '';
      final batchId = const Uuid().v4();

      for (final source in birds) {
        final values = Map<String, dynamic>.from(source);
        final id = values['id']?.toString();
        if (id == null || id.isEmpty) throw StateError('Bird ID is missing.');
        final price = (values['purchasePrice'] as num?)?.toDouble();
        if (price == null || price <= 0) {
          throw StateError('Purchase amount is required for every bird.');
        }
        total += price;
        purchaseDate ??=
            DateTime.tryParse(values['sourceDate']?.toString() ?? '') ??
                DateTime.now();
        seller = values['sourcePerson']?.toString().trim() ?? seller;
        notes = values['notes']?.toString().trim() ?? notes;
        values['createdAt'] ??= DateTime.now().toIso8601String();
        values['source'] = 'Purchase';
        values['saleStatus'] = 'Not for Sale';
        values['active'] = 1;
        await txn.insert(
          'birds',
          values,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await _addBirdEventTxn(
          txn,
          birdId: id,
          eventType: 'Purchased',
          eventDate: purchaseDate,
          details: 'Purchased in a batch of ${birds.length} birds.',
        );
      }

      final transactionId = 'bird_purchase_batch_$batchId';
      final financeNotes = [
        '${birds.length} bird${birds.length == 1 ? '' : 's'} purchased',
        if (seller.isNotEmpty) 'Seller: $seller',
        if (notes.isNotEmpty) notes,
      ].join(' · ');
      await txn.insert('finance_transactions', {
        'id': transactionId,
        'type': 'Expense',
        'category': 'Bird Purchase',
        'amount': total,
        'date': purchaseDate!.toIso8601String(),
        'notes': financeNotes,
        'birdId': null,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await _addActivityEventTxn(
        txn,
        category: 'Finance',
        eventType: 'Expense',
        eventDate: purchaseDate,
        title: 'Bird Purchase',
        details: financeNotes,
        entityType: 'Finance',
        entityId: transactionId,
        amount: total,
        financeType: 'Expense',
        sourceKey: 'finance_$transactionId',
      );
    });
  }

  Future<void> sellBirdBatch({
    required List<Map<String, dynamic>> items,
    required DateTime soldAt,
    String? buyer,
    String? notes,
    Set<String> releaseRingBirdIds = const <String>{},
  }) async {
    if (items.isEmpty) throw StateError('Select at least one bird.');
    final db = await database;
    await db.transaction((txn) async {
      var total = 0.0;
      final batchId = const Uuid().v4();
      final clutchIds = <String>{};

      for (final item in items) {
        final birdId = item['birdId']?.toString() ?? '';
        final price = (item['price'] as num?)?.toDouble();
        if (birdId.isEmpty || price == null || price <= 0) {
          throw StateError('Every sold bird needs a valid price.');
        }
        final rows = await txn.query(
          'birds',
          columns: ['ringNumber', 'name', 'active', 'nestClutchId'],
          where: 'id = ?',
          whereArgs: [birdId],
          limit: 1,
        );
        if (rows.isEmpty || (rows.first['active'] as num?)?.toInt() == 0) {
          throw StateError('One selected bird is no longer available for sale.');
        }
        final row = rows.first;
        final ring = row['ringNumber']?.toString().trim() ?? '';
        total += price;
        final nest = row['nestClutchId']?.toString();
        if (nest != null && nest.isNotEmpty) clutchIds.add(nest);
        final eggRows = await txn.query(
          'eggs',
          columns: ['clutchId', 'currentClutchId'],
          where: 'hatchedBirdId = ?',
          whereArgs: [birdId],
        );
        for (final egg in eggRows) {
          clutchIds.add(egg['clutchId'].toString());
          final current = egg['currentClutchId']?.toString();
          if (current != null && current.isNotEmpty) clutchIds.add(current);
        }

        await txn.update(
          'birds',
          {
            'saleStatus': 'Sold',
            'soldBuyer': buyer?.trim(),
            'soldPrice': price,
            'soldAt': soldAt.toIso8601String(),
            'soldNotes': notes?.trim(),
            'active': 0,
            'removedAt': soldAt.toIso8601String(),
            'removalReason': 'Sold',
            'cageId': null,
          },
          where: 'id = ?',
          whereArgs: [birdId],
        );
        final affectedPairs = await txn.query(
          'pairs',
          columns: ['id'],
          where: 'endedAt IS NULL AND (maleBirdId = ? OR femaleBirdId = ?)',
          whereArgs: [birdId, birdId],
        );
        await txn.update(
          'pairs',
          {
            'endedAt': soldAt.toIso8601String(),
            'endReason': 'Bird sold',
            'breedingStatus': 'Inactive',
          },
          where: 'endedAt IS NULL AND (maleBirdId = ? OR femaleBirdId = ?)',
          whereArgs: [birdId, birdId],
        );
        for (final pair in affectedPairs) {
          await txn.update(
            'pair_sessions',
            {
              'endedAt': soldAt.toIso8601String(),
              'endReason': 'Bird sold',
              'cageId': null,
            },
            where: 'pairId = ? AND endedAt IS NULL',
            whereArgs: [pair['id']],
          );
        }

        await _addBirdEventTxn(
          txn,
          birdId: birdId,
          eventType: 'Sold',
          eventDate: soldAt,
          details: [
            if (buyer?.trim().isNotEmpty == true) 'Buyer: ${buyer!.trim()}',
            'Price: $price',
            if (notes?.trim().isNotEmpty == true) notes!.trim(),
          ].join(' · '),
        );
        if (releaseRingBirdIds.contains(birdId) && ring.isNotEmpty) {
          await txn.update(
            'birds',
            {'ringNumber': ''},
            where: 'id = ?',
            whereArgs: [birdId],
          );
          await _addBirdEventTxn(
            txn,
            birdId: birdId,
            eventType: 'Ring Removed',
            eventDate: soldAt,
            details: 'Ring $ring removed during sale and released for reuse.',
          );
        }
      }

      final transactionId = 'bird_sale_batch_$batchId';
      final financeNotes = [
        '${items.length} bird${items.length == 1 ? '' : 's'} sold',
        if (buyer?.trim().isNotEmpty == true) 'Buyer: ${buyer!.trim()}',
        if (notes?.trim().isNotEmpty == true) notes!.trim(),
      ].join(' · ');
      await txn.insert('finance_transactions', {
        'id': transactionId,
        'type': 'Income',
        'category': 'Bird Sale',
        'amount': total,
        'date': soldAt.toIso8601String(),
        'notes': financeNotes,
        'birdId': null,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await _addActivityEventTxn(
        txn,
        category: 'Finance',
        eventType: 'Income',
        eventDate: soldAt,
        title: 'Bird Sale',
        details: financeNotes,
        entityType: 'Finance',
        entityId: transactionId,
        amount: total,
        financeType: 'Income',
        sourceKey: 'finance_$transactionId',
      );
      for (final clutchId in clutchIds) {
        await _evaluateClutchClosure(txn, clutchId);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Ring, mutation and bird-name management
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getRingRanges({String? speciesId}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT ringRange.*, species.name AS speciesName
      FROM ring_ranges ringRange
      INNER JOIN species ON species.id = ringRange.speciesId
      WHERE COALESCE(ringRange.active, 1) = 1
        AND (? IS NULL OR ringRange.speciesId = ?)
      ORDER BY species.name COLLATE NOCASE, ringRange.startNumber
    ''', [speciesId, speciesId]);
  }

  Future<void> addRingRange({
    required String speciesId,
    required int startNumber,
    required int endNumber,
    int padding = 3,
  }) async {
    if (startNumber < 0 || endNumber < startNumber) {
      throw StateError('Enter a valid ring range.');
    }
    final db = await database;
    final overlaps = await db.rawQuery('''
      SELECT id FROM ring_ranges
      WHERE speciesId = ? AND COALESCE(active, 1) = 1
        AND NOT (endNumber < ? OR startNumber > ?)
      LIMIT 1
    ''', [speciesId, startNumber, endNumber]);
    if (overlaps.isNotEmpty) {
      throw StateError('This ring range overlaps an existing range.');
    }
    await db.insert('ring_ranges', {
      'id': const Uuid().v4(),
      'speciesId': speciesId,
      'startNumber': startNumber,
      'endNumber': endNumber,
      'padding': padding.clamp(1, 8),
      'active': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteRingRange(String id) async {
    final db = await database;
    await db.delete('ring_ranges', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getRingAssignments(String speciesId) async {
    final ranges = await getRingRanges(speciesId: speciesId);
    if (ranges.isEmpty) return const [];
    final db = await database;
    final assignedRows = await db.rawQuery('''
      SELECT id AS birdId, ringNumber, name, gender, active, saleStatus,
        removalReason
      FROM birds
      WHERE speciesId = ? AND TRIM(COALESCE(ringNumber, '')) <> ''
    ''', [speciesId]);
    final assigned = <String, Map<String, dynamic>>{};
    for (final row in assignedRows) {
      final ring = row['ringNumber'].toString().trim();
      assigned[ring.toLowerCase()] = row;
      final numeric = int.tryParse(ring);
      if (numeric != null) assigned['#numeric:$numeric'] = row;
    }
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final range in ranges) {
      final start = (range['startNumber'] as num).toInt();
      final end = (range['endNumber'] as num).toInt();
      final padding = (range['padding'] as num?)?.toInt() ?? 3;
      for (var number = start; number <= end; number++) {
        final ring = number.toString().padLeft(padding, '0');
        if (!seen.add(ring.toLowerCase())) continue;
        final bird = assigned[ring.toLowerCase()] ?? assigned['#numeric:$number'];
        result.add({
          'ringNumber': ring,
          'allotted': bird == null ? 0 : 1,
          'birdId': bird?['birdId'],
          'birdName': bird?['name'],
          'gender': bird?['gender'] ?? 'Unknown',
          'active': bird?['active'],
          'saleStatus': bird?['saleStatus'],
          'removalReason': bird?['removalReason'],
        });
      }
    }
    return result;
  }

  Future<List<String>> getAvailableRingNumbers(
    String speciesId, {
    String? excludeBirdId,
  }) async {
    final assignments = await getRingAssignments(speciesId);
    String? currentRing;
    if (excludeBirdId != null) {
      final bird = await getBirdById(excludeBirdId);
      if (bird?['speciesId']?.toString() == speciesId) {
        currentRing = bird?['ringNumber']?.toString().trim();
      }
    }
    return assignments
        .where((row) {
          if ((row['allotted'] as num?)?.toInt() == 0) return true;
          return excludeBirdId != null && row['birdId']?.toString() == excludeBirdId;
        })
        .map((row) => row['ringNumber'].toString())
        .followedBy(
          currentRing == null || currentRing.isEmpty
              ? const <String>[]
              : <String>[currentRing],
        )
        .toSet()
        .toList()
      ..sort((a, b) {
        final ai = int.tryParse(a);
        final bi = int.tryParse(b);
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
  }

  Future<List<Map<String, dynamic>>> getManagedBirdValues({
    required String kind,
    String? speciesId,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT valueRow.*, species.name AS speciesName
      FROM managed_bird_values valueRow
      LEFT JOIN species ON species.id = valueRow.speciesId
      WHERE valueRow.kind = ? AND COALESCE(valueRow.active, 1) = 1
        AND (? IS NULL OR valueRow.speciesId IS NULL OR valueRow.speciesId = ?)
      ORDER BY valueRow.value COLLATE NOCASE
    ''', [kind, speciesId, speciesId]);
    final seen = <String>{};
    return rows.where((row) => seen.add(row['value'].toString().toLowerCase())).toList();
  }

  Future<void> addManagedBirdValue({
    required String kind,
    required String value,
    String? speciesId,
  }) async {
    final clean = value.trim();
    if (clean.isEmpty) throw StateError('Value cannot be empty.');
    final db = await database;
    final duplicate = await db.rawQuery('''
      SELECT id FROM managed_bird_values
      WHERE kind = ?
        AND ((speciesId = ?) OR (speciesId IS NULL AND ? IS NULL))
        AND value = ? COLLATE NOCASE
      LIMIT 1
    ''', [kind, speciesId, speciesId, clean]);
    if (duplicate.isNotEmpty) throw StateError('$clean already exists.');
    await db.insert('managed_bird_values', {
      'id': const Uuid().v4(),
      'kind': kind,
      'speciesId': speciesId,
      'value': clean,
      'active': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteManagedBirdValue(String id) async {
    final db = await database;
    await db.delete('managed_bird_values', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getPreviousBirdCount() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM birds WHERE COALESCE(active, 1) = 0',
        )) ??
        0;
  }

  Future<List<Map<String, dynamic>>> getChicksWithParents() async {
    final db = await database;
    return db.rawQuery('''
      SELECT chick.*, species.name AS speciesName,
        cage.identifier AS cageIdentifier,
        pair.identifier AS parentPairIdentifier,
        male.ringNumber AS fatherRingNumber,
        male.name AS fatherName,
        female.ringNumber AS motherRingNumber,
        female.name AS motherName
      FROM birds chick
      LEFT JOIN species ON species.id = chick.speciesId
      LEFT JOIN cages cage ON cage.id = chick.cageId
      LEFT JOIN pairs pair ON pair.id = chick.parentPairId
      LEFT JOIN birds male ON male.id = pair.maleBirdId
      LEFT JOIN birds female ON female.id = pair.femaleBirdId
      WHERE COALESCE(chick.active, 1) = 1
        AND chick.nestClutchId IS NOT NULL
        AND chick.leftNestDate IS NULL
      ORDER BY COALESCE(pair.identifier, ''),
        COALESCE(chick.hatchDate, chick.createdAt),
        chick.ringNumber COLLATE NOCASE
    ''');
  }

  // ---------------------------------------------------------------------------
  // Search and lookup
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> getCageById(String cageId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT cage.*,
        (SELECT COUNT(*) FROM birds bird
          WHERE bird.cageId = cage.id
            AND COALESCE(bird.active, 1) = 1) AS birdCount,
        (SELECT COUNT(*) FROM cages merged
          WHERE merged.mergedIntoId = cage.id
            AND COALESCE(merged.active, 1) = 1) AS mergedCount
      FROM cages cage
      WHERE cage.id = ?
      LIMIT 1
    ''', [cageId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getPairSessions(String pairId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT session.*, cage.identifier AS cageIdentifier
      FROM pair_sessions session
      LEFT JOIN cages cage ON cage.id = session.cageId
      WHERE session.pairId = ?
      ORDER BY session.startedAt DESC, session.id DESC
    ''', [pairId]);
  }

  Future<List<Map<String, dynamic>>> getOffspringForPair(
    String pairId,
  ) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        bird.*,
        species.name AS speciesName,
        species.chickToYoungDays,
        species.adultAgeMonths,
        cage.identifier AS cageIdentifier,
        CASE
          WHEN COALESCE(bird.active, 1) = 1 THEN 'Present'
          WHEN LOWER(COALESCE(bird.removalReason, '')) = 'died' THEN 'Deceased'
          WHEN LOWER(COALESCE(bird.removalReason, '')) = 'sold'
            OR bird.saleStatus = 'Sold' THEN 'Sold'
          ELSE 'Removed'
        END AS currentStatus
      FROM birds bird
      LEFT JOIN species species ON species.id = bird.speciesId
      LEFT JOIN cages cage ON cage.id = bird.cageId
      WHERE bird.parentPairId = ?
      ORDER BY
        CASE WHEN COALESCE(bird.active, 1) = 1 THEN 0 ELSE 1 END,
        COALESCE(bird.hatchDate, bird.sourceDate, bird.createdAt) DESC,
        bird.ringNumber COLLATE NOCASE ASC
    ''', [pairId]);
  }

  Future<int> getSpeciesBirdCount(String speciesId) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM birds WHERE speciesId = ?',
          [speciesId],
        )) ??
        0;
  }

  Future<void> deleteSpeciesCompletely(String speciesId) async {
    if (speciesId == 'cockatiel' || speciesId == 'ringneck') {
      throw StateError('Default species cannot be deleted. You can deactivate them.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final birdCount = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM birds WHERE speciesId = ?',
            [speciesId],
          )) ??
          0;
      if (birdCount > 0) {
        throw StateError(
          'This species is used by $birdCount bird record(s). Correct or delete those bird records first.',
        );
      }
      await txn.delete('species', where: 'id = ?', whereArgs: [speciesId]);
    });
  }

  Future<List<Map<String, dynamic>>> getAllSpecies() async {
    final db = await database;
    return db.query('species', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<void> setSpeciesActive(String speciesId, bool active) async {
    final db = await database;
    await db.update(
      'species',
      {'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [speciesId],
    );
  }

  Future<List<Map<String, dynamic>>> globalSearch(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final db = await database;
    final like = '%$term%';
    final results = <Map<String, dynamic>>[];

    final birds = await db.rawQuery('''
      SELECT
        bird.id,
        bird.ringNumber,
        bird.name,
        bird.notes,
        bird.mutation,
        bird.gender,
        species.name AS speciesName,
        cage.identifier AS cageIdentifier
      FROM birds bird
      LEFT JOIN species species ON species.id = bird.speciesId
      LEFT JOIN cages cage ON cage.id = bird.cageId
      WHERE bird.ringNumber LIKE ? COLLATE NOCASE
         OR COALESCE(bird.name, '') LIKE ? COLLATE NOCASE
         OR COALESCE(bird.notes, '') LIKE ? COLLATE NOCASE
         OR COALESCE(bird.mutation, '') LIKE ? COLLATE NOCASE
         OR COALESCE(species.name, '') LIKE ? COLLATE NOCASE
         OR COALESCE(cage.identifier, '') LIKE ? COLLATE NOCASE
      LIMIT 40
    ''', [like, like, like, like, like, like]);
    for (final bird in birds) {
      final ring = bird['ringNumber']?.toString() ?? 'Bird';
      final name = bird['name']?.toString().trim() ?? '';
      results.add({
        'type': 'Bird',
        'id': bird['id'],
        'title': name.isEmpty ? ring : '$ring — $name',
        'subtitle': '${bird['speciesName'] ?? 'Unknown species'} · Cage ${bird['cageIdentifier'] ?? 'None'}',
        'gender': bird['gender'],
        'notes': bird['notes'],
      });
    }

    final cages = await db.rawQuery('''
      SELECT * FROM cages
      WHERE identifier LIKE ? COLLATE NOCASE
         OR COALESCE(location, '') LIKE ? COLLATE NOCASE
         OR COALESCE(type, '') LIKE ? COLLATE NOCASE
         OR COALESCE(notes, '') LIKE ? COLLATE NOCASE
      LIMIT 30
    ''', [like, like, like, like]);
    for (final cage in cages) {
      results.add({
        'type': 'Cage',
        'id': cage['id'],
        'title': cage['identifier'],
        'subtitle': '${cage['type'] ?? ''} · ${cage['location'] ?? ''}',
        'notes': cage['notes'],
      });
    }

    final pairs = await db.rawQuery('''
      SELECT
        pair.id,
        pair.identifier,
        pair.notes,
        male.ringNumber AS maleRingNumber,
        male.name AS maleName,
        male.gender AS maleGender,
        female.ringNumber AS femaleRingNumber,
        female.name AS femaleName,
        female.gender AS femaleGender,
        cage.identifier AS cageIdentifier
      FROM pairs pair
      INNER JOIN birds male ON male.id = pair.maleBirdId
      INNER JOIN birds female ON female.id = pair.femaleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      WHERE COALESCE(pair.identifier, '') LIKE ? COLLATE NOCASE
         OR COALESCE(pair.notes, '') LIKE ? COLLATE NOCASE
         OR male.ringNumber LIKE ? COLLATE NOCASE
         OR COALESCE(male.name, '') LIKE ? COLLATE NOCASE
         OR female.ringNumber LIKE ? COLLATE NOCASE
         OR COALESCE(female.name, '') LIKE ? COLLATE NOCASE
         OR COALESCE(cage.identifier, '') LIKE ? COLLATE NOCASE
      LIMIT 30
    ''', [like, like, like, like, like, like, like]);
    for (final pair in pairs) {
      results.add({
        'type': 'Pair',
        'id': pair['id'],
        'title': '${pair['cageIdentifier'] ?? 'No cage'} — ${pair['identifier'] ?? 'Pair'}',
        'subtitle': '${pair['maleRingNumber']} × ${pair['femaleRingNumber']}',
        'maleRingNumber': pair['maleRingNumber'],
        'maleGender': pair['maleGender'],
        'femaleRingNumber': pair['femaleRingNumber'],
        'femaleGender': pair['femaleGender'],
        'notes': pair['notes'],
      });
    }

    final clutches = await db.rawQuery('''
      SELECT
        clutch.id,
        clutch.clutchNumber,
        clutch.notes,
        pair.identifier AS pairIdentifier,
        cage.identifier AS cageIdentifier
      FROM clutches clutch
      INNER JOIN pairs pair ON pair.id = clutch.pairId
      INNER JOIN birds male ON male.id = pair.maleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      WHERE CAST(clutch.clutchNumber AS TEXT) LIKE ?
         OR COALESCE(clutch.notes, '') LIKE ? COLLATE NOCASE
         OR COALESCE(pair.identifier, '') LIKE ? COLLATE NOCASE
         OR COALESCE(cage.identifier, '') LIKE ? COLLATE NOCASE
      LIMIT 30
    ''', [like, like, like, like]);
    for (final clutch in clutches) {
      results.add({
        'type': 'Clutch',
        'id': clutch['id'],
        'title': '${clutch['cageIdentifier'] ?? 'No cage'} — ${clutch['pairIdentifier'] ?? 'Pair'} — Clutch ${clutch['clutchNumber']}',
        'subtitle': 'Breeding clutch',
        'notes': clutch['notes'],
      });
    }

    final eggs = await db.rawQuery('''
      SELECT
        egg.id,
        egg.clutchId,
        egg.eggNumber,
        egg.status,
        egg.notes,
        clutch.clutchNumber,
        pair.identifier AS pairIdentifier,
        cage.identifier AS cageIdentifier
      FROM eggs egg
      INNER JOIN clutches clutch ON clutch.id = egg.clutchId
      INNER JOIN pairs pair ON pair.id = clutch.pairId
      INNER JOIN birds male ON male.id = pair.maleBirdId
      LEFT JOIN cages cage ON cage.id = male.cageId
      WHERE COALESCE(egg.notes, '') LIKE ? COLLATE NOCASE
         OR egg.status LIKE ? COLLATE NOCASE
      LIMIT 30
    ''', [like, like]);
    for (final egg in eggs) {
      results.add({
        'type': 'Egg',
        'id': egg['id'],
        'targetId': egg['clutchId'],
        'title': '${egg['cageIdentifier'] ?? 'No cage'} — ${egg['pairIdentifier'] ?? 'Pair'} — Egg ${egg['eggNumber']}',
        'subtitle': '${egg['status']} · Clutch ${egg['clutchNumber']}',
        'notes': egg['notes'],
      });
    }

    return results;
  }

  Future<String> getDatabaseFilePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'aviarypro.db');
  }

  Future<String> createTemporaryBackupPath({
    String prefix = 'snapshot',
  }) async {
    final dbPath = await getDatabasesPath();
    final directory = Directory(join(dbPath, 'aviarypro_backup_temp'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return join(
      directory.path,
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}.db',
    );
  }

  Future<String> createBackupSnapshot() async {
    final targetPath = await createTemporaryBackupPath();
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }

    final db = await database;
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');

    try {
      final escapedPath = targetPath.replaceAll("'", "''");
      await db.execute("VACUUM INTO '$escapedPath'");
    } catch (_) {
      // Older Android SQLite builds may not support VACUUM INTO. After a full
      // WAL checkpoint, briefly close the connection and copy the main file.
      final sourcePath = await getDatabaseFilePath();
      await db.close();
      _database = null;
      try {
        await File(sourcePath).copy(targetPath);
      } finally {
        await database;
      }
    }

    if (!await target.exists() || await target.length() == 0) {
      throw StateError('Could not create a database backup snapshot.');
    }
    return target.path;
  }

  Future<int> getSchemaVersion() async {
    final db = await database;
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) return 0;
    return (rows.first.values.first as num?)?.toInt() ?? 0;
  }

  Future<DateTime?> getDatabaseModifiedAt() async {
    final path = await getDatabaseFilePath();
    final file = File(path);
    if (!await file.exists()) return null;
    return (await file.stat()).modified;
  }

  Future<bool> hasUserData() async {
    final db = await database;
    const tables = <String>[
      'birds',
      'cages',
      'pairs',
      'clutches',
      'eggs',
      'finance_transactions',
    ];

    for (final table in tables) {
      try {
        final count = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $table'),
            ) ??
            0;
        if (count > 0) return true;
      } catch (_) {
        // A table may not exist in an old database. Continue checking.
      }
    }
    return false;
  }

  Future<void> restoreDatabaseFromSnapshot(String snapshotPath) async {
    final snapshot = File(snapshotPath);
    if (!await snapshot.exists() || await snapshot.length() == 0) {
      throw ArgumentError('The selected backup file is empty or missing.');
    }

    Database? validationDb;
    try {
      validationDb = await openDatabase(
        snapshotPath,
        readOnly: true,
        singleInstance: false,
      );
      final integrity = await validationDb.rawQuery('PRAGMA integrity_check');
      final result = integrity.isEmpty
          ? ''
          : integrity.first.values.first.toString().toLowerCase();
      if (result != 'ok') {
        throw StateError('The selected backup failed its integrity check.');
      }
      final requiredTable = await validationDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'birds'",
      );
      if (requiredTable.isEmpty) {
        throw StateError('This file is not an Aviary Pro database backup.');
      }
    } finally {
      await validationDb?.close();
    }

    final destinationPath = await getDatabaseFilePath();
    final destination = File(destinationPath);

    await _database?.close();
    _database = null;

    for (final suffix in const <String>['', '-wal', '-shm', '-journal']) {
      final file = File('$destinationPath$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }

    await snapshot.copy(destination.path);

    // Reopen immediately so schema upgrades and foreign-key configuration are
    // applied before the UI reads restored records.
    await database;
  }

}
