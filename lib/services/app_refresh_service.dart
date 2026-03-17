import 'dart:async';
import '../core/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'image_service.dart';
import 'sync_service.dart';

/// Broadcasts a refresh tick every [interval] and on app foreground resume.
/// Screens subscribe to [ticks] and call their own _load() in response.
///
/// Usage:
///   AppRefreshService.instance.start();   // call once after login
///   AppRefreshService.instance.stop();    // call on logout
///
/// In a StatefulWidget:
///   StreamSubscription? _sub;
///   void initState() {
///     super.initState();
///     WidgetsBinding.instance.addPostFrameCallback((_) {
///       if (!mounted) return;
///       _sub = AppRefreshService.instance.ticks.listen((_) {
///         if (mounted) _load();
///       });
///     });
///   }
///   void dispose() { _sub?.cancel(); super.dispose(); }

class AppRefreshService with WidgetsBindingObserver {
  static final AppRefreshService instance = AppRefreshService._internal();
  AppRefreshService._internal();

  static const interval = Duration(seconds: 1000);

  final _controller = StreamController<void>.broadcast();
  Stream<void> get ticks => _controller.stream;

  Timer? _timer;
  bool   _started = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    // Evict stale cache files on startup — fire-and-forget
    ImageService.instance.evictExpiredCache();
    Log.i('[AppRefresh] Started — ticking every ${interval.inSeconds}s.');
    // Immediate tick so all screens load data right after unlock
    // rather than waiting up to [interval] seconds for the first timer fire.
    _tick();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    Log.w('[AppRefresh] Stopped.');
  }

  void dispose() {
    stop();
    _controller.close();
  }

  // ── App lifecycle — fire on foreground resume ──────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Log.i('[AppRefresh] App resumed — firing refresh tick.');
      _tick();
      // Reset timer so the next periodic tick is a full interval away
      _restartTimer();
    }
  }

  /// Fire an immediate UI refresh after a write operation.
  /// Screens reload the just-written record from local SQLite instantly.
  /// Sync to Appwrite is handled by the queue — no need to trigger a full
  /// sync on every write, which adds latency for no benefit.
  void nudge() {
    Log.i('[AppRefresh] Nudged.');
    if (!_controller.isClosed) _controller.add(null);
    _restartTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void _restartTimer() {
    _timer?.cancel();
    _startTimer();
  }

  void _tick() {
    if (_controller.isClosed) return;
    // Broadcast immediately — screens reload from local SQLite right away.
    _controller.add(null);
    // Pre-flight connectivity check before attempting any network calls.
    // If offline: skip sync entirely, saving all API call overhead.
    // If online: run full sync, then broadcast again with fresh data.
    Connectivity().checkConnectivity().then((results) {
      if (results.contains(ConnectivityResult.none)) {
        Log.i('[AppRefresh] Offline — skipping sync on this tick.');
        return;
      }
      SyncService().fullSync().then((_) {
        if (!_controller.isClosed) _controller.add(null);
      }).catchError((e) {
        Log.e('[AppRefresh] Background sync error: $e');
      });
    });
  }
}