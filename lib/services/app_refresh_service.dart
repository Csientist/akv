import 'dart:async';
import '../core/logger.dart';
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

  static const interval = Duration(seconds: 60);

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

  /// Immediately fire a refresh tick — call after any write operation
  /// (save sale, record payment, add animal, etc.) so all subscribed
  /// screens update without waiting for the next 60s interval.
  void nudge() {
    Log.i('[AppRefresh] Nudged.');
    _tick();
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
    // Notify UI screens immediately so they reload from local SQLite.
    // Sync runs independently in the background — screens will get another
    // tick on the next interval with freshly pulled data.
    _controller.add(null);
    // Fire-and-forget — unawaited intentionally. fullSync is a no-op if
    // already running.
    SyncService().fullSync().catchError((e) {
      Log.e('[AppRefresh] Background sync error: $e');
    });
  }
}