import CoreGraphics
import SwiftUI

enum StackingDifficulty {
    nonisolated static func stars(for image: CGImage) -> Int? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let alphaOffset = 3
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var left = width
        var right = -1
        var top = height
        var bottom = -1
        var totalX = 0
        var pixelCount = 0

        for index in 0..<(width * height) where pixels[index * bytesPerPixel + alphaOffset] >= 128 {
            let x = index % width
            let y = index / width
            left = min(left, x)
            right = max(right, x)
            top = min(top, y)
            bottom = max(bottom, y)
            totalX += x
            pixelCount += 1
        }
        guard pixelCount > 0 else { return nil }

        let silhouetteWidth = Double(right - left + 1)
        let silhouetteHeight = bottom - top + 1
        let centerX = Double(totalX) / Double(pixelCount) + 0.5
        // Sample a shallow band at the bottom to allow for curved and antialiased edges.
        let supportBand = max(1, Int((Double(silhouetteHeight) * 0.03).rounded()))
        var supportLeft = right
        var supportRight = left
        for y in (bottom - supportBand + 1)...bottom {
            for x in left...right where pixels[(y * width + x) * bytesPerPixel + alphaOffset] >= 128 {
                supportLeft = min(supportLeft, x)
                supportRight = max(supportRight, x)
            }
        }

        let supportWidth = Double(supportRight - supportLeft + 1)
        let widthRatio = supportWidth / silhouetteWidth
        let heightRatio = supportWidth / Double(silhouetteHeight)
        let balance = min(centerX - Double(supportLeft), Double(supportRight + 1) - centerX) / silhouetteWidth

        if widthRatio < 0.32 || heightRatio < 0.28 || balance < 0.10 { return 3 }
        if widthRatio >= 0.65, heightRatio >= 0.65, balance >= 0.22 { return 1 }
        return 2
    }
}

struct StackingDifficultyRating: View {
    let asset: SubjectAsset
    @State private var stars: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let stars {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        title
                        starIcons(stars)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        title
                        starIcons(stars)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stacking difficulty")
                .accessibilityValue("\(stars) out of 3")
            }
        }
        .task(id: asset.id) {
            let image = asset.image
            let rating = await Task.detached(priority: .userInitiated) {
                TowerGameScene.collisionImage(for: image).cgImage.flatMap(StackingDifficulty.stars(for:))
            }.value
            guard !Task.isCancelled else { return }
            stars = rating
        }
    }

    private var title: some View {
        Text("Stacking difficulty")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(ImageTowerTheme.secondaryText)
    }

    private func starIcons(_ stars: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...3, id: \.self) { index in
                Image(systemName: index <= stars ? "star.fill" : "star")
                    .foregroundStyle(index <= stars ? ImageTowerTheme.orange : ImageTowerTheme.secondaryText)
            }
        }
        .font(.system(size: 9, weight: .semibold))
    }
}
