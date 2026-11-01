import Combine
import GoogleMobileAds
import UIKit

/// 「次のアイテムを選ぶ」ときに見てもらうリワード広告
@MainActor
final class RewardedAdManager: NSObject, ObservableObject {
    static let shared = RewardedAdManager()

    // 開発中に本番広告を表示するとAdMobのポリシー違反になるため、DebugではGoogle公式のテスト用IDを使う
    #if DEBUG
    private static let adUnitID = "ca-app-pub-3940256099942544/1712485313"
    #else
    private static let adUnitID = "ca-app-pub-8522231452310619/9312190214"
    #endif

    /// 広告を読み込み済みで、すぐに表示できるか
    @Published private(set) var isReady = false

    private var rewardedAd: RewardedAd?
    private var isLoading = false
    private var didEarnReward = false
    /// 広告を閉じたあとに、報酬を獲得したかどうかを渡して実行する処理
    private var onDismiss: ((Bool) -> Void)?

    func load() {
        guard rewardedAd == nil, !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let ad = try await RewardedAd.load(with: Self.adUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                rewardedAd = ad
                isReady = true
            } catch {
                // 読み込めなかったときは、次にアイテム選択を開いたときに再挑戦する
            }
        }
    }

    /// 広告を表示する。広告を閉じたあとに、最後まで見て報酬を獲得したかを completion に渡す
    func present(completion: @escaping (Bool) -> Void) {
        guard let rewardedAd, let viewController = UIApplication.shared.topViewController() else {
            load()
            completion(false)
            return
        }
        didEarnReward = false
        onDismiss = completion
        rewardedAd.present(from: viewController) { [weak self] in
            self?.didEarnReward = true
        }
    }

    private func finishPresentation() {
        rewardedAd = nil
        isReady = false
        let completion = onDismiss
        onDismiss = nil
        completion?(didEarnReward)
        didEarnReward = false
        load()
    }
}

extension RewardedAdManager: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        MainActor.assumeIsolated { finishPresentation() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        MainActor.assumeIsolated { finishPresentation() }
    }
}
