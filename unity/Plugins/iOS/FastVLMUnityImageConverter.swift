//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import CoreGraphics
import CoreImage
import Foundation

@objc enum FastVLMUnityColorFormat: Int {
    case rgba32 = 0
    case bgra32 = 1
}

struct FastVLMUnityImageConverter {

    func makeImage(
        from data: Data,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        format: FastVLMUnityColorFormat,
        flipVertical: Bool
    ) throws -> CIImage {
        guard !data.isEmpty else {
            throw FastVLMUnityError.invalidPixelBuffer
        }

        guard width > 0, height > 0, bytesPerRow > 0 else {
            throw FastVLMUnityError.invalidDimensions
        }

        guard let provider = CGDataProvider(data: data as CFData) else {
            throw FastVLMUnityError.imageCreationFailed
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let bitsPerPixel = 32

        let bitmapInfo: CGBitmapInfo
        switch format {
        case .rgba32:
            var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            info.insert(.byteOrder32Big)
            bitmapInfo = info
        case .bgra32:
            var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            info.insert(.byteOrder32Little)
            bitmapInfo = info
        }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw FastVLMUnityError.imageCreationFailed
        }

        var image = CIImage(cgImage: cgImage)
        if flipVertical {
            let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(height))
            image = image.transformed(by: transform)
        }

        return image
    }
}
