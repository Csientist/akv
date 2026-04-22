import 'package:appwrite/appwrite.dart';
import 'logger.dart';
import '../core/secrets.dart';

class AppwriteClient {
  static final AppwriteClient instance = AppwriteClient._internal();
  AppwriteClient._internal();

  late final Client client;
  late final TablesDB tablesDB; // Switched from Databases to TablesDB
  late final Account account; 
  late final Functions functions;
  late final Realtime realtime;

  static const _endpoint      = Secrets.appwriteEndpoint;
  static const kProjectId     = Secrets.appwriteProjectId;
  static const kDatabaseId    = Secrets.appwriteDatabaseId;

  // Collection (Table) IDs
  static const colLedger          = 'ledger_entries';
  static const colAssets          = 'assets';
  static const colInventory       = 'inventory';
  static const colFinancials      = 'financials';
  static const colAssetEvents     = 'asset_events';
  static const colMilkLogs        = 'milk_logs';
  static const colPartialPayments = 'partial_payments';
  static const colSyncConflicts   = 'sync_conflicts';
  static const colFlockLogs       = 'flock_logs';
  static const colAssetImages     = 'asset_images';

  // Storage bucket IDs
  static const bucketAssetImages  = Secrets.bucketAssetImages;

  void init() {
    client = Client()
      ..setEndpoint(_endpoint)
      ..setProject(kProjectId);

    // Initialize the new TablesDB service
    tablesDB  = TablesDB(client);
    account   = Account(client);
    functions = Functions(client);
    realtime  = Realtime(client);
  }

  /// Push a single record to Appwrite using the modern Upsert API.
  /// This replaces the manual "update-then-create" logic.
  Future<void> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      // The new upsertRow handles both creation and updates in one network call.
      // If the row exists, it updates; if not, it creates.
      await tablesDB.upsertRow(
        databaseId: kDatabaseId,
        tableId: collectionId, // In 1.8+, collectionId maps to tableId
        rowId: documentId,     // In 1.8+, documentId maps to rowId
        data: data,
      );

      Log.i('[Appwrite] Successfully upserted row: $documentId');
      
    } on AppwriteException catch (e) {
      // We no longer need to check for code 404 manually!
      // We only catch real errors: Network (0), Rate Limits (429), or Permissions (401).
      Log.e('[Appwrite] Upsert failed: ${e.message} (Code: ${e.code})');
      
      // CRITICAL: Rethrow so the SyncService knows to keep this in the SQLite queue.
      rethrow; 
    } catch (e) {
      Log.e('[Appwrite] Unexpected fatal error during upsert: $e');
      rethrow;
    }
  }
}