// main.swift - Privileged Helper Tool 入口点
// 此程序以 root 权限运行，提供 SMC 访问服务

import Foundation
import SMCKit

// MARK: - Helper Tool 实现

class HelperTool: NSObject, HelperToolProtocol, NSXPCListenerDelegate {

    private let listener: NSXPCListener
    private var connections = [NSXPCConnection]()
    private var shouldQuit = false

    override init() {
        self.listener = NSXPCListener(machServiceName: kHelperToolMachServiceName)
        super.init()
        self.listener.delegate = self
    }

    func run() {
        NSLog("MacFanControl Helper Tool starting...")
        self.listener.resume()

        // 运行主循环
        while !shouldQuit {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        }

        NSLog("MacFanControl Helper Tool exiting...")
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        NSLog("New XPC connection request")

        newConnection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
        newConnection.exportedObject = self

        newConnection.invalidationHandler = { [weak self] in
            if let index = self?.connections.firstIndex(of: newConnection) {
                self?.connections.remove(at: index)
            }
            NSLog("XPC connection invalidated")
        }

        newConnection.interruptionHandler = {
            NSLog("XPC connection interrupted")
        }

        connections.append(newConnection)
        newConnection.resume()

        NSLog("XPC connection accepted")
        return true
    }

    // MARK: - HelperToolProtocol 实现

    func getVersion(reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }

    func getFanCount(reply: @escaping (Int) -> Void) {
        do {
            try SMCManager.shared.open()
            let count = SMCManager.shared.getFanCount()
            reply(count)
        } catch {
            reply(0)
        }
    }

    func getFanSpeed(index: Int, reply: @escaping (NSNumber?) -> Void) {
        do {
            try SMCManager.shared.open()
            if let speed = SMCManager.shared.getFanSpeed(index: index) {
                reply(NSNumber(value: speed))
            } else {
                reply(nil)
            }
        } catch {
            reply(nil)
        }
    }

    func setFanSpeed(index: Int, speed: Int, reply: @escaping (Bool) -> Void) {
        do {
            try SMCManager.shared.open()
            try SMCManager.shared.setFanSpeed(index: index, speed: speed)
            NSLog("Set fan \(index) speed to \(speed) RPM")
            reply(true)
        } catch {
            NSLog("Failed to set fan speed: \(error)")
            reply(false)
        }
    }

    func resetFanToAuto(index: Int, reply: @escaping (Bool) -> Void) {
        do {
            try SMCManager.shared.open()
            try SMCManager.shared.resetFanToAuto(index: index)
            NSLog("Reset fan \(index) to auto")
            reply(true)
        } catch {
            NSLog("Failed to reset fan: \(error)")
            reply(false)
        }
    }

    func resetAllFansToAuto(reply: @escaping (Bool) -> Void) {
        do {
            try SMCManager.shared.open()
            let count = SMCManager.shared.getFanCount()
            for i in 0..<count {
                try SMCManager.shared.resetFanToAuto(index: i)
            }
            NSLog("Reset all fans to auto")
            reply(true)
        } catch {
            NSLog("Failed to reset all fans: \(error)")
            reply(false)
        }
    }

    func unlockFanControl(reply: @escaping (Bool) -> Void) {
        do {
            try SMCManager.shared.open()

            // 尝试写入 Ftst = 1
            var value = SMCValue()
            value.dataSize = 1
            value.bytes.0 = 1

            try SMCManager.shared.writeKey("Ftst", value: value)
            NSLog("Apple Silicon fan control unlocked (Ftst=1)")

            // 等待 thermalmonitord 让出控制
            var success = false
            let startTime = Date()

            while Date().timeIntervalSince(startTime) < 6.0 {
                do {
                    // 尝试设置风扇模式来验证控制权
                    var modeValue = SMCValue()
                    modeValue.dataSize = 1
                    modeValue.bytes.0 = 1
                    try SMCManager.shared.writeKey("F0Md", value: modeValue)
                    success = true
                    break
                } catch {
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }

            reply(success)
        } catch {
            NSLog("Failed to unlock fan control: \(error)")
            reply(false)
        }
    }

    func lockFanControl(reply: @escaping (Bool) -> Void) {
        do {
            try SMCManager.shared.open()
            SMCManager.shared.lockAppleSiliconFanControl()
            NSLog("Apple Silicon fan control locked")
            reply(true)
        } catch {
            reply(false)
        }
    }

    func getCPUTemperature(reply: @escaping (NSNumber?) -> Void) {
        do {
            try SMCManager.shared.open()
            if let temp = SMCManager.shared.getCPUTemperature() {
                reply(NSNumber(value: temp))
            } else {
                reply(nil)
            }
        } catch {
            reply(nil)
        }
    }

    func getAllTemperatures(reply: @escaping (NSDictionary) -> Void) {
        do {
            try SMCManager.shared.open()
            let sensors = SMCManager.shared.getAllTemperatureSensors()
            let result = NSMutableDictionary()
            for (name, value) in sensors {
                result[name] = NSNumber(value: value)
            }
            reply(result)
        } catch {
            reply(NSDictionary())
        }
    }
}

// MARK: - 主入口

let helper = HelperTool()
helper.run()
