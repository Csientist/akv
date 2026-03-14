import 'dart:io';
import '../core/logger.dart';
import 'package:appwrite/appwrite.dart';
import '../core/appwrite_client.dart';
import '../core/local_db.dart';
import 'image_service.dart';

/// Handles the Appwrite Storage side of image sync:
///   - Uploads pending images from asset_images table
///   - Deletes files from Appwrite Storage when queued for DELETE
///   - Called by SyncService during its normal sync pass
class ImageSyncService {
  static final ImageSyncService instance = ImageSyncService._();
  ImageSyncService._();

  static const _bucketId = 'asset-images'; // Appwrite Storage bucket ID

  // ── Upload pending images ──────────────────────────────────────────────────

  /// Upload all images with upload_status = 'pending' that have a local file.
  /// Safe to call multiple times — skips already-uploaded rows.
  Future<void> uploadPending() async {
    final db = await LocalDb.instance.database;

    final pending = await db.query(
      'asset_images',
      where: "upload_status = 'pending' AND local_path IS NOT NULL",
    );

    if (pending.isEmpty) return;
    Log.i('[ImageSync] ${pending.length} images pending upload.');

    final storage = Storage(AppwriteClient.instance.client);

    for (final row in pending) {
      final imageId   = row['image_id'] as String;
      final localPath = row['local_path'] as String;
      final file      = File(localPath);

      if (!await file.exists()) {
        Log.w('[ImageSync] Cache file missing for $imageId — skipping.');
        continue;
      }

      try {
        final result = await storage.createFile(
          bucketId: _bucketId,
          fileId:   imageId, // use imageId as Appwrite file ID for 1:1 mapping
          file:     InputFile.fromPath(
            path:     localPath,
            filename: '$imageId.jpg',
          ),
          permissions: [
            Permission.read(Role.user(row['created_by'] as String)),
          ],
        );

        await ImageService.instance.markUploaded(imageId, result.$id);
        Log.i('[ImageSync] Uploaded $imageId → ${result.$id}');
      } on AppwriteException catch (e) {
        // 409 = file already exists in Appwrite (e.g. re-run after crash)
        if (e.code == 409) {
          await ImageService.instance.markUploaded(imageId, imageId);
          Log.w('[ImageSync] $imageId already exists in Appwrite — marked uploaded.');
        } else {
          Log.e('[ImageSync] Upload failed for $imageId: ${e.message}');
          // Will retry on next sync pass
        }
      } catch (e) {
        Log.e('[ImageSync] Unexpected error for $imageId: $e');
      }
    }
  }

  // ── Delete from Appwrite ───────────────────────────────────────────────────

  /// Delete a file from Appwrite Storage by its file ID.
  /// Called by SyncService when it processes a DELETE from the sync_queue
  /// for table 'asset_images'.
  Future<void> deleteFile(String appwriteFileId) async {
    try {
      final storage = Storage(AppwriteClient.instance.client);
      await storage.deleteFile(bucketId: _bucketId, fileId: appwriteFileId);
      Log.i('[ImageSync] Deleted $appwriteFileId from Appwrite Storage.');
    } on AppwriteException catch (e) {
      // 404 = already gone, treat as success
      if (e.code == 404) {
        Log.w('[ImageSync] $appwriteFileId not found in Appwrite — already deleted.');
      } else {
        Log.e('[ImageSync] Delete failed for $appwriteFileId: ${e.message}');
        rethrow;
      }
    }
  }

  // ── Download for cache refresh ─────────────────────────────────────────────

  /// Fetch image bytes from Appwrite and refresh local cache.
  /// Call when FarmImage.localPath is null but appwriteFileId is set.
  Future<String?> fetchAndRecache(FarmImage image) async {
    if (image.appwriteFileId == null) return null;
    try {
      final storage = Storage(AppwriteClient.instance.client);
      final bytes   = await storage.getFileDownload(
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

  /// Build the Appwrite preview URL for an image (no download needed for display).
  /// Use this for fast in-app display when you have a valid session.
  String previewUrl(String appwriteFileId, {int width = 1080}) {
    final endpoint  = AppwriteClient.instance.client.endPoint;
    final projectId = AppwriteClient.kProjectId;
    return '$endpoint/storage/buckets/$_bucketId/files/$appwriteFileId/preview'
        '?width=$width&project=$projectId';
  }
}