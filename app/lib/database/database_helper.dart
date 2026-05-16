import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('jarvis.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE routines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        scheduled_time TEXT,
        enabled INTEGER DEFAULT 1,
        order_index INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        routine_id INTEGER,
        status TEXT DEFAULT 'pending',
        notes TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT DEFAULT 'pending',
        priority INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        gym_score REAL DEFAULT 0,
        timing_score REAL DEFAULT 0,
        task_score REAL DEFAULT 0,
        food_score REAL DEFAULT 0,
        overall_score REAL DEFAULT 0,
        summary TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        name TEXT NOT NULL,
        value REAL,
        unit TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        routine_slot TEXT,
        content TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await _seedDefaultRoutines(db);
  }

  Future<void> _seedDefaultRoutines(Database db) async {
    final routines = [
      {'name': 'wakeup', 'scheduled_time': '05:00', 'order_index': 1},
      {'name': 'post_gym', 'scheduled_time': '07:00', 'order_index': 2},
      {'name': 'morning_office', 'scheduled_time': '09:00', 'order_index': 3},
      {'name': 'lunch', 'scheduled_time': '12:00', 'order_index': 4},
      {'name': 'afternoon', 'scheduled_time': '15:00', 'order_index': 5},
      {'name': 'evening_code', 'scheduled_time': '18:00', 'order_index': 6},
      {'name': 'night_review', 'scheduled_time': '21:00', 'order_index': 7},
    ];
    for (final r in routines) {
      await db.insert('routines', r);
    }
  }

  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return db.insert(table, data);
  }

  Future<int> update(String table, Map<String, dynamic> data, int id) async {
    final db = await database;
    return db.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String table, int id) async {
    final db = await database;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> query(String table,
      {String? where, List<dynamic>? whereArgs, String? orderBy}) async {
    final db = await database;
    return db.query(table,
        where: where, whereArgs: whereArgs, orderBy: orderBy);
  }

  Future<Map<String, dynamic>?> getScore(String date) async {
    final db = await database;
    final results =
        await db.query('scores', where: 'date = ?', whereArgs: [date]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getLogsForDate(String date) async {
    final db = await database;
    return db.query('daily_logs', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<Map<String, dynamic>>> getTasksForDate(String date) async {
    final db = await database;
    return db.query('tasks',
        where: 'date = ?', whereArgs: [date], orderBy: 'priority DESC');
  }

  Future<List<Map<String, dynamic>>> getScoreRange(
      String startDate, String endDate) async {
    final db = await database;
    return db.query('scores',
        where: 'date BETWEEN ? AND ?',
        whereArgs: [startDate, endDate],
        orderBy: 'date ASC');
  }

  Future<List<Map<String, dynamic>>> getAllScores() async {
    final db = await database;
    return db.query('scores', orderBy: 'date DESC', limit: 30);
  }

  Future<List<Map<String, dynamic>>> getMetricsForDate(String date) async {
    final db = await database;
    return db.query('metrics', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<Map<String, dynamic>>> getAllRoutines() async {
    final db = await database;
    return db.query('routines', orderBy: 'order_index ASC');
  }

  Future<void> upsertScore(Map<String, dynamic> data) async {
    final db = await database;
    final existing = await db.query('scores',
        where: 'date = ?', whereArgs: [data['date']]);
    if (existing.isNotEmpty) {
      await db.update('scores', data,
          where: 'date = ?', whereArgs: [data['date']]);
    } else {
      await db.insert('scores', data);
    }
  }

  Future<Map<String, dynamic>?> getTask(int id) async {
    final db = await database;
    final results =
        await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getMonthlyScores(
      int year, int month) async {
    final db = await database;
    final startDate = '$year-${month.toString().padLeft(2, '0')}-01';
    final endDate = month == 12
        ? '${year + 1}-01-01'
        : '$year-${(month + 1).toString().padLeft(2, '0')}-01';
    return db.query('scores',
        where: 'date >= ? AND date < ?',
        whereArgs: [startDate, endDate],
        orderBy: 'date ASC');
  }
}
