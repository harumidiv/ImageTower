import Combine
import SpriteKit
import SwiftUI
import UIKit

@MainActor
final class TowerGameViewModel: ObservableObject {
    let scene: TowerGameScene
    let images: [UIImage]

    @Published var score = 0
    @Published var bestScore: Int
    @Published var nextImageIndex = 0
    @Published var isGameOver = false
    @Published var isPaused = false
    @Published var hasDroppedOnce = false
    @Published private(set) var towerSnapshot: UIImage?
    /// このゲームを始めたときのベスト。超えたら「自己ベスト更新」とする
    private(set) var bestScoreAtStart: Int

    private let bestScoreKey = "imagetower.best-score.v1"
    private let landingFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let rotateFeedback = UISelectionFeedbackGenerator()
    private let gameOverFeedback = UINotificationFeedbackGenerator()

    init(images: [UIImage]) {
        self.images = images
        let savedBestScore = UserDefaults.standard.integer(forKey: bestScoreKey)
        bestScore = savedBestScore
        bestScoreAtStart = savedBestScore
        scene = TowerGameScene(images: images)
        connectScene()
        landingFeedback.prepare()
        gameOverFeedback.prepare()
    }

    var didUpdateBestScore: Bool {
        score > 0 && score > bestScoreAtStart
    }

    func restart() {
        score = 0
        bestScoreAtStart = bestScore
        towerSnapshot = nil
        isGameOver = false
        isPaused = false
        hasDroppedOnce = false
        scene.isPaused = false
        scene.resetGame()
    }

    func togglePause() {
        guard !isGameOver else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isPaused.toggle() }
        scene.isPaused = isPaused
    }

    func rotateHeldItem() {
        guard !isPaused, !isGameOver, scene.rotateHeldItem() else { return }
        rotateFeedback.selectionChanged()
    }

    func persistBestScore() {
        UserDefaults.standard.set(bestScore, forKey: bestScoreKey)
    }

    private func connectScene() {
        scene.onScore = { [weak self] score in
            guard let self else { return }
            self.score = score
            if score > self.bestScore {
                self.bestScore = score
                self.persistBestScore()
            }
        }
        scene.onNextImage = { [weak self] index in self?.nextImageIndex = index }
        scene.onFirstDrop = { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) { self?.hasDroppedOnce = true }
        }
        scene.onLand = { [weak self] in
            self?.landingFeedback.impactOccurred(intensity: 0.82)
        }
        scene.onGameOver = { [weak self] in
            guard let self else { return }
            self.persistBestScore()
            self.towerSnapshot = self.scene.towerSnapshotImage()
            withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
                self.isGameOver = true
            }
            self.gameOverFeedback.notificationOccurred(.warning)
        }
    }
}

struct TowerGameView: View {
    @StateObject private var model: TowerGameViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var shareImage: Image?
    let stageName: String
    let onExit: () -> Void

    init(images: [UIImage], stageName: String, onExit: @escaping () -> Void) {
        _model = StateObject(wrappedValue: TowerGameViewModel(images: images))
        self.stageName = stageName
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            ImageTowerTheme.sky.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    header
                    scoreRow
                    board
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                // 盤面とバナーの間に余白を取り、ドロップ操作での誤タップを防ぐ
                .padding(.bottom, 24)

                BannerAdView()
                    .frame(width: BannerAdView.size.width, height: BannerAdView.size.height)
            }

