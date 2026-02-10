// SMCHelperClient.swift - 通过 Unix Socket 与 Helper Daemon 通信

import Foundation
import MacFanControlCore
// MARK: - SMC Helper (通过 Unix Socket 与 daemon 通信)

final class SMCHelperClient: FanControlProvider, @unchecked Sendable {
    static let shared = SMCHelperClient()

    private let socketPath = "/var/run/com.macfancontrol.smchelper.sock"
    private let helperPath = "/Library/PrivilegedHelperTools/com.macfancontrol.smchelper"

    private init() {}

    var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: socketPath) ||
        FileManager.default.fileExists(atPath: helperPath)
    }

    var isDaemonRunning: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    // MARK: - FanControlProvider

    var isAvailable: Bool { isDaemonRunning }

    func getFanCount() -> Int {
        getFanInfo()?.fanCount ?? 0
    }

    func getFanData() -> [FanDataSnapshot] {
        guard let info = getFanInfo() else { return [] }
        return info.fans.map { fan in
            FanDataSnapshot(
                index: fan.index,
                currentSpeed: Int(fan.currentSpeed),
                minSpeed: Int(fan.minSpeed),
                maxSpeed: Int(fan.maxSpeed),
                mode: fan.mode
            )
        }
    }

    struct FanData: Codable {
        let index: Int
        let currentSpeed: Double
        let minSpeed: Double
        let maxSpeed: Double
        let targetSpeed: Double
        let mode: Int
    }

    struct FanInfo: Codable {
        let fanCount: Int
        let fans: [FanData]
    }

    struct TempData: Codable {
        let key: String
        let name: String
        let value: Double
    }

    struct TempInfo: Codable {
        let temperatures: [TempData]
    }

    func getFanInfo() -> FanInfo? {
        guard let output = sendCommand("info") else { return nil }
        guard let data = output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FanInfo.self, from: data)
    }

    func getTemperatures() -> TempInfo? {
        guard let output = sendCommand("temp") else { return nil }
        guard let data = output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TempInfo.self, from: data)
    }

    func setFanSpeed(_ rpm: Int) -> Bool {
        guard let output = sendCommand("speed \(rpm)") else { return false }
        return output.contains("success")
    }

    func resetToAuto() -> Bool {
        guard let output = sendCommand("auto") else { return false }
        return output.contains("success")
    }

    /// 通过 Unix Socket 发送命令
    private func sendCommand(_ command: String) -> String? {
        // 首先尝试 socket 通信
        if isDaemonRunning {
            if let result = sendViaSocket(command) {
                return result
            }
        }
        return nil
    }

    private func sendViaSocket(_ command: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // 设置超时 (2秒)
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // 复制 socket 路径
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        // 连接
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else { return nil }

        // 发送命令
        let cmdData = command + "\n"
        _ = cmdData.withCString { cstr in
            write(fd, cstr, strlen(cstr))
        }

        // 读取响应
        var buffer = [CChar](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count - 1)
        guard bytesRead > 0 else { return nil }

        return String(cString: buffer)
    }

    // MARK: - 自动安装 Helper Daemon

    /// 检查并安装 Helper (如果需要)
    func installHelperIfNeeded(completion: @escaping (Bool, String?) -> Void) {
        if isDaemonRunning {
            completion(true, nil)
            return
        }

        // 获取 helper 源文件路径
        let bundle = Bundle.main
        guard let helperSource = bundle.path(forResource: "smc_helper", ofType: nil) ??
              findHelperInAppBundle() else {
            // 尝试从应用目录查找
            let appDir = bundle.bundlePath
            let possiblePaths = [
                (appDir as NSString).deletingLastPathComponent + "/smc_helper",
                FileManager.default.currentDirectoryPath + "/smc_helper",
                FileManager.default.currentDirectoryPath + "/.build/debug/smc_helper",
            ]

            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    installHelper(from: path, completion: completion)
                    return
                }
            }

            completion(false, "找不到 smc_helper 文件")
            return
        }

        installHelper(from: helperSource, completion: completion)
    }

    private func findHelperInAppBundle() -> String? {
        let bundle = Bundle.main
        let appPath = bundle.bundlePath

        // 检查 Contents/Resources 目录 (标准位置)
        let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources/smc_helper")
        if FileManager.default.fileExists(atPath: resourcesPath) {
            return resourcesPath
        }

        // 检查 Contents/MacOS 目录
        let macosPath = (appPath as NSString).appendingPathComponent("Contents/MacOS/smc_helper")
        if FileManager.default.fileExists(atPath: macosPath) {
            return macosPath
        }

        // 检查 bundle.resourcePath
        if let resourceDir = bundle.resourcePath {
            let path = (resourceDir as NSString).appendingPathComponent("smc_helper")
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func installHelper(from sourcePath: String, completion: @escaping (Bool, String?) -> Void) {
        // 构建 plist 内容
        let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.macfancontrol.smchelper</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/Library/PrivilegedHelperTools/com.macfancontrol.smchelper</string>
                    <string>daemon</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
                <key>StandardErrorPath</key>
                <string>/var/log/com.macfancontrol.smchelper.log</string>
            </dict>
            </plist>
            """

        // 将 plist 写入临时文件
        let tempPlistPath = "/tmp/com.macfancontrol.smchelper.plist"
        do {
            try plistContent.write(toFile: tempPlistPath, atomically: true, encoding: .utf8)
        } catch {
            completion(false, "无法创建临时文件")
            return
        }

        let script = "do shell script \"launchctl unload /Library/LaunchDaemons/com.macfancontrol.smchelper.plist 2>/dev/null || true; mkdir -p /Library/PrivilegedHelperTools; cp '\(sourcePath)' /Library/PrivilegedHelperTools/com.macfancontrol.smchelper; chown root:wheel /Library/PrivilegedHelperTools/com.macfancontrol.smchelper; chmod 755 /Library/PrivilegedHelperTools/com.macfancontrol.smchelper; cp '\(tempPlistPath)' /Library/LaunchDaemons/com.macfancontrol.smchelper.plist; chown root:wheel /Library/LaunchDaemons/com.macfancontrol.smchelper.plist; chmod 644 /Library/LaunchDaemons/com.macfancontrol.smchelper.plist; launchctl load /Library/LaunchDaemons/com.macfancontrol.smchelper.plist\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)

                // 等待 daemon 启动
                Thread.sleep(forTimeInterval: 1.0)

                DispatchQueue.main.async {
                    if self.isDaemonRunning {
                        completion(true, nil)
                    } else if let err = error {
                        completion(false, err["NSAppleScriptErrorMessage"] as? String ?? "安装失败")
                    } else {
                        completion(false, "Daemon 启动失败")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(false, "无法创建安装脚本")
                }
            }
        }
    }
}
