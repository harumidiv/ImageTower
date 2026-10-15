import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var library = SubjectLibrary()
    @State private var editorRoute: StageEditorRoute?
    @State private var playingStageID: UUID?
    @State private var sharingStage: ShareRoute?
    @State private var receiveRoute: ReceiveRoute?

    var body: some View {
        Group {
            if let stage = playingStage {
                TowerGameView(images: library.images(for: stage), stageName: stage.name) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                        playingStageID = nil
                    }
                }
                .transition(.opacity)
            } else {
                home
                    .transition(.opacity)
            }
        }
        .tint(ImageTowerTheme.coral)
        .preferredColorScheme(.light)
        .sheet(item: $editorRoute) { route in
            SubjectLibraryView(
                library: library,
                stage: route.stage
            )
        }
        .sheet(item: $sharingStage) { route in
            StageShareView(library: library, stageID: route.id)
        }
        .sheet(item: $receiveRoute) { route in
            StageReceiveView(library: library, initialCode: route.code)
        }
        .onOpenURL { url in
            // 共有リンク（imagetower://stage/コード）で開かれたら受け取り画面を出す
            guard let code = StageShareCode.code(from: url) else { return }
            editorRoute = nil
            sharingStage = nil
            withAnimation { playingStageID = nil }
            receiveRoute = ReceiveRoute(code: code)
        }
        .alert("操作できませんでした", isPresented: Binding(
            get: { editorRoute == nil && sharingStage == nil && receiveRoute == nil && library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var playingStage: GameStage? {
        guard let playingStageID,
              let stage = library.stage(withID: playingStageID),
              library.isPlayable(stage) else { return nil }
        return stage
    }

    private var home: some View {
        ZStack {
            LinearGradient(
                colors: [ImageTowerTheme.sky, ImageTowerTheme.cream],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            decorativeBackground

            ScrollView {
                VStack(spacing: 22) {
                    titleSection
                    stagesSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 42)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var decorativeBackground: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(ImageTowerTheme.yellow.opacity(0.75))
                    .frame(width: 120, height: 120)
                    .position(x: proxy.size.width - 28, y: 55)
                Circle()
                    .fill(.white.opacity(0.45))
                    .frame(width: 150, height: 70)
                    .blur(radius: 1)
                    .position(x: 42, y: 185)
                Circle()
                    .fill(.white.opacity(0.36))
                    .frame(width: 120, height: 55)
                    .position(x: proxy.size.width - 14, y: 310)
            }
            .allowsHitTesting(false)
        }
    }

    private var titleSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(ImageTowerTheme.coral)
                    .rotationEffect(.degrees(-8))
                Text("のっけタワー")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .tracking(1.2)
            }
            Text("お気に入りの写真で、ぐらぐらタワー")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(ImageTowerTheme.secondaryText)
        }
        .foregroundStyle(ImageTowerTheme.ink)
    }

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MY STAGES")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(ImageTowerTheme.secondaryText)
                    Text("ステージ")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                }
                Spacer()
                Button {
                    receiveRoute = ReceiveRoute(code: nil)
                } label: {
                    Label("受け取る", systemImage: "tray.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(ImageTowerTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(.white, in: Capsule())
                        .overlay(Capsule().stroke(.black.opacity(0.06)))
                }
                .buttonStyle(BouncyButtonStyle())
                Button {
                    editorRoute = StageEditorRoute(stage: nil)
                } label: {
                    Label("作る", systemImage: "plus")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(ImageTowerTheme.orange, in: Capsule())
                }
                .buttonStyle(BouncyButtonStyle())
            }

            if library.stages.isEmpty {
                emptyStageCard
            } else {
                ForEach(library.stages) { stage in
                    stageCard(stage)
                }
            }
        }
    }

    private var emptyStageCard: some View {
        Button {
            editorRoute = StageEditorRoute(stage: nil)
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.badge.automatic")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(ImageTowerTheme.orange)
                Text("最初のステージを作成")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text("写真から切り抜くか、保存済み素材を選びます")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(ImageTowerTheme.secondaryText)
            }
            .foregroundStyle(ImageTowerTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(ImageTowerTheme.orange.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }

    private func stageCard(_ stage: GameStage) -> some View {
        let images = library.images(for: stage)
        let isPlayable = images.count >= SubjectLibrary.minimumPlayableItems
        let remainingCount = max(0, SubjectLibrary.minimumPlayableItems - images.count)
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                stageThumbnail(images)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.name)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(ImageTowerTheme.ink)
                        .lineLimit(1)
                    Text(isPlayable ? "\(images.count)個の素材・プレイできます" : "あと\(remainingCount)個追加で遊べます")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isPlayable ? ImageTowerTheme.secondaryText : ImageTowerTheme.orange)
                }

                Spacer()

                if isPlayable {
                    Button {
                        sharingStage = ShareRoute(id: stage.id)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ImageTowerTheme.secondaryText)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.045), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("「\(stage.name)」を共有")
                }

                Button {
                    editorRoute = StageEditorRoute(stage: stage)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ImageTowerTheme.secondaryText)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.045), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("「\(stage.name)」を編集")
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                    playingStageID = stage.id
                }
            } label: {
                Label(
                    isPlayable ? "このステージであそぶ" : "\(SubjectLibrary.minimumPlayableItems)個以上であそべます",
                    systemImage: "play.fill"
                )
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(ImageTowerTheme.ink, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle())
            .disabled(!isPlayable)
            .opacity(isPlayable ? 1 : 0.3)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.black.opacity(0.055)))
    }

    private func stageThumbnail(_ images: [UIImage]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(ImageTowerTheme.cream)

            if images.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(ImageTowerTheme.secondaryText.opacity(0.5))
            } else {
                ForEach(Array(images.prefix(3).enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: CGFloat(42 + index * 6), height: CGFloat(42 + index * 6))
                        .offset(x: CGFloat(index - 1) * 12, y: CGFloat(1 - index) * 3)
                }
            }
        }
        .frame(width: 82, height: 82)
    }
}

private struct StageEditorRoute: Identifiable {
    let id = UUID()
    // 開いた時点のステージを保持し、削除後に閉じるアニメーション中も編集画面のまま表示する
    let stage: GameStage?
}

private struct ShareRoute: Identifiable {
    let id: UUID
}

private struct ReceiveRoute: Identifiable {
    let id = UUID()
    /// 共有リンクから開いたときのコード。手入力ならnil
    let code: String?
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