            if model.isPaused { pauseOverlay }
            if model.isGameOver { gameOverOverlay }
        }
        .onDisappear { model.persistBestScore() }
        .onChange(of: model.towerSnapshot) { _, snapshot in
            shareImage = snapshot.flatMap(makeShareImage)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, !model.isPaused, !model.isGameOver {
                model.togglePause()
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.9), in: Circle())
            }
            .buttonStyle(BouncyButtonStyle())
            .accessibilityLabel("ホームに戻る")

            Spacer()
            VStack(spacing: 0) {
                Text("IMAGE TOWER")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(1.1)
                Text("落とさず、どこまで積める？")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(ImageTowerTheme.secondaryText)
            }
            Spacer()

            Button(action: model.togglePause) {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.9), in: Circle())
            }
            .buttonStyle(BouncyButtonStyle())
            .accessibilityLabel(model.isPaused ? "再開" : "一時停止")
        }
        .foregroundStyle(ImageTowerTheme.ink)
    }

    private var scoreRow: some View {
        HStack(spacing: 10) {
            scoreCell(label: "SCORE", value: model.score, accent: ImageTowerTheme.coral)
            scoreCell(label: "BEST", value: model.bestScore, accent: ImageTowerTheme.skyDeep)

            HStack(spacing: 8) {
                Text("NEXT")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(ImageTowerTheme.secondaryText)
                if model.images.indices.contains(model.nextImageIndex) {
                    Image(uiImage: model.images[model.nextImageIndex])
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .foregroundStyle(ImageTowerTheme.ink)
    }

    private func scoreCell(label: String, value: Int, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(accent)
            Text("\(value)")
                .font(.system(size: 21, weight: .black, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .frame(height: 58)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var board: some View {
        SpriteView(scene: model.scene, options: [.ignoresSiblingOrder])
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                if !model.hasDroppedOnce {
                    Label("左右に動かして指を離すと落下・右下で回転", systemImage: "hand.draw.fill")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(ImageTowerTheme.ink)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.9), in: Capsule())
                        .padding(.top, 15)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                rotateButton
                    .padding(14)
            }
            .shadow(color: ImageTowerTheme.skyDeep.opacity(0.28), radius: 16, y: 8)
    }

    private var rotateButton: some View {
        Button(action: model.rotateHeldItem) {
            Image(systemName: "rotate.right.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(ImageTowerTheme.coral, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(model.isGameOver)
        .accessibilityLabel("落とすアイテムを回転")
    }

    private var pauseOverlay: some View {
        Color.black.opacity(0.25)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 18) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 30, weight: .black))
                    Text("ひとやすみ")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                    Button(action: model.togglePause) {
                        Label("つづける", systemImage: "play.fill")
                            .primaryGameButton(color: ImageTowerTheme.ink)
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
                .padding(26)
                .frame(maxWidth: 310)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
    }

    private var gameOverOverlay: some View {
        Color.black.opacity(0.32)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 15) {
                    Text("おっと！")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text("\(model.score) 個つめました")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(model.didUpdateBestScore ? "自己ベスト更新！" : "BEST  \(model.bestScore)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(ImageTowerTheme.coral)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(ImageTowerTheme.cream, in: Capsule())

                    Button(action: model.restart) {
                        Label("もういちど", systemImage: "arrow.clockwise")
                            .primaryGameButton(color: ImageTowerTheme.coral)
                    }
                    .buttonStyle(BouncyButtonStyle())

                    if let shareImage {
                        ShareLink(
                            item: shareImage,
                            message: Text(shareMessage),
                            preview: SharePreview("IMAGE TOWER のスコア", image: shareImage)
                        ) {
                            Label("スクショでシェア", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(ImageTowerTheme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(ImageTowerTheme.cream, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }

                    Button("ホームへ", action: onExit)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(ImageTowerTheme.secondaryText)
                }
                .padding(27)
                .frame(maxWidth: 320)
                .background(ImageTowerTheme.paper, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
            }
    }

    private var shareMessage: String {
        let headline = model.didUpdateBestScore ? "自己ベスト更新！" : ""
        return "\(headline)「\(stageName)」で\(model.score)個つみました！ #ImageTower"
    }

    /// タワーのスクショにステージ名とスコアを添えたシェア用画像を作る
    private func makeShareImage(from towerImage: UIImage) -> Image? {
        let card = ShareCardView(
            stageName: stageName,
            score: model.score,
            isNewBest: model.didUpdateBestScore,
            towerImage: towerImage
        )
        let renderer = ImageRenderer(content: card)
        // 高く積んで縦長になっても画像が大きくなりすぎないよう、長辺を約6000pxに抑える
        renderer.scale = min(displayScale, 6000 / card.estimatedHeight)
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// SNS共有用の画像レイアウト。タワーが高いほど縦長になる
private struct ShareCardView: View {
    static let width: CGFloat = 360
    private static let padding: CGFloat = 24

    let stageName: String
    let score: Int
    let isNewBest: Bool
    let towerImage: UIImage

    private var towerWidth: CGFloat { Self.width - Self.padding * 2 }
    private var towerHeight: CGFloat {
        towerWidth * towerImage.size.height / max(towerImage.size.width, 1)
    }

    /// 見出しやスコアのぶんを含めた、おおよその画像の高さ
    var estimatedHeight: CGFloat { towerHeight + 190 }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("IMAGE TOWER")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(1.5)
                Spacer()
                Text(stageName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ImageTowerTheme.secondaryText)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                if isNewBest {
                    Text("自己ベスト更新！")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(ImageTowerTheme.coral, in: Capsule())
                }

                // 桁数が多くても折り返さず、1行に収まるよう縮小する
                (Text("\(score)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                 + Text(" 個つみました")
                    .font(.system(size: 18, weight: .black, design: .rounded)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(uiImage: towerImage)
                .resizable()
                .frame(width: towerWidth, height: towerHeight)
                // 書き出したタワーの画像は背景が透明なので、ゲーム画面と同じ空色を敷く
                .background(
                    LinearGradient(
                        colors: [ImageTowerTheme.skyDeep, ImageTowerTheme.sky],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white, lineWidth: 4)
                )
        }
        .foregroundStyle(ImageTowerTheme.ink)
        .padding(Self.padding)
        .frame(width: Self.width)
        .background(ImageTowerTheme.background)
        .environment(\.colorScheme, .light)
    }
}

private extension View {
    func primaryGameButton(color: Color) -> some View {
        font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
