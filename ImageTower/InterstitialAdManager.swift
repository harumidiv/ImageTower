import GoogleMobileAds
import UIKit

/// 「もういちど」を押したときに出すインタースティシャル広告
/// 毎回出すと遊びのテンポを崩すため、3回に1回だけ表示する
@MainActor
final class InterstitialAdManager: NSObject {
    static let shared = InterstitialAdManager()

    // 開発中に本番広告を表示するとAdMobのポリシー違反になるため、DebugではGoogle公式のテスト用IDを使う
    #if DEBUG
    private static let adUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    private static let adUnitID = "ca-app-pub-8522231452310619/1071127759"
    #endif

    private static let showInterval = 3

    private var interstitial: InterstitialAd?
    private var isLoading = false
    private var restartCount = 0
    /// 広告を閉じたあとに実行する処理。広告の裏でゲームが始まらないよう、閉じるまで待つ
    private var onDismiss: (() -> Void)?

    func load() {
        guard interstitial == nil, !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let ad = try await InterstitialAd.load(with: Self.adUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                interstitial = ad
            } catch {
                // 読み込めなかったときは次の「もういちど」で再挑戦する
            }
        }
    }

    /// 「もういちど」が押されたときに呼ぶ。広告を出す回なら閉じたあとに、そうでなければすぐに completion を実行する
    func handleRestart(completion: @escaping () -> Void) {
        restartCount += 1
        guard restartCount.isMultiple(of: Self.showInterval),
              let interstitial,
              let viewController = UIApplication.shared.topViewController() else {
            load()
            completion()
            return
        }
        onDismiss = completion
        interstitial.present(from: viewController)
    }

    private func finishPresentation() {
        interstitial = nil
        let completion = onDismiss
        onDismiss = nil
        completion?()
        load()
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        MainActor.assumeIsolated { finishPresentation() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        MainActor.assumeIsolated { finishPresentation() }
    }
}

extension UIApplication {
    /// 広告を表示するための最前面の ViewController
    func topViewController() -> UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
