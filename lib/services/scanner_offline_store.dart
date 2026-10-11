import 'package:sqflite/sqflite.dart';

class ScannerOfflineStore {
  ScannerOfflineStore({DatabaseFactory? factory, String? path})
      : factory = factory ?? databaseFactory, path = path;
  final DatabaseFactory factory;
  final String? path;
  Database? _database;

  Future<Database> database() async {
    if (_database != null) return _database!;
    final location = path ?? '${await factory.getDatabasesPath()}/tiketix-scanner-offline.db';
    _database = await factory.openDatabase(location, options: OpenDatabaseOptions(version: 1,
      onConfigure: (db) async { await db.execute('PRAGMA synchronous = FULL'); },
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE encrypted_state (id INTEGER PRIMARY KEY CHECK (id = 1), value TEXT NOT NULL)');
      },
    ));
    return _database!;
  }

  Future<String?> read() async {
    final rows = await (await database()).query('encrypted_state', where: 'id = ?', whereArgs: [1]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> write(String encrypted) async {
    await (await database()).transaction((transaction) async {
      await transaction.insert('encrypted_state', {'id': 1, 'value': encrypted}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
