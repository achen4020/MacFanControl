// HelperConnection.swift - 主应用与 Helper Tool 的 XPC 连接管理

import Foundation
import ServiceManagement
import Security
import AppKit

/// Helper Tool 连接管理器
class HelperConnection {
    static let shared = HelperConnection()

    private var connection: NSXPCConnection?
    private var helperProxy: HelperToolProtocol?

    /// Helper 是否已安装
    var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/\(kHelperToolMachServiceName)")
    }

    private init() {}

    // MARK: - 安装 Helper

    /// 安装 Helper Tool (需要管理员权限)
    func installHelper() async throws -> Bool {
        // 使用 SMAppService (macOS 13+)
        return try await installHelperViaSMAppService()
    }

    private func installHelperViaSMAppService() async throws -> Bool {
        let service = SMAppService.daemon(plistName: "com.macfancontrol.helper.plist")

        switch service.status {
        case .notRegistered:
            try service.register()
            print("Helper registered via SMAppService")
            return true

        case .enabled:
            print("Helper already enabled")
            return true

        case .requiresApproval:
            print("Helper requires approval in System Settings")
            // 打开系统设置
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            return false

        case .notFound:
            print("Helper plist not found")
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - 连接管理

    /// 获取 Helper 代理
    func getHelper() throws -> HelperToolProtocol {
        if let proxy = helperProxy {
            return proxy
        }

        let conn = getConnection()
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            print("XPC Error: \(error)")
            self.connection = nil
            self.helperProxy = nil
        }) as? HelperToolProtocol else {
            throw HelperError.connectionFailed
        }

        helperProxy = proxy
        return proxy
    }

    private func getConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }

        let newConnection = NSXPCConnection(machServiceName: kHelperToolMachServiceName, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperToolProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            self?.connection = nil
            self?.helperProxy = nil
            print("XPC connection invalidated")
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.helperProxy = nil
            print("XPC connection interrupted")
        }

        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    /// 断开连接
    func disconnect() {
        connection?.invalidate()
        connection = nil
        helperProxy = nil
    }

    // MARK: - 便捷方法

    /// 设置风扇转速
    func setFanSpeed(index: Int, speed: Int) async throws -> Bool {
        let helper = try getHelper()

        return await withCheckedContinuation { continuation in
            helper.setFanSpeed(index: index, speed: speed) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// 重置风扇为自动
    func resetFanToAuto(index: Int) async throws -> Bool {
        let helper = try getHelper()

        return await withCheckedContinuation { continuation in
            helper.resetFanToAuto(index: index) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// 解锁 Apple Silicon 风扇控制
    func unlockFanControl() async throws -> Bool {
        let helper = try getHelper()

        return await withCheckedContinuation { continuation in
            helper.unlockFanControl { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// 获取 CPU 温度
    func getCPUTemperature() async throws -> Double? {
        let helper = try getHelper()

        return await withCheckedContinuation { continuation in
            helper.getCPUTemperature { temp in
                continuation.resume(returning: temp?.doubleValue)
            }
        }
    }
}

// MARK: - Helper 错误

enum HelperError: Error, LocalizedError {
    case authorizationFailed
    case authorizationDenied
    case installFailed(Error?)
    case connectionFailed
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .authorizationFailed:
            return "无法创建授权"
        case .authorizationDenied:
            return "授权被拒绝"
        case .installFailed(let error):
            if let err = error {
                return "安装 Helper 失败: \(err.localizedDescription)"
            }
            return "安装 Helper 失败"
        case .connectionFailed:
            return "无法连接到 Helper"
        case .notInstalled:
            return "Helper 未安装"
        }
    }
}
