import 'dart:io';
import '../core/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/local_db.dart';

/// Supported entity types that can own images.
enum ImageEntityType { asset, assetEvent }

extension ImageEntityTypeX on ImageEntityType {
  String get value => switch (this) {
        ImageEntityType.asset      => 'asset',
        ImageEntityType.assetEvent => 'asset_event',
      };
}

/// Upload status for an image row.
enum ImageUploadStatus { pending, uploaded }

/// A single image record as returned from SQLite.
class FarmImage {
  final String   imageId;
  final String   entityType;
  final String   entityId;
  final int      sortOrder;
  final String?  localPath;      // null if cache evicted
  final String?  appwriteFileId; // null until uploaded
  final String   uploadStatus;
  final DateTime cachedUntil;
  final DateTime createdAt;

  const FarmImage({
    required this.imageId,
    required this.entityType,
    required this.entityId,
    required this.sortOrder,
    required this.localPath,
    required this.appwriteFileId,
    required this.uploadStatus,
    required this.cachedUntil,
    required this.createdAt,
  });

  bool get isUploaded   => uploadStatus == 'uploaded';
  bool get isCached     => localPath != null;
  bool get cacheExpired => DateTime.now().isAfter(cachedUntil);

  factory FarmImage.fromMap(Map<String, dynamic> m) => FarmImage(
        imageId:        m['image_id'] as String,
        entityType:     m['entity_type'] as String,
        entityId:       m['entity_id'] as String,
        sortOrder:      m['sort_order'] as int,
        localPath:      m['local_path'] as String?,
        appwriteFileId: m['appwrite_file_id'] as String?,
        uploadStatus:   m['upload_status'] as String,
        cachedUntil:    DateTime.parse(m['cached_until'] as String),
        createdAt:      DateTime.parse(m['created_at'] as String),
      );
}

/// Handles all image lifecycle:
///   pick → compress → write to disk cache → insert SQLite row → queue upload
class ImageService {
  static final ImageService instance = ImageService._();
  ImageService._();

  static const int  _maxWidthPx  = 1080;
  static const int  _maxHeightPx = 1080;
  static const int  _qualityPct  = 82;   // ~200 KB for a typical photo
  static const int  _maxPerAsset = 3;
  static const int  _cacheDays   = 30;

  final _picker = ImagePicker();
  final _uuid   = const Uuid();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Pick from camera or gallery, compress, cache, and queue for upload.
  /// Returns null if the user cancelled or the entity already has [_maxPerAsset].
  /// [sortOrder] is auto-assigned to the next available slot (0, 1, 2).
  Future<FarmImage?> pickAndSave({
    required ImageEntityType entityType,
    required String          entityId,
    required String          createdBy,
    ImageSource source = ImageSource.camera,
  }) async {
    // Check slot availability (assets: max 3, events: max 1)
    final maxSlots = entityType == ImageEntityType.asset ? _maxPerAsset : 1;
    final existing = await getImages(entityType: entityType, entityId: entityId);
    if (existing.length >= maxSlots) {
      Log.w('[ImageService] Max images ($maxSlots) reached for $entityId');
      return null;
    }

    // Pick
    final XFile? picked = await _picker.pickImage(source: source);
    if (picked == null) return null;

    // Compress
    final compressed = await _compress(picked.path);
    if (compressed == null) return null;

    // Write to cache directory
    final cacheDir  = await _cacheDir();
    final imageId   = _uuid.v4();
    final cachePath = p.join(cacheDir.path, '$imageId.jpg');
    await compressed.copy(cachePath);

    // Insert row
    final now        = DateTime.now().toUtc();
    final cachedUntil = now.add(const Duration(days: _cacheDays));
    final sortOrder   = existing.length; // next available slot

    final db = await LocalDb.instance.database;
    await db.insert('asset_images', {
      'image_id':         imageId,
      'entity_type':      entityType.value,
      'entity_id':        entityId,
      'sort_order':       sortOrder,
      'local_path':       cachePath,
      'appwrite_file_id': null,
      'upload_status':    'pending',
      'cached_until':     cachedUntil.toIso8601String(),
      'created_by':       createdBy,
      'created_at':       now.toIso8601String(),
    });

    // Queue for upload via existing outbox
    await LocalDb.instance.addToQueueDirect(recordId: imageId, tableName: 'asset_images', operation: 'CREATE');

    Log.i('[ImageService] Saved image $imageId for $entityId (slot $sortOrder)');

    return FarmImage(
      imageId:        imageId,
      entityType:     entityType.value,
      entityId:       entityId,
      sortOrder:      sortOrder,
      localPath:      cachePath,
      appwriteFileId: null,
      uploadStatus:   'uploaded',
      cachedUntil:    cachedUntil,
      createdAt:      now,
    );
  }

