import Foundation
import AppTrackingTransparency
import SwiftUI

protocol AdServing {
    /// true: パーソナライズ広告許可（ATT許諾済み）
    func requestATTIfNeeded() async -> Bool
    func bannerView() -> AnyView
    func preloadInterstitial()
    func showInterstitialIfReady()
}

/// 広告SDK（Google AdMob）連携のプレースホルダー実装。
/// 実際のGoogleMobileAds SDKはXcode側でSwift Package Managerとして追加後、
/// この実装を`GoogleMobileAds`ベースのものに置き換える（要件定義書8章・詳細設計書4.11参照）。
/// ATT許諾フローのみ実SDKに依存しないため先行実装している。
final class AdService: AdServing {
    func requestATTIfNeeded() async -> Bool {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            return ATTrackingManager.trackingAuthorizationStatus == .authorized
        }
        let status = await ATTrackingManager.requestTrackingAuthorization()
        return status == .authorized
    }

    func bannerView() -> AnyView {
        // TODO: GoogleMobileAds導入後、GADBannerViewをUIViewRepresentableでラップして差し替える
        AnyView(EmptyView())
    }

    func preloadInterstitial() {
        // TODO: GoogleMobileAds導入後に実装
    }

    func showInterstitialIfReady() {
        // TODO: GoogleMobileAds導入後に実装
    }
}
