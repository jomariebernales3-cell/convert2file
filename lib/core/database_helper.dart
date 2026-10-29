import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smart_template.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE users ADD COLUMN bio TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN phone TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN location TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN profile_image_path TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE users ADD COLUMN supabase_user_id TEXT');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_supabase_user_id ON users(supabase_user_id)',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE bug_reports ADD COLUMN complaint_mode TEXT DEFAULT "direct"',
      );
      await db.execute(
        'ALTER TABLE bug_reports ADD COLUMN attachments_json TEXT',
      );
    }
    if (oldVersion < 5) {
      await _createStudySetsTable(db);
    }
    if (oldVersion < 6) {
      // The former local-only seed accounts are no longer administrators.
      // Administrator access is now restricted to the Supabase admin account.
      await db.execute(
        "UPDATE users SET role = 'user' WHERE email IN ('admin@smarttemplate.app', 'dbzadmin@fconvert')",
      );
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // Users Table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supabase_user_id TEXT UNIQUE,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'user',
        status TEXT NOT NULL DEFAULT 'active',
        bio TEXT,
        phone TEXT,
        location TEXT,
        profile_image_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Files Table
    await db.execute('''
      CREATE TABLE files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        source_file_id INTEGER,
        kind TEXT NOT NULL,
        original_name TEXT NOT NULL,
        stored_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        extension TEXT NOT NULL,
        path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        metadata_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Templates Table
    await db.execute('''
      CREATE TABLE templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        file_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        structure_json TEXT NOT NULL,
        placeholders_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Logs Table
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        level TEXT NOT NULL DEFAULT 'info',
        event_type TEXT NOT NULL,
        message TEXT NOT NULL,
        context_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Bug Reports Table
    await db.execute('''
      CREATE TABLE bug_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        reporter_name TEXT NOT NULL,
        reporter_email TEXT NOT NULL,
        subject TEXT NOT NULL,
        message TEXT NOT NULL,
        screenshot_path TEXT,
        screenshot_name TEXT,
        complaint_mode TEXT NOT NULL DEFAULT 'direct',
        attachments_json TEXT,
        status TEXT NOT NULL DEFAULT 'new',
        created_at TEXT NOT NULL
      )
    ''');

    // Offline Queue Table
    await db.execute('''
      CREATE TABLE offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        retries INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await _createStudySetsTable(db);

    // Legacy local records. These are regular users; Supabase controls the
    // actual administrator identity.
    await db.execute('''
      INSERT INTO users (name, email, password_hash, role, status, created_at, updated_at)
      VALUES ('System Administrator', 'admin@smarttemplate.app', '\$2y\$10\$JZPnZAe36pGH9GLlmYS.MO4nPzeQM04kQTuDXRcZT/9oVWb1Rp5Sy', 'user', 'active', datetime('now'), datetime('now'))
    ''');

    // Legacy local record.
    await db.execute('''
      INSERT INTO users (name, email, password_hash, role, status, created_at, updated_at)
      VALUES ('DBZ Admin', 'dbzadmin@fconvert', '\$2y\$10\$v1Qm4JfZgXvH5jY0bYx8pGxE2z8nXG7wq6oGxgqkGfYv9r0tGJt7u', 'user', 'active', datetime('now'), datetime('now'))
    ''');
  }

  Future<void> _createStudySetsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        questions_json TEXT NOT NULL,
        last_score INTEGER,
        last_total INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // Users
  Future<int> insertUser(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('users', row);
  }

  Future<int> upsertUser(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final supabaseUserId = row['supabase_user_id'] as String?;
    Map<String, dynamic>? existing;

    if (supabaseUserId != null && supabaseUserId.isNotEmpty) {
      existing = await getUserBySupabaseId(supabaseUserId);
    }
    existing ??= await getUserByEmail(row['email'] as String);

    if (existing == null) {
      return await db.insert('users', row);
    }

    await db.update(
      'users',
      {
        ...row,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [existing['id']],
    );

    return existing['id'] as int;
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    Database db = await instance.database;
    final results =
        await db.query('users', where: 'email = ?', whereArgs: [email]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getUserById(int id) async {
    Database db = await instance.database;
    final results = await db.query('users', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getUserBySupabaseId(
      String supabaseUserId) async {
    Database db = await instance.database;
    final results = await db.query(
      'users',
      where: 'supabase_user_id = ?',
      whereArgs: [supabaseUserId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> getOrCreateGuestUserId() async {
    const email = 'guest@convert2file.local';
    final existing = await getUserByEmail(email);
    if (existing != null) return existing['id'] as int;

    final now = DateTime.now().toIso8601String();
    return await insertUser({
      'name': 'Guest User',
      'email': email,
      'password_hash': 'local-guest',
      'role': 'user',
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> queryAllUsers() async {
    Database db = await instance.database;
    return await db.query(
      'users',
      where: 'email != ?',
      whereArgs: ['guest@convert2file.local'],
      orderBy: 'id DESC',
    );
  }

  Future<List<Map<String, dynamic>>> queryUsersByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    Database db = await instance.database;
    return await db.query(
      'users',
      where: 'id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
      orderBy: 'id DESC',
    );
  }

  Future<int> updateUserProfile(int id, Map<String, dynamic> values) async {
    Database db = await instance.database;
    return await db.update(
      'users',
      {
        ...values,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Files
  Future<int> insertFile(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('files', row);
  }

  Future<List<Map<String, dynamic>>> queryAllFiles() async {
    Database db = await instance.database;
    return await db.query('files', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> queryFilesByUser(int userId) async {
    Database db = await instance.database;
    return await db.query('files',
        where: 'user_id = ?', orderBy: 'id DESC', whereArgs: [userId]);
  }

  Future<List<Map<String, dynamic>>> queryFilesByKind(String kind) async {
    Database db = await instance.database;
    return await db.query('files',
        where: 'kind = ?', orderBy: 'id DESC', whereArgs: [kind]);
  }

  Future<int> deleteFile(int id) async {
    Database db = await instance.database;
    return await db.delete('files', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteFilesByIds(List<int> ids) async {
    Database db = await instance.database;
    return await db.delete(
      'files',
      where: 'id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<int> deleteFilesByDateRange(String startIso, String endIso) async {
    Database db = await instance.database;
    return await db.delete(
      'files',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [startIso, endIso],
    );
  }

  Future<int> deleteAllFiles() async {
    Database db = await instance.database;
    return await db.delete('files');
  }

  // Templates
  Future<int> insertTemplate(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('templates', row);
  }

  Future<List<Map<String, dynamic>>> queryAllTemplates() async {
    Database db = await instance.database;
    return await db.query('templates', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> queryTemplatesByUser(int userId) async {
    Database db = await instance.database;
    return await db.query('templates',
        where: 'user_id = ?', orderBy: 'id DESC', whereArgs: [userId]);
  }

  Future<Map<String, dynamic>?> getTemplateById(int id) async {
    Database db = await instance.database;
    final results =
        await db.query('templates', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  // Logs
  Future<int> insertLog(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('logs', row);
  }

  Future<List<Map<String, dynamic>>> queryAllLogs() async {
    Database db = await instance.database;
    return await db.query('logs', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> queryLogsByLevel(String level) async {
    Database db = await instance.database;
    return await db.query('logs',
        where: 'level = ?', orderBy: 'id DESC', whereArgs: [level]);
  }

  Future<List<Map<String, dynamic>>> queryLogsByUser(int userId) async {
    Database db = await instance.database;
    return await db.query('logs',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC');
  }

  // Bug Reports
  Future<int> insertBugReport(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('bug_reports', row);
  }

  Future<List<Map<String, dynamic>>> queryAllBugReports() async {
    Database db = await instance.database;
    return await db.query('bug_reports', orderBy: 'id DESC');
  }

  Future<int> updateBugReportStatus(int id, String status) async {
    Database db = await instance.database;
    return await db.update('bug_reports', {'status': status},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateBugReportAttachments(int id, String attachmentsJson) async {
    Database db = await instance.database;
    return await db.update('bug_reports', {'attachments_json': attachmentsJson},
        where: 'id = ?', whereArgs: [id]);
  }

  // Offline Queue
  Future<int> insertQueueItem(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('offline_queue', row);
  }

  Future<List<Map<String, dynamic>>> queryPendingQueueItems() async {
    Database db = await instance.database;
    return await db.query('offline_queue',
        where: 'status = ?', orderBy: 'timestamp ASC', whereArgs: ['pending']);
  }

  Future<int> updateQueueItemStatus(int id, String status, int retries) async {
    Database db = await instance.database;
    return await db.update(
        'offline_queue', {'status': status, 'retries': retries},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteQueueItem(int id) async {
    Database db = await instance.database;
    return await db.delete('offline_queue', where: 'id = ?', whereArgs: [id]);
  }

  // Stats
  Future<int> countFiles() async {
    Database db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM files');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countTemplates() async {
    Database db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM templates');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countUsers() async {
    Database db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countBugReports() async {
    Database db = await instance.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM bug_reports');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countLogsByLevel(String level) async {
    Database db = await instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM logs WHERE level = ?', [level]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> updateUserStatus(int id, String status) async {
    Database db = await instance.database;
    return await db.update(
      'users',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteUser(int id) async {
    Database db = await instance.database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // Study Sets
  Future<int> insertStudySet(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('study_sets', row);
  }

  Future<int> updateStudySet(int id, Map<String, dynamic> values) async {
    Database db = await instance.database;
    return await db.update(
      'study_sets',
      {
        ...values,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> queryStudySetsByUser(int userId) async {
    Database db = await instance.database;
    return await db.query(
      'study_sets',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
    );
  }

  Future<int> deleteStudySet(int id) async {
    Database db = await instance.database;
    return await db.delete('study_sets', where: 'id = ?', whereArgs: [id]);
  }
}
