// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "flutter_native_splash", path: "../.packages/flutter_native_splash-2.4.6"),
        .package(name: "shared_preferences_foundation", path: "../.packages/shared_preferences_foundation-2.5.4"),
        .package(name: "google_mobile_ads", path: "../.packages/google_mobile_ads-9.1.0"),
        .package(name: "webview_flutter_wkwebview", path: "../.packages/webview_flutter_wkwebview-3.25.1"),
        .package(name: "path_provider_foundation", path: "../.packages/path_provider_foundation-2.4.1"),
        .package(name: "audioplayers_darwin", path: "../.packages/audioplayers_darwin-6.3.0"),
        .package(name: "app_tracking_transparency", path: "../.packages/app_tracking_transparency-2.0.7"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "flutter-native-splash", package: "flutter_native_splash"),
                .product(name: "shared-preferences-foundation", package: "shared_preferences_foundation"),
                .product(name: "google-mobile-ads", package: "google_mobile_ads"),
                .product(name: "webview-flutter-wkwebview", package: "webview_flutter_wkwebview"),
                .product(name: "path-provider-foundation", package: "path_provider_foundation"),
                .product(name: "audioplayers-darwin", package: "audioplayers_darwin"),
                .product(name: "app-tracking-transparency", package: "app_tracking_transparency"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
