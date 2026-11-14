import DiskHealthCore
import SwiftUI

/// Шкала заповненості диска; помаранчева, коли досягнуто порогу з налаштувань.
struct SpaceBar: View {
    let space: DiskSpace
    let fullWarning: Int

    private var isFull: Bool { space.usedPercent >= fullWarning }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: Double(space.usedBytes), total: Double(max(space.totalBytes, 1)))
                .progressViewStyle(.linear)
                .tint(isFull ? .orange : .accentColor)
            Text("\(space.usedPercent)% full · \(Format.bytes(space.availableBytes)) free of \(Format.bytes(space.totalBytes))")
                .font(.caption)
                .foregroundStyle(isFull ? .orange : .secondary)
        }
    }
}
