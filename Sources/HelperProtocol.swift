// HelperProtocol.swift - XPC 通信协议 (主应用和 Helper 共享)

import Foundation

/// Helper Tool 提供的服务协议
/// 注意: XPC 协议必须使用 Objective-C 兼容的类型
@objc protocol HelperToolProtocol {
    /// 获取 Helper 版本
    func getVersion(reply: @escaping (String) -> Void)

    /// 获取风扇数量
    func getFanCount(reply: @escaping (Int) -> Void)

    /// 获取风扇转速 (返回 NSNumber 以兼容 Objective-C)
    func getFanSpeed(index: Int, reply: @escaping (NSNumber?) -> Void)

    /// 设置风扇转速
    func setFanSpeed(index: Int, speed: Int, reply: @escaping (Bool) -> Void)

    /// 重置风扇为自动模式
    func resetFanToAuto(index: Int, reply: @escaping (Bool) -> Void)

    /// 重置所有风扇为自动模式
    func resetAllFansToAuto(reply: @escaping (Bool) -> Void)

    /// 解锁 Apple Silicon 风扇控制
    func unlockFanControl(reply: @escaping (Bool) -> Void)

    /// 锁定风扇控制（恢复系统控制）
    func lockFanControl(reply: @escaping (Bool) -> Void)

    /// 获取 CPU 温度 (返回 NSNumber 以兼容 Objective-C)
    func getCPUTemperature(reply: @escaping (NSNumber?) -> Void)

    /// 获取所有温度传感器 (返回 NSDictionary 以兼容 Objective-C)
    func getAllTemperatures(reply: @escaping (NSDictionary) -> Void)
}

/// Helper Tool 的 Mach 服务名称
let kHelperToolMachServiceName = "com.macfancontrol.helper"

/// Helper Tool 的 Bundle ID
let kHelperToolBundleID = "com.macfancontrol.helper"

/// 主应用的 Bundle ID
let kMainAppBundleID = "com.macfancontrol.app"
