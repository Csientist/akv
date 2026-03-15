import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io'; // To check the platform
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/logger.dart';


// SQLite Desktop Support
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── Core & Services Imports ──────────────────────────────────────────────────
import 'core/appwrite_client.dart'; 
import 'core/local_db.dart';        
import 'services/sync_service.dart';

// ── Feature Screen Imports ───────────────────────────────────────────────────
import 'features/sales/new_sales_screen.dart'; 
import 'features/herd/herd_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/auth/auth_gate.dart';

void main() async {
  // 1. Ensure Flutter binding is ready before calling native code
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize desktop SQLite ONLY if we are NOT on the web
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 2. Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 3. Set a clean, modern status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // 4. Pre-warm the database
  try {
    Log.i('[Boot] Initializing Local Database...');
    await LocalDb.instance.database; 
    Log.i('[Boot] Database ready.');
  } catch (e) {
    Log.e('[Boot] Fatal DB Error: $e');
  }

  // 5. Initialize Appwrite & Background Sync
  try {
    AppwriteClient.instance.init();
    SyncService().listenForConnectivity();
    Log.i('[Boot] Appwrite & Sync Service initialized.');
  } catch (e) {
    Log.i('[Boot] Backend init failed (Offline mode active): $e');
  }

  // 6. Run the App
  runApp(const FarmApp());
}

// ── Root Application ─────────────────────────────────────────────────────────

class FarmApp extends StatelessWidget {
  const FarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Farm Manager',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const AuthGate(child: AppShell()),
    );
  }

  ThemeData _buildTheme() {
    const seedGreen = Color(0xFF2D6A4F);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedGreen,
        brightness: Brightness.light,
        primary: seedGreen,
        secondary: const Color(0xFF52B788),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF7FAF8),
      fontFamily: 'DMSans', 
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1.0),
        headlineMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontWeight: FontWeight.w500, height: 1.5),
        labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8E8E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8E8E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE63946)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD8E8E0)),
        ),
      ),
    );
  }
}

// ── Bottom Navigation Shell ──────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final List<_NavItem> _navItems = const [
    _NavItem(label: 'Dashboard', icon: Icons.bar_chart_outlined,     activeIcon: Icons.bar_chart),
    _NavItem(label: 'Sales',     icon: Icons.receipt_long_outlined,  activeIcon: Icons.receipt_long),
    _NavItem(label: 'Herd',      icon: Icons.pets_outlined,          activeIcon: Icons.pets),
    _NavItem(label: 'Inventory', icon: Icons.inventory_2_outlined,   activeIcon: Icons.inventory_2),
  ];

  final List<Widget> _screens = [
    const DashboardScreen(),
    const NewSaleScreen(),
    const HerdManagementScreen(),
    const InventoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: 0.04))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          // Removed rigid height constraint. Using padding for dynamic sizing.
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              children: List.generate(_navItems.length, (i) {
                final item = _navItems[i];
                final selected = i == _currentIndex;
                return Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _currentIndex = i),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min, // Allows Column to shrink-wrap its children
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut, // Fixed: Swapped easeOutBack to easeOut to prevent negative width crash
                            height: 3,
                            width: selected ? 24 : 0,
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Icon(
                            selected ? item.activeIcon : item.icon,
                            color: selected ? scheme.primary : Colors.grey[400],
                            size: 24,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? scheme.primary : Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem({required this.label, required this.icon, required this.activeIcon});
}