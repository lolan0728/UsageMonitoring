struct QuotaCardViewData: Sendable {
    let label: String
    let remainingText: String
    let resetText: String
    let syncedText: String
    let statusText: String
    let remainingPercent: Double
    let usedPercent: Double

    static func placeholder(
        label: String,
        statusText: String,
        resetText: String = "Waiting for sync"
    ) -> QuotaCardViewData {
        QuotaCardViewData(
            label: label,
            remainingText: "--",
            resetText: resetText,
            syncedText: "Never",
            statusText: statusText,
            remainingPercent: 0,
            usedPercent: 0)
    }
}
