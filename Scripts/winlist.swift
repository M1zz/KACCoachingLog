import CoreGraphics
import Foundation

// usage: winlist <pid>  → "id x y w h layer" per on-screen window of that pid (front to back)
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let id = w[kCGWindowNumber as String] as! Int
    let layer = w[kCGWindowLayer as String] as! Int
    print(id, b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!, layer)
}
