import AppKit
import ImageIO

// Composite the original app logo without redrawing or stretching its artwork.
// Run from the repository root; the illustration is separate from the logo.
let artworkURL = URL(fileURLWithPath: "packaging/dmg/background-art@2x.png")
let logoURL = URL(fileURLWithPath: "oTATo Prompt/AppIcon.icon/Assets/app-icon-white.png")
let outputURL = URL(fileURLWithPath: "packaging/dmg/background@2x.png")

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Cannot load image: \(url.path)")
    }
    return image
}

let artwork = loadImage(artworkURL)
let logo = loadImage(logoURL)
guard let logoData = try? Data(contentsOf: logoURL),
      let bitmap = NSBitmapImageRep(data: logoData),
      let pixels = bitmap.bitmapData else {
    fatalError("Cannot read logo alpha channel")
}
precondition(bitmap.hasAlpha && bitmap.bitsPerSample == 8 && !bitmap.isPlanar)
let alpha = bitmap.bitmapFormat.contains(.alphaFirst) ? 0 : bitmap.samplesPerPixel - 1
var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        let offset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel + alpha
        if pixels[offset] > 0 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
precondition(maxX >= minX && maxY >= minY)
let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let croppedLogo = logo.cropping(to: bounds),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: artwork.width, height: artwork.height,
                              bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Cannot create background context")
}
context.interpolationQuality = .high
context.draw(artwork, in: CGRect(x: 0, y: 0, width: artwork.width, height: artwork.height))
let width: CGFloat = 210
let height = width * CGFloat(croppedLogo.height) / CGFloat(croppedLogo.width)
let rect = CGRect(x: (CGFloat(artwork.width) - width) / 2,
                  y: CGFloat(artwork.height) - 42 - height, width: width, height: height)
context.draw(croppedLogo, in: rect)
guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode background")
}
try png.write(to: outputURL)
print("Composited source logo at \(Int(width)) × \(Int(height)) pixels; original aspect ratio preserved")