  /// Re-download an image from Appwrite and refresh its local cache.
  /// Call this when [FarmImage.localPath] is null but [appwriteFileId] exists.
  Future<String?> recache({
    required String imageId,
    required String appwriteFileId,
    required Uint8List bytes,
  }) async {
    final cacheDir  = await _cacheDir();
    final cachePath = p.join(cacheDir.path, '$imageId.jpg');
    final file      = File(cachePath);
    await file.writeAsBytes(bytes);

    final now         = DateTime.now().toUtc();
    final cachedUntil = now.add(const Duration(days: _cacheDays));

    final db = await LocalDb.instance.database;
    await db.update(
      'asset_images',
      {'local_path': cachePath, 'cached_until': cachedUntil.toIso8601String()},
      where: 'image_id = ?',
      whereArgs: [imageId],
    );

    return cachePath;
  }

  /// Mark an image as uploaded and store the Appwrite file ID.
  Future<void> markUploaded(String imageId, String appwriteFileId) async {
    final db = await LocalDb.instance.database;
    await db.update(
      'asset_images',
      {'appwrite_file_id': appwriteFileId, 'upload_status': 'uploaded'},
      where: 'image_id = ?',
      whereArgs: [imageId],
    );
    Log.i('[ImageService] Marked $imageId as uploaded → $appwriteFileId');
  }

  /// Delete an image locally and queue a DELETE for Appwrite.
  Future<void> delete(FarmImage image) async {
    // Remove local file
    if (image.localPath != null) {
      final f = File(image.localPath!);
      if (await f.exists()) await f.delete();
    }

    final db = await LocalDb.instance.database;
    await db.delete('asset_images', where: 'image_id = ?', whereArgs: [image.imageId]);

    if (image.appwriteFileId != null) {
      await LocalDb.instance.addToQueueDirect(recordId: image.imageId, tableName: 'asset_images', operation: 'DELETE');
    }

    // Re-index sort_order for remaining images
    final remaining = await getImages(entityType: null, entityId: image.entityId, raw: true);
    for (var i = 0; i < remaining.length; i++) {
      if (remaining[i].sortOrder != i) {
        await db.update(
          'asset_images',
          {'sort_order': i},
          where: 'image_id = ?',
          whereArgs: [remaining[i].imageId],
        );
      }
    }
  }

  /// Get all images for an entity, ordered by sort_order.
  Future<List<FarmImage>> getImages({
    required ImageEntityType? entityType,
    required String entityId,
    bool raw = false,
  }) async {
    final db = await LocalDb.instance.database;
    final rows = await db.query(
      'asset_images',
      where: entityType != null
          ? 'entity_id = ? AND entity_type = ?'
          : 'entity_id = ?',
      whereArgs: entityType != null
          ? [entityId, entityType.value]
          : [entityId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(FarmImage.fromMap).toList();
  }

  /// Evict expired cache entries: delete local files, null out local_path.
  /// Call from AppRefreshService or on app start.
  Future<void> evictExpiredCache() async {
    final db  = await LocalDb.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final expired = await db.query(
      'asset_images',
      where: 'cached_until < ? AND local_path IS NOT NULL',
      whereArgs: [now],
    );

    for (final row in expired) {
      final path = row['local_path'] as String?;
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    }

    if (expired.isNotEmpty) {
      await db.update(
        'asset_images',
        {'local_path': null},
        where: 'cached_until < ?',
        whereArgs: [now],
      );
      Log.i('[ImageService] Evicted ${expired.length} expired cache files.');
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<File?> _compress(String sourcePath) async {
    try {
      final dir    = await getTemporaryDirectory();
      final tmpOut = p.join(dir.path, '${_uuid.v4()}_compressed.jpg');

      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        tmpOut,
        minWidth:  _maxWidthPx,
        minHeight: _maxHeightPx,
        quality:   _qualityPct,
        format:    CompressFormat.jpeg,
        keepExif:  false, // strip GPS and device metadata
      );

      if (result == null) return null;

      // Ensure we hit ≤200 KB; step down quality if needed
      var outFile = File(result.path);
      var quality = _qualityPct;
      while (await outFile.length() > 200 * 1024 && quality > 50) {
        quality -= 10;
        final retry = await FlutterImageCompress.compressAndGetFile(
          sourcePath, tmpOut,
          minWidth: _maxWidthPx, minHeight: _maxHeightPx,
          quality: quality, format: CompressFormat.jpeg, keepExif: false,
        );
        if (retry != null) outFile = File(retry.path);
      }

      final kb = (await outFile.length()) ~/ 1024;
      Log.i('[ImageService] Compressed → ${kb}KB (q=$quality)');
      return outFile;
    } catch (e) {
      Log.e('[ImageService] Compression failed: $e');
      return null;
    }
  }

  Future<Directory> _cacheDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory(p.join(base.path, 'image_cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}