import SpriteKit
import UIKit

final class TowerGameScene: SKScene, SKPhysicsContactDelegate {
    var onScore: ((Int) -> Void)?
    var onNextImage: ((Int) -> Void)?
    var onFirstDrop: (() -> Void)?
    var onLand: (() -> Void)?
    var onGameOver: (() -> Void)?

    private let textures: [SKTexture]
    private let physicsTextures: [SKTexture]
    private let itemCategory: UInt32 = 1 << 0
    private let platformCategory: UInt32 = 1 << 1
    private let gameCamera = SKCameraNode()

    private var heldNode: SKSpriteNode?
    /// 回転ボタンで決めた、持っているアイテムの角度（アニメーション途中でも落下時はこの角度にする）
    private var heldRotation: CGFloat = 0
    private weak var activeTouch: UITouch?
    private weak var latestDroppedNode: SKSpriteNode?
    private var upcomingIndices: [Int] = []
    private var lastSpawnIndex: Int?
    private var score = 0
    private var isGameFinished = false
    private var didBuildWorld = false
    private var didDropOnce = false

    private let itemName = "tower-item"
    private let heldName = "held-item"
    private let aimGuideName = "aim-guide"
    private let platformName = "platform"
    private static let towerTopScreenRatio: CGFloat = 0.55
    private static let maximumFallSpeed: CGFloat = 520

    init(images: [UIImage]) {
        textures = images.map {
            let texture = SKTexture(image: $0)
            texture.filteringMode = .linear
            return texture
        }
        physicsTextures = images.map {
            SKTexture(image: Self.downscaled($0, to: 96))
        }
        super.init(size: CGSize(width: 390, height: 700))
        scaleMode = .resizeFill
        backgroundColor = ImageTowerTheme.uiSky
        physicsWorld.gravity = CGVector(dx: 0, dy: -10.5)
        physicsWorld.contactDelegate = self
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        view.backgroundColor = ImageTowerTheme.uiSky
        buildWorldIfNeeded()
        prepareNextTurn()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didBuildWorld else { return }
        gameCamera.position.x = size.width / 2
        if gameCamera.position.y < size.height / 2 {
            gameCamera.position.y = size.height / 2
        }
        rebuildPlatform()
        rebuildCameraDecoration()
        updateHeldNodePosition()
    }

    func resetGame() {
        removeAllActions()
        enumerateChildNodes(withName: itemName) { node, _ in node.removeFromParent() }
        heldNode?.removeFromParent()
        childNode(withName: aimGuideName)?.removeFromParent()
        heldNode = nil
        latestDroppedNode = nil
        activeTouch = nil
        upcomingIndices.removeAll(keepingCapacity: true)
        score = 0
        isGameFinished = false
        didDropOnce = false
        gameCamera.removeAllActions()
        gameCamera.position = CGPoint(x: size.width / 2, y: size.height / 2)
        onScore?(0)
        prepareNextTurn()
    }

    func endGame() {
        finishGame()
    }

