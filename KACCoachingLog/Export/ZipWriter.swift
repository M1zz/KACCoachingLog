import Foundation

/// Minimal ZIP archive writer (STORED entries, no compression).
/// XLSX files are ZIP packages; Excel, Numbers and LibreOffice all accept stored entries.
struct ZipWriter {
    private struct Entry {
        let nameBytes: [UInt8]
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var output = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(modificationDate: Date = Date(), timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: modificationDate)
        let year: Int = max((c.year ?? 1980) - 1980, 0)
        let month: Int = c.month ?? 1
        let day: Int = c.day ?? 1
        let hour: Int = c.hour ?? 0
        let minute: Int = c.minute ?? 0
        let second: Int = c.second ?? 0
        let packedDate: Int = (year << 9) | (month << 5) | day
        let packedTime: Int = (hour << 11) | (minute << 5) | (second / 2)
        dosDate = UInt16(truncatingIfNeeded: packedDate)
        dosTime = UInt16(truncatingIfNeeded: packedTime)
    }

    mutating func addFile(path: String, data: Data) {
        let nameBytes = Array(path.utf8)
        let crc = CRC32.checksum(data)
        let size = UInt32(truncatingIfNeeded: data.count)
        let offset = UInt32(truncatingIfNeeded: output.count)

        output.appendLE(UInt32(0x0403_4B50))   // local file header signature
        output.appendLE(UInt16(20))            // version needed to extract
        output.appendLE(UInt16(0x0800))        // flags: UTF-8 names
        output.appendLE(UInt16(0))             // method: stored
        output.appendLE(dosTime)
        output.appendLE(dosDate)
        output.appendLE(crc)
        output.appendLE(size)                  // compressed size
        output.appendLE(size)                  // uncompressed size
        output.appendLE(UInt16(nameBytes.count))
        output.appendLE(UInt16(0))             // extra field length
        output.append(contentsOf: nameBytes)
        output.append(data)

        entries.append(Entry(nameBytes: nameBytes, crc: crc, size: size, offset: offset))
    }

    mutating func addFile(path: String, string: String) {
        addFile(path: path, data: Data(string.utf8))
    }

    func finalize() -> Data {
        var archive = output
        let centralDirectoryOffset = UInt32(truncatingIfNeeded: archive.count)
        var centralDirectory = Data()
        for entry in entries {
            centralDirectory.appendLE(UInt32(0x0201_4B50)) // central directory header signature
            centralDirectory.appendLE(UInt16(20))          // version made by
            centralDirectory.appendLE(UInt16(20))          // version needed
            centralDirectory.appendLE(UInt16(0x0800))      // flags
            centralDirectory.appendLE(UInt16(0))           // method
            centralDirectory.appendLE(dosTime)
            centralDirectory.appendLE(dosDate)
            centralDirectory.appendLE(entry.crc)
            centralDirectory.appendLE(entry.size)
            centralDirectory.appendLE(entry.size)
            centralDirectory.appendLE(UInt16(entry.nameBytes.count))
            centralDirectory.appendLE(UInt16(0))           // extra length
            centralDirectory.appendLE(UInt16(0))           // comment length
            centralDirectory.appendLE(UInt16(0))           // disk number start
            centralDirectory.appendLE(UInt16(0))           // internal attributes
            centralDirectory.appendLE(UInt32(0))           // external attributes
            centralDirectory.appendLE(entry.offset)
            centralDirectory.append(contentsOf: entry.nameBytes)
        }
        archive.append(centralDirectory)

        archive.appendLE(UInt32(0x0605_4B50))              // end of central directory signature
        archive.appendLE(UInt16(0))                        // disk number
        archive.appendLE(UInt16(0))                        // disk with central directory
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(truncatingIfNeeded: centralDirectory.count))
        archive.appendLE(centralDirectoryOffset)
        archive.appendLE(UInt16(0))                        // comment length
        return archive
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
