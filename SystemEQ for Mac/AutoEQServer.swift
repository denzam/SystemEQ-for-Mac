import Foundation

/// Клас для керування локальним AutoEQ Python сервером
class AutoEQServer {
    static let shared = AutoEQServer()
    
    private var serverProcess: Process?
    private let serverURL = URL(string: "http://127.0.0.1:5555")!
    private var isServerRunning = false
    
    private init() {}
    
    /// Запускає локальний Python сервер
    func startServer() {
        guard !isServerRunning else {
            print("AutoEQ Server: Already running")
            return
        }
        
        // Визначаємо шлях до проекту
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let projectPath = homeDir + "/CascadeProjects/SystemEQ for Mac"
        let serverScriptPath = projectPath + "/start_server.sh"
        
        print("AutoEQ Server: Starting server...")
        print("AutoEQ Server: Project path: \(projectPath)")
        print("AutoEQ Server: Script path: \(serverScriptPath)")
        
        // Перевіряємо чи існує скрипт
        guard FileManager.default.fileExists(atPath: serverScriptPath) else {
            print("AutoEQ Server: ❌ start_server.sh not found at \(serverScriptPath)")
            return
        }
        
        serverProcess = Process()
        serverProcess?.executableURL = URL(fileURLWithPath: "/bin/bash")
        serverProcess?.arguments = [serverScriptPath]
        serverProcess?.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        
        // Redirect output
        let pipe = Pipe()
        serverProcess?.standardOutput = pipe
        serverProcess?.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("AutoEQ Server: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        do {
            try serverProcess?.run()
            isServerRunning = true
            print("AutoEQ Server: Started successfully")
            
            // Чекаємо поки сервер запуститься
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 секунди
                _ = await checkServerHealth()
            }
        } catch {
            print("AutoEQ Server: Failed to start: \(error)")
        }
    }
    
    /// Зупиняє локальний Python сервер
    func stopServer() {
        guard isServerRunning else { return }
        
        print("AutoEQ Server: Stopping...")
        serverProcess?.terminate()
        serverProcess = nil
        isServerRunning = false
        print("AutoEQ Server: Stopped")
    }
    
    /// Перевіряє чи працює сервер
    func checkServerHealth() async -> Bool {
        let healthURL = serverURL.appendingPathComponent("health")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: healthURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return false
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String,
               status == "ok" {
                print("AutoEQ Server: Health check OK")
                return true
            }
        } catch {
            print("AutoEQ Server: Health check failed: \(error)")
        }
        
        return false
    }
    
    /// Обчислює GraphicEQ значення для заданого вимірювання
    func calculateGraphicEQ(
        measurementName: String,
        targetName: String = "JM-1 with Harman filters",
        bandCount: Int
    ) async throws -> (bands: [(freq: Double, gain: Double)], preamp: Double) {
        
        let equalizeURL = serverURL.appendingPathComponent("equalize")
        var request = URLRequest(url: equalizeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "measurement_name": measurementName,
            "target_name": targetName,
            "band_count": bandCount
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("AutoEQ Server: Requesting GraphicEQ...")
        print("AutoEQ Server: Measurement: \(measurementName)")
        print("AutoEQ Server: Target: \(targetName)")
        print("AutoEQ Server: Band count: \(bandCount)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AutoEQServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        print("AutoEQ Server: Response status: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AutoEQServer", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        // Парсимо відповідь
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bandsArray = json["bands"] as? [[String: Any]],
              let preamp = json["preamp"] as? Double else {
            throw NSError(domain: "AutoEQServer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        var bands: [(freq: Double, gain: Double)] = []
        for bandDict in bandsArray {
            guard let freq = bandDict["freq"] as? Double,
                  let gain = bandDict["gain"] as? Double else {
                continue
            }
            bands.append((freq: freq, gain: gain))
        }
        
        print("AutoEQ Server: Successfully received \(bands.count) bands")
        
        return (bands: bands, preamp: preamp)
    }
    
    deinit {
        stopServer()
    }
}
