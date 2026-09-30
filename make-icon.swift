import AppKit

let output = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { fatalError("No graphics context") }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let bounds = CGRect(x: 32, y: 32, width: 960, height: 960)
let background = NSBezierPath(roundedRect: bounds, xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.16, green: 0.24, blue: 0.43, alpha: 1).setFill()
background.fill()

let text = "⌘Q" as NSString
let font = NSFont.systemFont(ofSize: 410, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white
]
let textSize = text.size(withAttributes: attributes)
let textRect = CGRect(x: (CGFloat(size) - textSize.width) / 2,
                      y: (CGFloat(size) - textSize.height) / 2 + 8,
                      width: textSize.width, height: textSize.height)
text.draw(in: textRect, withAttributes: attributes)

let slash = NSBezierPath()
slash.lineCapStyle = .round
slash.lineWidth = 48
NSColor(calibratedRed: 1, green: 0.32, blue: 0.36, alpha: 1).setStroke()
slash.move(to: NSPoint(x: 220, y: 220))
slash.line(to: NSPoint(x: 804, y: 804))
slash.stroke()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: output))
