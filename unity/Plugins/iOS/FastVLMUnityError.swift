//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import Foundation

enum FastVLMUnityError: LocalizedError {

    case modelDirectoryMissing
    case modelResourcesMissing(String)
    case imageCreationFailed
    case unsupportedPixelFormat
    case invalidPixelBuffer
    case invalidDimensions
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelDirectoryMissing:
            return "FastVLM model directory has not been configured."
        case .modelResourcesMissing(let path):
            return "FastVLM resources were not found at \(path)."
        case .imageCreationFailed:
            return "Unable to create an image from the supplied pixel buffer."
        case .unsupportedPixelFormat:
            return "The provided pixel format is not supported by the FastVLM Unity plugin."
        case .invalidPixelBuffer:
            return "Pixel buffer was null or empty."
        case .invalidDimensions:
            return "Width, height, and bytes-per-row must be greater than zero."
        case .cancelled:
            return "The FastVLM request was cancelled."
        }
    }
}
