import Foundation
import IOKit

/// `smartctl` на macOS називає диски IOService-шляхами; тут шукаємо BSD-ім'я та розмір цілого диска.
public enum IOKitLookup {
    public struct Media: Equatable, Sendable {
        public var bsdName: String
        public var sizeBytes: Int64?
    }

    public static func wholeMedia(forServicePath path: String) -> Media? {
        guard path.hasPrefix("IOService:") else { return nil }
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(entry) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(entry, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != IO_OBJECT_NULL {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOMedia") != 0,
                  property(child, "Whole") as? Bool == true,
                  let bsd = property(child, "BSD Name") as? String
            else { continue }
            let size = (property(child, "Size") as? NSNumber)?.int64Value
            return Media(bsdName: bsd, sizeBytes: size)
        }
        return nil
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