    /// 土台からタワーの頂上までを1枚の画像に書き出す（SNS共有用）
    /// 画面より高く積んだときは、そのぶん縦長の画像になる
    func towerSnapshotImage() -> UIImage? {
        guard let view, size.width > 0, size.height > 0 else { return nil }

        var towerTop: CGFloat = 0
        enumerateChildNodes(withName: itemName) { node, _ in
            guard let sprite = node as? SKSpriteNode else { return }
            towerTop = max(towerTop, sprite.frame.maxY)
        }
        let bottom: CGFloat = 0
        let top = max(size.height, towerTop + 70)
        let totalHeight = top - bottom

        // 1回で書き出せるテクスチャの大きさには上限があるため、画面の高さごとに分けて書き出してつなげる
        var slices: [(image: UIImage, minY: CGFloat, height: CGFloat)] = []
        var sliceMinY = bottom
        while sliceMinY < top {
            let sliceHeight = min(size.height, top - sliceMinY)
            let crop = CGRect(x: 0, y: sliceMinY, width: size.width, height: sliceHeight)
            guard let texture = view.texture(from: self, crop: crop) else { return nil }
            slices.append((UIImage(cgImage: texture.cgImage()), sliceMinY, sliceHeight))
            sliceMinY += sliceHeight
        }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        // 縦長になりすぎても画像が大きくなりすぎないよう、長辺を約6000pxに抑える
        format.scale = min(view.contentScaleFactor, 6000 / max(totalHeight, size.width))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width, height: totalHeight), format: format)
        return renderer.image { _ in
            for slice in slices {
                // シーンは上が+Y、画像は上が0なので上下を変換して並べる
                let y = top - (slice.minY + slice.height)
                slice.image.draw(in: CGRect(x: 0, y: y, width: size.width, height: slice.height))
            }
        }
    }

    private func buildWorldIfNeeded() {
        guard !didBuildWorld else { return }
        didBuildWorld = true
        addChild(gameCamera)
        camera = gameCamera
        gameCamera.position = CGPoint(x: size.width / 2, y: size.height / 2)
        rebuildPlatform()
        rebuildCameraDecoration()
    }

    private func rebuildPlatform() {
        childNode(withName: platformName)?.removeFromParent()

        let width = min(size.width * 0.72, 300)
        let height: CGFloat = 24
        let platform = SKSpriteNode(color: UIColor(red: 0.48, green: 0.28, blue: 0.16, alpha: 1), size: CGSize(width: width, height: height))
        platform.name = platformName
        platform.position = CGPoint(x: size.width / 2, y: 72)
        platform.zPosition = 4
        platform.physicsBody = SKPhysicsBody(rectangleOf: platform.size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.restitution = 0
        platform.physicsBody?.friction = 1
        platform.physicsBody?.categoryBitMask = platformCategory
        platform.physicsBody?.collisionBitMask = itemCategory
        platform.physicsBody?.contactTestBitMask = itemCategory

        let top = SKSpriteNode(color: UIColor(red: 0.72, green: 0.46, blue: 0.24, alpha: 1), size: CGSize(width: width + 10, height: 8))
        top.position.y = height / 2
        top.zPosition = 1
        platform.addChild(top)

        let leftLeg = SKSpriteNode(color: UIColor(red: 0.38, green: 0.22, blue: 0.13, alpha: 1), size: CGSize(width: 18, height: 44))
        leftLeg.position = CGPoint(x: -width * 0.32, y: -28)
        platform.addChild(leftLeg)
        let rightLeg = leftLeg.copy() as! SKSpriteNode
        rightLeg.position.x = width * 0.32
        platform.addChild(rightLeg)
        addChild(platform)
    }

    private func rebuildCameraDecoration() {
        gameCamera.childNode(withName: "camera-decoration")?.removeFromParent()
        let decoration = SKNode()
        decoration.name = "camera-decoration"
        decoration.zPosition = -50

        let sun = SKShapeNode(circleOfRadius: 38)
        sun.fillColor = UIColor(red: 1, green: 0.82, blue: 0.30, alpha: 0.92)
        sun.strokeColor = .clear
        sun.position = CGPoint(x: size.width * 0.34, y: size.height * 0.32)
        decoration.addChild(sun)

        decoration.addChild(makeCloud(at: CGPoint(x: -size.width * 0.31, y: size.height * 0.27), scale: 1.05))
        decoration.addChild(makeCloud(at: CGPoint(x: size.width * 0.29, y: size.height * 0.10), scale: 0.72))
        decoration.addChild(makeCloud(at: CGPoint(x: -size.width * 0.18, y: -size.height * 0.05), scale: 0.52))
        gameCamera.addChild(decoration)
    }

    private func makeCloud(at position: CGPoint, scale: CGFloat) -> SKNode {
        let cloud = SKNode()
        cloud.position = position
        cloud.setScale(scale)
        for (offset, radius) in [(CGPoint(x: -24, y: 0), CGFloat(22)),
                                 (CGPoint(x: 0, y: 8), CGFloat(29)),
                                 (CGPoint(x: 28, y: 0), CGFloat(20))] {
            let puff = SKShapeNode(circleOfRadius: radius)
            puff.position = offset
            puff.fillColor = UIColor.white.withAlphaComponent(0.62)
            puff.strokeColor = .clear
            cloud.addChild(puff)
        }
        return cloud
    }

    private func prepareNextTurn() {
        guard !isGameFinished, heldNode == nil, !textures.isEmpty else { return }
        fillQueue(to: 2)
        let imageIndex = upcomingIndices.removeFirst()
        fillQueue(to: 1)
        onNextImage?(upcomingIndices[0])

        let side = itemSide()
        let node = SKSpriteNode(texture: textures[imageIndex], size: CGSize(width: side, height: side))
        node.name = heldName
        node.zPosition = 12
        node.userData = NSMutableDictionary()
        node.userData?["imageIndex"] = imageIndex
        node.userData?["baseScale"] = CGFloat(1)
        node.position = CGPoint(x: size.width / 2, y: heldHeight)
        heldRotation = 0
        node.zRotation = heldRotation
        node.alpha = 0
        node.setScale(0.72)
        addChild(node)
        heldNode = node
        updateAimGuide(x: node.position.x)
        node.run(.group([
            .fadeIn(withDuration: 0.15),
            .scale(to: 1, duration: 0.22)
        ]))
    }

    private func fillQueue(to count: Int) {
        while upcomingIndices.count < count {
            var candidate = Int.random(in: textures.indices)
            if textures.count > 1, candidate == lastSpawnIndex {
                candidate = (candidate + Int.random(in: 1..<textures.count)) % textures.count
            }
            upcomingIndices.append(candidate)
            lastSpawnIndex = candidate
        }
    }

    private func itemSide() -> CGFloat {
        let base = min(max(size.width * 0.245, 78), 112)
        return base * CGFloat.random(in: 0.86...1.08)
    }

    private var heldHeight: CGFloat {
        gameCamera.position.y + size.height * 0.39
    }

    private func updateHeldNodePosition() {
        guard let heldNode else { return }
        heldNode.position.y = heldHeight
        heldNode.position.x = clampedX(heldNode.position.x, for: heldNode)
        updateAimGuide(x: heldNode.position.x)
    }

    private func updateAimGuide(x: CGFloat) {
        childNode(withName: aimGuideName)?.removeFromParent()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: heldHeight - 46))
        path.addLine(to: CGPoint(x: x, y: gameCamera.position.y - size.height * 0.25))
        let line = SKShapeNode(path: path)
        line.name = aimGuideName
        line.strokeColor = UIColor.white.withAlphaComponent(0.62)
        line.lineWidth = 2
        line.zPosition = 2
        addChild(line)
    }

    private func clampedX(_ x: CGFloat, for node: SKSpriteNode) -> CGFloat {
        let margin = node.size.width * 0.40
        return min(max(x, margin), size.width - margin)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameFinished, activeTouch == nil, let touch = touches.first, let heldNode else { return }
        activeTouch = touch
        heldNode.position.x = clampedX(touch.location(in: self).x, for: heldNode)
        updateAimGuide(x: heldNode.position.x)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch), let heldNode else { return }
        heldNode.position.x = clampedX(activeTouch.location(in: self).x, for: heldNode)
        updateAimGuide(x: heldNode.position.x)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch), let heldNode else { return }
        self.activeTouch = nil
        heldNode.position.x = clampedX(activeTouch.location(in: self).x, for: heldNode)
        drop(heldNode)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        self.activeTouch = nil
    }

    /// 持っているアイテムを45°ずつ時計回りに回す
    @discardableResult
    func rotateHeldItem() -> Bool {
        guard !isGameFinished, let heldNode else { return false }
        heldRotation -= .pi / 4
        heldNode.removeAction(forKey: "rotate")
        let rotate = SKAction.rotate(toAngle: heldRotation, duration: 0.12, shortestUnitArc: true)
        rotate.timingMode = .easeOut
        heldNode.run(rotate, withKey: "rotate")
        return true
    }

    private func drop(_ node: SKSpriteNode) {
        guard node === heldNode, !isGameFinished else { return }
        node.removeAllActions()
        node.setScale(1)
        node.alpha = 1
        node.zRotation = heldRotation
        node.name = itemName
        childNode(withName: aimGuideName)?.removeFromParent()

        let imageIndex = node.userData?["imageIndex"] as? Int ?? 0
        let body = SKPhysicsBody(texture: physicsTextures[imageIndex], size: node.size)
        body.friction = 0.9
        body.restitution = 0
        body.linearDamping = 0.45
        body.angularDamping = 1.4
        body.density = 0.95
        body.allowsRotation = true
        body.categoryBitMask = itemCategory
        body.collisionBitMask = itemCategory | platformCategory
        body.contactTestBitMask = itemCategory | platformCategory
        body.usesPreciseCollisionDetection = false
        node.physicsBody = body

        heldNode = nil
        latestDroppedNode = node
        if !didDropOnce {
            didDropOnce = true
            onFirstDrop?()
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard !isGameFinished, let dropped = latestDroppedNode else { return }
        guard contact.bodyA.node === dropped || contact.bodyB.node === dropped else { return }
        guard dropped.action(forKey: "confirm-placement") == nil else { return }

        onLand?()
        dropped.run(.sequence([
            .wait(forDuration: 0.48),
            .run { [weak self, weak dropped] in
                guard let self, let dropped else { return }
                self.confirmPlacement(of: dropped)
            }
        ]), withKey: "confirm-placement")
    }

    private func confirmPlacement(of node: SKSpriteNode) {
        guard !isGameFinished, latestDroppedNode === node, node.parent != nil, node.position.y > -node.size.height else { return }
        latestDroppedNode = nil
        score += 1
        onScore?(score)
        prepareNextTurn()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGameFinished else { return }

        // 高所から勢いよくぶつかって周りを弾き飛ばさないよう、落下速度に上限を設ける
        if let body = latestDroppedNode?.physicsBody, body.velocity.dy < -Self.maximumFallSpeed {
            body.velocity.dy = -Self.maximumFallSpeed
        }

        var highestPoint: CGFloat = 0
        var fallenNodeFound = false
        enumerateChildNodes(withName: itemName) { node, stop in
            guard let sprite = node as? SKSpriteNode else { return }
            // 落下中のアイテムでカメラが上がらないよう、着地して落ち着いたものだけで高さを測る
            let isSettled = sprite !== self.latestDroppedNode
                && abs(sprite.physicsBody?.velocity.dy ?? 0) < 40
            if isSettled {
                highestPoint = max(highestPoint, sprite.position.y + sprite.size.height * 0.5)
            }
            if sprite.position.y < -sprite.size.height || abs(sprite.position.x - self.size.width / 2) > self.size.width * 1.25 {
                fallenNodeFound = true
                stop.pointee = true
            }
        }

        if fallenNodeFound {
            finishGame()
            return
        }

        // タワーの頂上が画面の下から towerTopScreenRatio を超えたぶんだけ、少しずつ上へスクロールする
        let desiredCameraY = max(size.height / 2, highestPoint + size.height * (0.5 - Self.towerTopScreenRatio))
        if desiredCameraY > gameCamera.position.y + 1 {
            gameCamera.position.y += min((desiredCameraY - gameCamera.position.y) * 0.03, 4)
            updateHeldNodePosition()
        }
    }

    private func finishGame() {
        guard !isGameFinished else { return }
        isGameFinished = true
        activeTouch = nil
        heldNode?.removeFromParent()
        heldNode = nil
        childNode(withName: aimGuideName)?.removeFromParent()
        onGameOver?()
    }

    nonisolated private static func downscaled(_ image: UIImage, to pixels: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
    }
}
