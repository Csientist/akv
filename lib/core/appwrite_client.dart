import 'package:appwrite/appwrite.dart';
import 'dart:developer' as dev;

class AppwriteClient {
  static final AppwriteClient instance = AppwriteClient._internal();
  AppwriteClient._internal();

  late final Client client; // Renamed from _client so AuthService can access it
  late final Databases databases;
  late final Account account; // ADDED BACK: Crucial for your LoginScreen to work!

  // ── Replace these with your Appwrite project values ──────────────────────
  static const _endpoint  = 'https://fra.cloud.appwrite.io/v1'; 
  static const _projectId = '69a53fb00009c20573d6';
  static const _databaseId = '69a6d9c9002f3a1c4d7a';

  // Collection IDs (must match Appwrite console)
  static const colLedger     = 'ledger_entries';
  static const colAssets     = 'assets';
  static const colInventory  = 'inventory';
  static const colFinancials = 'financials';
  static const colAssetEvents = 'asset_events'; 
  static const colMilkLogs    = 'milk_logs';      

  void init() {
    client = Client()
      ..setEndpoint(_endpoint)
      ..setProject(_projectId)
      ..setSelfSigned(status: true); 

    databases = Databases(client);
    account = Account(client); // Initialize auth!
  }

  /// Push a single record to Appwrite. 
  /// Throws an exception if the network fails so the local DB keeps the data queued.
  Future<void> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      // 1. Attempt to update the existing document.
      // Appwrite only updates the specific fields provided in the 'data' map,
      // preventing you from accidentally wiping out other fields changed by other users.
      await databases.updateDocument(
        databaseId: _databaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
      dev.log('[Appwrite] Updated document: $documentId');
      
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        // 2. Document does not exist on the server. Safe to create.
        try {
          await databases.createDocument(
            databaseId: _databaseId,
            collectionId: collectionId,
            documentId: documentId,
            data: data,
          );
          dev.log('[Appwrite] Created new document: $documentId');
        } on AppwriteException catch (createError) {
          // CRITICAL: If the network drops exactly here, we MUST rethrow 
          // so the SyncService doesn't mark it as 'synced'.
          dev.log('[Appwrite] Create failed: ${createError.message}');
          rethrow; 
        }
      } else {
        // 3. Network timeout (code 0), Rate Limit (429), or Permission Error (401/403)
        dev.log('[Appwrite] Update failed: ${e.message}');
        rethrow; // CRITICAL: Keep it in the SQLite queue!
      }
    } catch (e) {
      // Catch-all for formatting errors or unexpected crashes
      dev.log('[Appwrite] Fatal upsert error: $e');
      rethrow;
    }
  }
}