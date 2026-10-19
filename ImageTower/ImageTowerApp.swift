//
//  ImageTowerApp.swift
//  ImageTower
//
//  Created by harumi.sagawa on 2026/10/13.
//

import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI

@main
struct ImageTowerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRequestedTracking = false

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // ATTダイアログはアプリがアクティブな状態でないと表示されないため、active になってから要求する
            guard phase == .active, !hasRequestedTracking else { return }
            hasRequestedTracking = true
            Task { @MainActor in
                _ = await ATTrackingManager.requestTrackingAuthorization()
                // 許可の結果を広告リクエストに反映させるため、ATTの回答後に広告SDKを開始する
                MobileAds.shared.start(completionHandler: nil)
                // 「もういちど」を押したときにすぐ出せるよう、先に読み込んでおく
                InterstitialAdManager.shared.load()
            }
        }
    }
}
