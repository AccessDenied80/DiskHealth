/// Пороги, за якими диск вважається проблемним. Значення за замовчуванням — зі специфікації.
public struct Thresholds: Codable, Equatable, Sendable {
    public var wearWarning = 80
    public var wearCritical = 90
    public var temperatureWarning = 60

    public init() {}
}
