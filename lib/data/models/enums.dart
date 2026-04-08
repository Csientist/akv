enum LedgerType { sale, purchase, herdUpdate, inventoryAdjust }
enum LedgerStatus { pending, completed, failed }

enum AssetCategory { livestock, crop }
enum AssetStatus { active, sold, deceased }

enum PaymentMethod { mpesa, cash, bank }
enum PaymentStatus { paid, pending, failed }
enum TransactionType { sale, purchase }

enum InventoryUnit { kg, litres, bags, pieces, vials }
enum InventoryCategory { feed, medicine, equipment, seed, other }

enum MilkSession { am, pm, full }