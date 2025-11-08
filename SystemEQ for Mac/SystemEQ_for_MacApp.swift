//
//  SystemEQ_for_MacApp.swift
//  SystemEQ for Mac
//
//  Created by Denys Zamorniak on 07/10/25.
//

import SwiftUI

@main
struct SystemEQ_for_MacApp: App {
    @StateObject private var featureRegistry = FeatureRegistry()
    
    init() {
        // Запускаємо AutoEQ Python сервер при старті програми
        print("🚀 SystemEQ: Starting AutoEQ Python Server...")
        AutoEQServer.shared.startServer()
    }
    
    var body: some Scene {
        Window("SystemEQ for Mac", id: "main") {
            MainWindowView()
                .environmentObject(featureRegistry)
                .background(WindowAccessor(id: "main"))
        }
        .defaultSize(width: 360, height: 340)
        .windowResizability(.contentSize)
        Window("Calibration", id: FeatureID.calibration.rawValue) {
            CalibrationView()
                .background(WindowAccessor(id: FeatureID.calibration.rawValue))
        }
        Window("AutoEQ", id: FeatureID.autoeq.rawValue) {
            AutoEQView()
                .background(WindowAccessor(id: FeatureID.autoeq.rawValue))
        }
        Window("Routing", id: FeatureID.routing.rawValue) {
            RoutingView()
                .background(WindowAccessor(id: FeatureID.routing.rawValue))
        }
        Window("Settings", id: FeatureID.settings.rawValue) {
            SettingsView()
                .background(WindowAccessor(id: FeatureID.settings.rawValue))
        }
        Window("Visualizer", id: FeatureID.visualizer.rawValue) {
            VisualizerView()
                .background(WindowAccessor(id: FeatureID.visualizer.rawValue))
        }
        MenuBarExtra("SystemEQ", systemImage: "slider.horizontal.3") {
            MenuBarExtraView()
        }
    }
}
