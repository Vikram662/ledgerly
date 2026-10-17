import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app/app.dart';
import 'core/backup/backup_scheduler.dart';
import 'core/db/database.dart';
import 'core/db/enums.dart';
import 'core/db/providers.dart';
import 'core/i18n/i18n.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await loadAppLanguage();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await BackupScheduler().initialize();
  } catch (_) {
    // Background backup unavailable; foreground triggers still run.
  }
  final db = AppDatabase();
  final profile = await db.select(db.businessProfiles).getSingleOrNull();
  runApp(AppRoot(
    database: db,
    needsOnboarding: profile == null,
    userType: profile?.userType ?? UserType.contractor,
  ));
}

/// Owns the open database. A restore closes it, swaps the file and rebuilds
/// the whole app on the new data (PRD D6).
class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.database,
    required this.needsOnboarding,
    required this.userType,
  });

  final AppDatabase database;
  final bool needsOnboarding;
  final UserType userType;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late AppDatabase _db = widget.database;
  late bool _needsOnboarding = widget.needsOnboarding;
  late UserType _userType = widget.userType;
  int _generation = 0;

  Future<void> _replaceDatabase(
    Future<void> Function(String dbPath) write,
    Future<void> Function(AppDatabase db) afterOpen,
  ) async {
    await _db.close();
    try {
      await write(await databaseFilePath());
    } finally {
      _db = AppDatabase();
    }
    await afterOpen(_db);
    final profile = await _db.select(_db.businessProfiles).getSingleOrNull();
    setState(() {
      _needsOnboarding = profile == null;
      _userType = profile?.userType ?? UserType.contractor;
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey(_generation),
      overrides: [
        databaseProvider.overrideWithValue(_db),
        databaseReplacerProvider.overrideWithValue(_replaceDatabase),
      ],
      child: ThekedaarApp(
        needsOnboarding: _needsOnboarding,
        userType: _userType,
      ),
    );
  }
}
