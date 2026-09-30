import CoreGraphics
import Foundation
import ImageIO

/// Análisis barato de capturas para decidir sin un modelo de visión.
public enum ScreenAnalysis {
    /// La captura es prácticamente de un solo color (negra, blanca o de fondo): la app no
    /// está dibujando nada. Se reduce a 36×78 en gris, se ignora la barra de estado y se
    /// mide cuánto varía la luminancia.
    public static func isBlank(png data: Data, maxDeviation: Double = 4) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let width = 36, height = 78
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        // Las filas de datos van de arriba abajo: se salta ~6 % superior (hora, batería).
        let values = pixels[(width * 5)...].map(Double.init)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() <= maxDeviation
    }
}
