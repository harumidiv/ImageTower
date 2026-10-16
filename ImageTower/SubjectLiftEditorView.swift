import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Vision
import VisionKit

enum LiftAnalysisStatus: Equatable {
    case analyzing
    case ready
    case noSubject
    case unsupported
    case failed

    /// 切り抜きできない状態か
    var isError: Bool {
        switch self {
        case .noSubject, .unsupported, .failed: true
        case .analyzing, .ready: false
        }
    }

    var errorMessage: String? {
        switch self {
        case .noSubject: "被写体が見つからないため、この写真は切り抜きできません"
        case .unsupported: "この端末は被写体の切り抜きに対応していません"
        case .failed: "写真の解析に失敗しました。別の写真をお試しください"
        case .analyzing, .ready: nil
        }
    }
}

/// 写真の被写体を長押しし、透明背景の画像として受け取る画面。
/// Kuttuke の Subject Lift フローを ImageTower 用に移植している。
struct SubjectLiftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let photo: UIImage
    @ObservedObject var library: SubjectLibrary

    @State private var analysisStatus: LiftAnalysisStatus = .analyzing
    @State private var liftedSubject: UIImage?
    @State private var isDropTargeted = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [ImageTowerTheme.cream, ImageTowerTheme.paper],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    instruction
                    photoStage
                    transferArrow
                    dropZone
                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 12)

                if analysisStatus == .analyzing {
                    loadingOverlay(text: "切り抜きを準備しています…")
                }
                if isSaving {
                    loadingOverlay(text: "ゲーム用に整えています…")
                }
            }
            .navigationTitle("被写体を切り抜く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveSubject() }
                        .fontWeight(.bold)
                        .disabled(liftedSubject == nil || isSaving)
                }
            }
            .alert("保存できませんでした", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var instruction: some View {
        HStack(spacing: 12) {
            Text("1")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(ImageTowerTheme.coral, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("写真の被写体を長押し")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text("光ったら、指を離さず下へ運びます")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(ImageTowerTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 15)
        .frame(height: 60)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var photoStage: some View {
        ZStack {
            Color(red: 0.10, green: 0.12, blue: 0.13)

            LiftablePhotoView(image: photo) { status in
                withAnimation(.easeInOut(duration: 0.2)) { analysisStatus = status }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(7)

            VStack {
                HStack {
                    Spacer()
                    statusBadge
                }
                Spacer()
                if let message = analysisStatus.errorMessage {
                    Text(message)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.72), in: Capsule())
                }
            }
            .padding(13)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.75), lineWidth: 2))
        .frame(minHeight: 210, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch analysisStatus {
        case .analyzing:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small).tint(.white)
                Text("準備中")
            }
            .liftStatusCapsule()
        case .ready:
            Label("長押しできます", systemImage: "hand.tap.fill")
                .liftStatusCapsule()
        case .noSubject, .unsupported, .failed:
            Label("切り抜きできません", systemImage: "exclamationmark.triangle.fill")
                .liftStatusCapsule()
        }
    }

    private var transferArrow: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(ImageTowerTheme.coral)
            Text("長押しした被写体をここへ")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(ImageTowerTheme.secondaryText)
        }
        .frame(height: 18)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isDropTargeted ? ImageTowerTheme.coral.opacity(0.16) : .white.opacity(0.82))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isDropTargeted ? ImageTowerTheme.coral : ImageTowerTheme.secondaryText.opacity(0.28),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [8, 6])
                )

            if let liftedSubject {
                HStack(spacing: 17) {
                    Image(uiImage: liftedSubject)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.14), radius: 7, y: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Label("切り抜けました！", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.green)
                        Text("下のボタンで保存します")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(ImageTowerTheme.secondaryText)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: isDropTargeted ? "hand.point.down.fill" : "square.and.arrow.down")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(isDropTargeted ? ImageTowerTheme.coral : ImageTowerTheme.secondaryText)
                    Text(isDropTargeted ? "ここで指を離す" : "切り抜きを置く")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                    Text("透明な背景の画像として保存されます")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(ImageTowerTheme.secondaryText)
                }
            }

            SubjectDropReceiver(isTargeted: $isDropTargeted) { image in
                liftedSubject = image
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .frame(height: 132)
        .scaleEffect(isDropTargeted ? 1.015 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isDropTargeted)
    }

    private var saveButton: some View {
        Button(action: saveSubject) {
            Label("この切り抜きを保存", systemImage: "plus.circle.fill")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(ImageTowerTheme.ink, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(liftedSubject == nil || isSaving)
        .opacity(liftedSubject == nil ? 0.3 : 1)
    }

    private func loadingOverlay(text: String) -> some View {
        Color.black.opacity(0.22)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    ProgressView().tint(ImageTowerTheme.coral).scaleEffect(1.15)
                    Text(text)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 25)
                .padding(.vertical, 22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
    }

    private func saveSubject() {
        guard let liftedSubject, !isSaving else { return }
        isSaving = true
        Task {
            let savedID = await library.addLiftedSubject(liftedSubject)
            isSaving = false
            if savedID != nil {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}

struct LiftablePhotoView: UIViewRepresentable {
    let image: UIImage
    var isActive: Bool = true
    let onStatusChange: (LiftAnalysisStatus) -> Void

    init(image: UIImage, isActive: Bool = true, onStatusChange: @escaping (LiftAnalysisStatus) -> Void) {
        self.image = image
        self.isActive = isActive
        self.onStatusChange = onStatusChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStatusChange: onStatusChange)
    }

    func makeUIView(context: Context) -> LiftImageView {
        let imageView = LiftImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.image = image
        context.coordinator.setActive(isActive, on: imageView)
        context.coordinator.analyze(image)
        return imageView
    }

    func updateUIView(_ imageView: LiftImageView, context: Context) {
        context.coordinator.onStatusChange = onStatusChange
        context.coordinator.setActive(isActive, on: imageView)
        guard imageView.image !== image else { return }
        imageView.image = image
        context.coordinator.analyze(image)
    }

    static func dismantleUIView(_ imageView: LiftImageView, coordinator: Coordinator) {
        coordinator.analysisTask?.cancel()
        coordinator.interaction.analysis = nil
    }

    @MainActor
    final class Coordinator {
        let interaction = ImageAnalysisInteraction()
        var onStatusChange: (LiftAnalysisStatus) -> Void
        var analysisTask: Task<Void, Never>?

        init(onStatusChange: @escaping (LiftAnalysisStatus) -> Void) {
            self.onStatusChange = onStatusChange
            interaction.preferredInteractionTypes = [.imageSubject]
        }

        func setActive(_ isActive: Bool, on imageView: UIImageView) {
            let isAttached = interaction.view === imageView
            if isActive, !isAttached {
                imageView.addInteraction(interaction)
                interaction.setContentsRectNeedsUpdate()
            } else if !isActive, isAttached {
                imageView.removeInteraction(interaction)
            }
        }

        func analyze(_ image: UIImage) {
            analysisTask?.cancel()
            interaction.analysis = nil
            onStatusChange(.analyzing)

            guard ImageAnalyzer.isSupported else {
                onStatusChange(.unsupported)
                return
            }

            analysisTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let analyzer = ImageAnalyzer()
                    let analysis = try await analyzer.analyze(image, configuration: .init([]))
                    guard !Task.isCancelled else { return }
                    interaction.analysis = analysis
                    interaction.preferredInteractionTypes = [.imageSubject]
                    interaction.setContentsRectNeedsUpdate()
                    let hasSubject = await Self.detectsSubject(in: image)
                    guard !Task.isCancelled else { return }
                    onStatusChange(hasSubject ? .ready : .noSubject)
                } catch is CancellationError {
                    return
                } catch {
                    onStatusChange(.failed)
                }
            }
        }

        /// 画面に表示されていない写真でも判定できるよう、interaction ではなく Vision で被写体の有無を調べる。
        /// 判定自体に失敗した場合は長押しを妨げないよう「被写体あり」とみなす。
        nonisolated private static func detectsSubject(in image: UIImage) async -> Bool {
            guard let cgImage = image.cgImage else { return true }
            return await Task.detached(priority: .userInitiated) {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage)
                do {
                    try handler.perform([request])
                } catch {
                    return true
                }
                return request.results?.contains { !$0.allInstances.isEmpty } ?? false
            }.value
        }
    }
}

final class LiftImageView: UIImageView {
    override var intrinsicContentSize: CGSize { .zero }
}

struct SubjectDropReceiver: UIViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isTargeted: $isTargeted, onDrop: onDrop)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.isTargeted = $isTargeted
        context.coordinator.onDrop = onDrop
    }

    @MainActor
    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var isTargeted: Binding<Bool>
        var onDrop: (UIImage) -> Void

        init(isTargeted: Binding<Bool>, onDrop: @escaping (UIImage) -> Void) {
            self.isTargeted = isTargeted
            self.onDrop = onDrop
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier])
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            isTargeted.wrappedValue = true
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            isTargeted.wrappedValue = false
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            isTargeted.wrappedValue = false
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            isTargeted.wrappedValue = false
            guard let provider = session.items.lazy.map(\.itemProvider).first(where: {
                $0.canLoadObject(ofClass: UIImage.self)
            }) else { return }

            let dropHandler = onDrop
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in dropHandler(image) }
            }
        }
    }
}

private extension View {
    func liftStatusCapsule() -> some View {
        font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.black.opacity(0.68), in: Capsule())
    }
}
