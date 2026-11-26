import GameKit
import OSLog
import SwiftUI
import UIKit

@MainActor
final class GameCenter {
    static let shared = GameCenter()

    enum Dashboard {
        case leaderboards
        case leaderboard(itemCount: Int)
        case achievements
    }

    private static let rankedItemCounts = SubjectLibrary.minimumPlayableItems...SubjectLibrary.maximumStageItems
    private static let personalBestID = "imagetower.personal_best"
    private static let milestones: [(score: Int, id: String)] = [
        (1, "imagetower.stack_1"),
        (5, "imagetower.stack_5"),
        (10, "imagetower.stack_10"),
        (20, "imagetower.stack_20"),
    ]

    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "harumidiv.ImageTower", category: "GameCenter")
    private var signInController: UIViewController?
    private var hasStarted = false
    private var syncingPlayers: Set<String> = []

    private init() {}

    func start() {
        guard !hasStarted else {
            sync()
            return
        }
        hasStarted = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                self.signInController = controller
                if let errorMessage {
                    self.logger.info("Authentication: \(errorMessage)")
                }
                self.sync()
            }
        }
    }

    func show(_ dashboard: Dashboard) -> Bool {
        start()
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.keyWindow
        guard let window else { return false }

        if !GKLocalPlayer.local.isAuthenticated {
            guard let signInController, let root = window.rootViewController else { return false }
            guard root.presentedViewController == nil else { return false }
            root.present(signInController, animated: true)
            return true
        }

        let accessPoint = GKAccessPoint.shared
        guard !accessPoint.isPresentingGameCenter else { return true }
        accessPoint.parentWindow = window
        switch dashboard {
        case .leaderboards:
            accessPoint.trigger(state: .leaderboards) {}
        case .leaderboard(let itemCount):
            accessPoint.trigger(leaderboardID: Self.leaderboardID(for: itemCount), playerScope: .global, timeScope: .allTime)
        case .achievements:
            accessPoint.trigger(state: .achievements) {}
        }
        return true
    }

    func recordFinishedScore(_ score: Int, itemCount: Int, beatPersonalBest: Bool) {
        let player = GKLocalPlayer.local
        guard score > 0, player.isAuthenticated else { return }
        let key = Self.storageKey(for: player.gamePlayerID)
        let scoreKey = key + ".items\(itemCount)"
        if Self.rankedItemCounts.contains(itemCount), score > defaults.integer(forKey: scoreKey) {
            defaults.set(score, forKey: scoreKey)
        }
        if score > defaults.integer(forKey: key + ".highest") {
            defaults.set(score, forKey: key + ".highest")
        }
        if beatPersonalBest { defaults.set(true, forKey: key + ".beatPersonalBest") }
        sync()
    }

    private static func storageKey(for playerID: String) -> String {
        "imagetower.game-center.v1.\(playerID)"
    }

    private static func leaderboardID(for itemCount: Int) -> String {
        "imagetower.items\(itemCount)"
    }

    private struct Progress: Equatable {
        let scores: [Int]
        let highest: Int
        let beatPersonalBest: Bool
    }

    private func progress(for key: String) -> Progress {
        Progress(
            scores: Self.rankedItemCounts.map { defaults.integer(forKey: key + ".items\($0)") },
            highest: defaults.integer(forKey: key + ".highest"),
            beatPersonalBest: defaults.bool(forKey: key + ".beatPersonalBest")
        )
    }

    private func sync() {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return }
        let playerID = player.gamePlayerID
        let key = Self.storageKey(for: playerID)
        guard defaults.integer(forKey: key + ".highest") > 0,
              syncingPlayers.insert(playerID).inserted else { return }

        Task {
            defer { syncingPlayers.remove(playerID) }
            // A game may finish while a GameKit request is in flight.
            var snapshot: Progress
            repeat {
                snapshot = progress(for: key)
                for (itemCount, score) in zip(Self.rankedItemCounts, snapshot.scores) {
                    guard player.isAuthenticated, player.gamePlayerID == playerID else { return }
                    await submitScore(score, itemCount: itemCount, player: player, key: key + ".items\(itemCount).submitted")
                }
                guard player.isAuthenticated, player.gamePlayerID == playerID else { return }
                await reportAchievements(for: snapshot, key: key)
            } while snapshot != progress(for: key)
        }
    }

    private func submitScore(_ score: Int, itemCount: Int, player: GKLocalPlayer, key: String) async {
        guard score > defaults.integer(forKey: key) else { return }
        do {
            try await GKLeaderboard.submitScore(score, context: 0, player: player, leaderboardIDs: [Self.leaderboardID(for: itemCount)])
            defaults.set(score, forKey: key)
        } catch {
            logger.error("Leaderboard submission failed: \(error.localizedDescription)")
        }
    }

    private func reportAchievements(for progress: Progress, key: String) async {
        let scoreKey = key + ".achievements"
        let personalBestKey = key + ".personalBestReported"
        let lastReportedScore = defaults.integer(forKey: scoreKey)
        var identifiers = Self.milestones
            .filter { lastReportedScore < $0.score && $0.score <= progress.highest }
            .map(\.id)
        let reportPersonalBest = progress.beatPersonalBest && !defaults.bool(forKey: personalBestKey)
        if reportPersonalBest { identifiers.append(Self.personalBestID) }
        guard !identifiers.isEmpty else { return }

        let achievements = identifiers.map { identifier in
            let achievement = GKAchievement(identifier: identifier)
            achievement.percentComplete = 100
            achievement.showsCompletionBanner = true
            return achievement
        }
        do {
            try await GKAchievement.report(achievements)
            defaults.set(progress.highest, forKey: scoreKey)
            if reportPersonalBest { defaults.set(true, forKey: personalBestKey) }
        } catch {
            logger.error("Achievement reporting failed: \(error.localizedDescription)")
        }
    }
}

extension View {
    func gameCenterSignInAlert(isPresented: Binding<Bool>) -> some View {
        alert("Game Center", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign in to Game Center in Settings, then try again.")
        }
    }
}
