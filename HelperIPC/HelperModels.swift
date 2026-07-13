import Foundation

public struct HelperFanSnapshot: Codable, Equatable, Sendable {
    public let index: Int
    public let currentRPM: Int
    public let minimumRPM: Int
    public let maximumRPM: Int
    public let targetRPM: Int?
    public let mode: Int

    public init(
        index: Int,
        currentRPM: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        targetRPM: Int?,
        mode: Int
    ) {
        self.index = index
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
        self.mode = mode
    }
}

public struct HelperTemperatureSnapshot: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let value: Double

    public init(key: String, name: String, value: Double) {
        self.key = key
        self.name = name
        self.value = value
    }
}

public enum HelperPayloadCodec {
    public static func encodeFans(_ snapshots: [HelperFanSnapshot]) throws -> Data {
        try JSONEncoder().encode(snapshots)
    }

    public static func decodeFans(_ data: Data) throws -> [HelperFanSnapshot] {
        try JSONDecoder().decode([HelperFanSnapshot].self, from: data)
    }

    public static func encodeTemperatures(_ snapshots: [HelperTemperatureSnapshot]) throws -> Data {
        try JSONEncoder().encode(snapshots)
    }

    public static func decodeTemperatures(_ data: Data) throws -> [HelperTemperatureSnapshot] {
        try JSONDecoder().decode([HelperTemperatureSnapshot].self, from: data)
    }
}
