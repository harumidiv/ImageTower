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

    private let bestScoreKey = "imagetower.best-score.v1"
    private let landingFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let rotateFeedback = UISelectionFeedbackGenerator()
    private let gameOverFeedback = UINotificationFeedbackGenerator()

    init(images: [UIImage]) {
        self.images = images
        bestScore = UserDefaults.standard.integer(forKey: bestScoreKey)
        scene = TowerGameScene(images: images)
        connectScene()
        landingFeedback.prepare()
        gameOverFeedback.prepare()
    }

    func restart() {
        score = 0
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
    let onExit: () -> Void

    init(images: [UIImage], onExit: @escaping () -> Void) {
        _model = StateObject(wrappedValue: TowerGameViewModel(images: images))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            ImageTowerTheme.sky.ignoresSafeArea()

            VStack(spacing: 10) {
                header
                scoreRow
                board
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if model.isPaused { pauseOverlay }
            if model.isGameOver { gameOverOverlay }
        }
        .onDisappear { model.persistBestScore() }
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
                    Text("BEST  \(model.bestScore)")
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
