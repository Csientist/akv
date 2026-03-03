import 'package:appwrite/appwrite.dart';

class AppwriteClient {
  static final AppwriteClient instance = AppwriteClient._internal();
  AppwriteClient._internal();

  late final Client _client;
  late final Databases databases;

  // ── Replace these with your Appwrite project values ──────────────────────
  static const _endpoint  = 'https://cloud.appwrite.io/v1'; // or self-hosted URL
  static const _projectId = 'YOUR_PROJECT_ID';
  static const _databaseId = 'farm_db';

  // Collection IDs (must match Appwrite console)
  static const colLedger     = 'ledger_entries';
  static const colAssets     = 'assets';
  static const colInventory  = 'inventory';
  static const colFinancials = 'financials';

  void init() {
    _client = Client()
      ..setEndpoint(_endpoint)
      ..setProject(_projectId)
      ..setSelfSigned(status: true); // remove in production

    databases = Databases(_client);
  }

  /// Push a single record to Appwrite. The [data] map must match
  /// the Appwrite collection schema attributes.
  Future<void> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      // Try update first, fall back to create (idempotent upsert)
      await databases.updateDocument(
        databaseId: _databaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        await databases.createDocument(
          databaseId: _databaseId,
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        );
      } else {
        rethrow;
      }
    }
  }
}