import AppKit
import Foundation
let paths = ["/Applications/积存金.app", CommandLine.arguments[1], "/Applications/积存金.app/Contents/Resources/AppIcon.icns"]
for (index,path) in paths.enumerated() {
    let image = index == 2 ? NSImage(contentsOfFile: path)! : NSWorkspace.shared.icon(forFile: path)
    let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
    image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
    NSGraphicsContext.restoreGraphicsState()
    try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2] + "/system-icon-\(index).png"))
    print("Rendered \(path)")
}
