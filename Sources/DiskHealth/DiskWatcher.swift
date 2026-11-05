import DiskArbitration
import Foundation

/// Сповіщає про підключення/відключення фізичних дисків і про монтування томів, зокрема з Finder
/// (з дебаунсом, бо том монтується кількома подіями).
final class DiskWatcher: @unchecked Sendable {
    private let session: DASession
    private let onChange: @Sendable () -> Void
    private let onVolumesChange: @Sendable () -> Void
    private var pending: DispatchWorkItem?
    private var pendingVolumes: DispatchWorkItem?
    private let queue = DispatchQueue(label: "DiskHealth.DiskWatcher")
    private var armed = false

    init(onChange: @escaping @Sendable () -> Void, onVolumesChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        self.onVolumesChange = onVolumesChange
        session = DASessionCreate(kCFAllocatorDefault)!
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let match = [kDADiskDescriptionMediaWholeKey as String: true] as CFDictionary
        DARegisterDiskAppearedCallback(session, match, { _, ctx in
            Unmanaged<DiskWatcher>.fromOpaque(ctx!).takeUnretainedValue().changed()
        }, ctx)
        DARegisterDiskDisappearedCallback(session, match, { _, ctx in
            Unmanaged<DiskWatcher>.fromOpaque(ctx!).takeUnretainedValue().changed()
        }, ctx)
        DARegisterDiskDescriptionChangedCallback(session, nil, [kDADiskDescriptionVolumePathKey] as CFArray, { _, _, ctx in
            Unmanaged<DiskWatcher>.fromOpaque(ctx!).takeUnretainedValue().volumesChanged()
        }, ctx)
        DASessionSetDispatchQueue(session, queue)
        // DiskArbitration одразу повідомляє про всі наявні диски — ігноруємо цю першу хвилю.
        queue.asyncAfter(deadline: .now() + 3) { self.armed = true }
    }

    deinit {
        DASessionSetDispatchQueue(session, nil)
    }

    private func volumesChanged() {
        pendingVolumes?.cancel()
        let item = DispatchWorkItem { [onVolumesChange] in onVolumesChange() }
        pendingVolumes = item
        queue.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private func changed() {
        guard armed else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + 5, execute: item)
    }
}
