/// Пороги, за якими диск вважається проблемним. Значення за замовчуванням — зі специфікації.
public struct Thresholds: Codable, Equatable, Sendable {
    public var wearWarning = 80
    public var wearCritical = 90
    public var temperatureWarning = 60
    /// Заповненість диска у відсотках, з якої надходить попередження.
    public var fullWarning = 90
    public var fullRearmMargin = 5

    public init() {}
}
