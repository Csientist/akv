import 'dart:io';
import '../core/logger.dart';
import 'package:appwrite/appwrite.dart';
import '../core/appwrite_client.dart';
import '../core/local_db.dart';
import 'image_service.dart';

/// Handles the Appwrite Storage side of image sync.
class ImageSyncService {
  static final ImageSyncService instance = ImageSyncService._();
  ImageSyncService._();

  static const _bucketId = AppwriteClient.bucketAssetImages;

  // Initialize storage once
  late final Storage _storage = Storage(AppwriteClient.instance.client);
  // Shortcut to the new TablesDB service
  late final TablesDB _tablesDB = AppwriteClient.instance.tablesDB;

  // ── Upload pending images ──────────────────────────────────────────────────

  /// Upload all images with upload_status = 'pending' that have a local file.
  Future<void> uploadPending() async {
    final db = await LocalDb.instance.database;

    final pending = await db.query(
      'asset_images',
      where: "upload_status = 'pending' AND local_path IS NOT NULL",
    );

    if (pending.isEmpty) return;
    Log.i('[ImageSync] ${pending.length} images pending upload.');

    for (final row in pending) {
      final imageId   = row['image_id'] as String;
      final localPath = row['local_path'] as String;
      final file       = File(localPath);

      if (!await file.exists()) {
        Log.w('[ImageSync] Cache file missing for $imageId — skipping.');
        continue;
      }

      try {
        final result = await _storage.createFile(
          bucketId: _bucketId,
          fileId:   imageId, 
          file:     InputFile.fromPath(
            path:     localPath,
            filename: '$imageId.jpg',
          ),
          permissions: [
            Permission.read(Role.user(row['created_by'] as String)),
          ],
        );

        await ImageService.instance.markUploaded(imageId, result.$id);
        
        // Push metadata to DB table so other devices can down-sync it
        await _pushMetadata(row, result.$id);
        
        Log.i('[ImageSync] Uploaded $imageId → ${result.$id}');
      } on AppwriteException catch (e) {
        if (e.code == 409) {
          // File already exists in storage, just fix the metadata and local state
          await ImageService.instance.markUploaded(imageId, imageId);
          await _pushMetadata(row, imageId);
          Log.w('[ImageSync] $imageId already exists in Storage — recovery successful.');
        } else {
          Log.e('[ImageSync] Upload failed for $imageId: ${e.message}');
        }
      } catch (e) {
        Log.e('[ImageSync] Unexpected error for $imageId: $e');
      }
    }
  }

  /// Push image metadata to the asset_images Appwrite Database table.
  /// Refactored to use native upsertRow.
  Future<void> _pushMetadata(Map<String, dynamic> row, String appwriteFileId) async {
    final imageId = row['image_id'] as String;
    
    try {
      // Streamlined: upsertRow handles both the initial creation and any subsequent updates.
      await _tablesDB.upsertRow(
        databaseId: AppwriteClient.kDatabaseId,
        tableId:    AppwriteClient.colAssetImages,
        rowId:      imageId,
        data: {
          'image_id':         imageId,
          'entity_type':      row['entity_type'],
          'entity_id':        row['entity_id'],
          'sort_order':       row['sort_order'],
          'appwrite_file_id': appwriteFileId,
          'upload_status':    'uploaded',
          'cached_until':     row['cached_until'],
          'created_by':       row['created_by'],
          'created_at':       row['created_at'],
        },
      );
      
      Log.i('[ImageSync] Metadata pushed for $imageId');
    } catch (e) {
      // Non-fatal — Storage upload succeeded, metadata push will retry on next sync pass
      Log.e('[ImageSync] Metadata push failed for $imageId: $e');
    }
  }

  // ── Delete from Appwrite ───────────────────────────────────────────────────

  /// Delete a file from Appwrite Storage.
  Future<void> deleteFile(String appwriteFileId) async {
    try {
      await _storage.deleteFile(bucketId: _bucketId, fileId: appwriteFileId);
      Log.i('[ImageSync] Deleted $appwriteFileId from Appwrite Storage.');
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        Log.w('[ImageSync] $appwriteFileId not found — already deleted.');
      } else {
        Log.e('[ImageSync] Delete failed for $appwriteFileId: ${e.message}');
        rethrow;
      }
    }
  }

  // ── Download for cache refresh ─────────────────────────────────────────────

  /// Fetch image bytes from Appwrite and refresh local cache.
  Future<String?> fetchAndRecache(FarmImage image) async {
    if (image.appwriteFileId == null) return null;
    
    try {
      final bytes = await _storage.getFileDownload(
        bucketId: _bucketId,
        fileId:   image.appwriteFileId!,
      );
      
      return await ImageService.instance.recache(
        imageId:        image.imageId,
        appwriteFileId: image.appwriteFileId!,
        bytes:          bytes,
      );
    } on AppwriteException catch (e) {
      Log.e('[ImageSync] Fetch failed for ${image.imageId}: ${e.message}');
      return null;
    }
  }

  /// Build the Appwrite preview URL for an image.
  String previewUrl(String appwriteFileId, {int width = 1080}) {
    final endpoint  = AppwriteClient.instance.client.endPoint;
    final projectId = AppwriteClient.kProjectId;
    
    return '$endpoint/storage/buckets/$_bucketId/files/$appwriteFileId/preview'
        '?width=$width&project=$projectId';
  }
}