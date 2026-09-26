import StitchCore
import StoreKit

/// StoreKit 2 买断制 Pro 权益管理：购买、恢复、交易监听、本地持久化。
@MainActor
final class ProUpgradeManager: ObservableObject {
    static let shared = ProUpgradeManager()
    static let productID = "com.example.stitchshot.pro"

    private static let entitlementKey = "pro.isPro"

    @Published private(set) var isPro: Bool
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        isPro = AppConstants.sharedDefaults.bool(forKey: Self.entitlementKey)
        updatesTask = Task { [weak self] in await self?.listenForTransactions() }
        Task {
            await refreshEntitlement()
            await loadProduct()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var priceText: String {
        product?.displayPrice ?? "—"
    }

    func loadProduct() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    // MARK: - Purchase / Restore

    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            await loadProduct()
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return false }
                await grantEntitlement(transaction)
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    // MARK: - Entitlement

    private func refreshEntitlement() async {
        var granted = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                granted = true
            }
        }
        applyEntitlement(granted)
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update else { continue }
            if transaction.productID == Self.productID {
                if transaction.revocationDate == nil {
                    await grantEntitlement(transaction)
                } else {
                    applyEntitlement(false)
                    await transaction.finish()
                }
            }
        }
    }

    private func grantEntitlement(_ transaction: StoreKit.Transaction) async {
        applyEntitlement(true)
        await transaction.finish()
    }

    private func applyEntitlement(_ value: Bool) {
        isPro = value
        AppConstants.sharedDefaults.set(value, forKey: Self.entitlementKey)
    }
}
