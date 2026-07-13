import Foundation

public let helperMachServiceName = "com.macfancontrol.helper"
public let helperBundleIdentifier = "com.macfancontrol.helper"
public let mainAppBundleIdentifier = "com.macfancontrol.app"

@objc public protocol HelperToolProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func getFanData(reply: @escaping (Data?, String?) -> Void)
    func setFanSpeed(index: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void)
    func resetFanToAuto(index: Int, reply: @escaping (Bool, String?) -> Void)
    func resetAllFansToAuto(reply: @escaping (Bool, String?) -> Void)
    func getTemperatures(reply: @escaping (Data?, String?) -> Void)
    func removeLegacyHelper(reply: @escaping (Bool, String?) -> Void)
}
