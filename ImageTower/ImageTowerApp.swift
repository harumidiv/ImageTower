//
//  ImageTowerApp.swift
//  ImageTower
//
//  Created by harumi.sagawa on 2026/10/13.
//

import GoogleMobileAds
import SwiftUI

@main
struct ImageTowerApp: App {
    init() {
        MobileAds.shared.start(completionHandler: nil)
        // 「もういちど」を押したときにすぐ出せるよう、先に読み込んでおく
        InterstitialAdManager.shared.load()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
