import 'package:appwrite/appwrite.dart';
import 'logger.dart';

class AppwriteClient {
  static final AppwriteClient instance = AppwriteClient._internal();
  AppwriteClient._internal();

  late final Client client; // Renamed from _client so AuthService can access it
  late final Databases databases;
  late final Account account; // ADDED BACK: Crucial for your LoginScreen to work!
  late final Functions functions;
  late final Realtime realtime;

  // ── Replace these with your Appwrite project values ──────────────────────
  static const _endpoint      = 'https://fra.cloud.appwrite.io/v1';
  static const kProjectId     = '69a53fb00009c20573d6';  // k-prefix avoids clash with Client.projectId (Appwrite SDK 12+)
  static const kDatabaseId    = '69a6d9c9002f3a1c4d7a';  // k-prefix for consistency

  // Collection IDs (must match Appwrite console)
  static const colLedger          = 'ledger_entries';
  static const colAssets          = 'assets';
  static const colInventory       = 'inventory';
  static const colFinancials      = 'financials';
  static const colAssetEvents     = 'asset_events';
  static const colMilkLogs        = 'milk_logs';
  static const colPartialPayments = 'partial_payments';

  void init() {
    client = Client()
      ..setEndpoint(_endpoint)
      ..setProject(kProjectId)
      ..setSelfSigned(status: true);

    databases = Databases(client);
    account   = Account(client);
    functions = Functions(client);
    realtime  = Realtime(client);
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
        databaseId: kDatabaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
      Log.i('[Appwrite] Updated document: $documentId');
      
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        // 2. Document does not exist on the server. Safe to create.
        try {
          await databases.createDocument(
            databaseId: kDatabaseId,
            collectionId: collectionId,
            documentId: documentId,
            data: data,
          );
          Log.i('[Appwrite] Created new document: $documentId');
        } on AppwriteException catch (createError) {
          // CRITICAL: If the network drops exactly here, we MUST rethrow 
          // so the SyncService doesn't mark it as 'synced'.
          Log.e('[Appwrite] Create failed: ${createError.message}');
          rethrow; 
        }
      } else {
        // 3. Network timeout (code 0), Rate Limit (429), or Permission Error (401/403)
        Log.e('[Appwrite] Update failed: ${e.message}');
        rethrow; // CRITICAL: Keep it in the SQLite queue!
      }
    } catch (e) {
      // Catch-all for formatting errors or unexpected crashes
      Log.e('[Appwrite] Fatal upsert error: $e');
      rethrow;
    }
  }
}