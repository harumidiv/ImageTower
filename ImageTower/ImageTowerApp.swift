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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
