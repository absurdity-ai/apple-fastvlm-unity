//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import CoreImage
import Darwin
import Foundation

private let unityRunner = FastVLMUnityRunner()
private let imageConverter = FastVLMUnityImageConverter()

typealias FastVLMUnityStatusCallback = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
typealias FastVLMUnityResultCallback = @convention(c) (
    Int32, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<CChar>?
) -> Void

@_cdecl("FastVLMUnity_Configure")
public func FastVLMUnity_Configure(_ modelDirectoryPointer: UnsafePointer<CChar>?) {
    let path = modelDirectoryPointer.flatMap { String(cString: $0) } ?? ""
    Task {
        await unityRunner.configure(modelDirectoryPath: path)
    }
}

@_cdecl("FastVLMUnity_SetGenerationOptions")
public func FastVLMUnity_SetGenerationOptions(_ temperature: Float, _ maxTokens: Int32) {
    Task {
        await unityRunner.setGenerationOptions(temperature: temperature, maxTokens: Int(maxTokens))
    }
}

@_cdecl("FastVLMUnity_SetCancelOnNewRequest")
public func FastVLMUnity_SetCancelOnNewRequest(_ cancelOnNewRequest: Int32) {
    Task {
        await unityRunner.setCancelOnNewRequest(cancelOnNewRequest != 0)
    }
}

@_cdecl("FastVLMUnity_LoadModel")
public func FastVLMUnity_LoadModel(_ callback: FastVLMUnityStatusCallback?) {
    guard let callback else { return }

    Task.detached(priority: .userInitiated) {
        do {
            try await unityRunner.loadModel()
            await MainActor.run {
                callback(nil)
            }
        } catch {
            let message = createCString(from: error.localizedDescription)
            await MainActor.run {
                callback(message)
            }
        }
    }
}

@_cdecl("FastVLMUnity_ProcessImage")
public func FastVLMUnity_ProcessImage(
    _ requestId: Int32,
    _ pixelDataPointer: UnsafeRawPointer?,
    _ width: Int32,
    _ height: Int32,
    _ bytesPerRow: Int32,
    _ formatRawValue: Int32,
    _ flipVertical: Int32,
    _ promptPointer: UnsafePointer<CChar>?,
    _ callback: FastVLMUnityResultCallback?
) {
    guard let callback else { return }

    guard let pixelDataPointer else {
        let errorPointer = createCString(from: FastVLMUnityError.invalidPixelBuffer.localizedDescription)
        Task { @MainActor in
            callback(requestId, nil, errorPointer)
        }
        return
    }

    guard width > 0, height > 0, bytesPerRow > 0 else {
        let errorPointer = createCString(from: FastVLMUnityError.invalidDimensions.localizedDescription)
        Task { @MainActor in
            callback(requestId, nil, errorPointer)
        }
        return
    }

    guard let format = FastVLMUnityColorFormat(rawValue: Int(formatRawValue)) else {
        let errorPointer = createCString(from: FastVLMUnityError.unsupportedPixelFormat.localizedDescription)
        Task { @MainActor in
            callback(requestId, nil, errorPointer)
        }
        return
    }

    let prompt = promptPointer.flatMap { String(cString: $0) } ?? ""
    let length = Int(bytesPerRow) * Int(height)
    let data = Data(bytes: pixelDataPointer, count: length)

    Task.detached(priority: .userInitiated) {
        do {
            let ciImage = try imageConverter.makeImage(
                from: data,
                width: Int(width),
                height: Int(height),
                bytesPerRow: Int(bytesPerRow),
                format: format,
                flipVertical: flipVertical != 0
            )

            let output = try await unityRunner.generate(ciImage: ciImage, prompt: prompt)
            let resultPointer = createCString(from: output)
            await MainActor.run {
                callback(requestId, resultPointer, nil)
            }
        } catch {
            let errorPointer = createCString(from: error.localizedDescription)
            await MainActor.run {
                callback(requestId, nil, errorPointer)
            }
        }
    }
}

@_cdecl("FastVLMUnity_CancelAll")
public func FastVLMUnity_CancelAll() {
    Task {
        await unityRunner.cancelAll()
    }
}

@_cdecl("FastVLMUnity_FreeCString")
public func FastVLMUnity_FreeCString(_ pointer: UnsafeMutablePointer<CChar>?) {
    guard let pointer else { return }
    free(pointer)
}

private func createCString(from string: String?) -> UnsafeMutablePointer<CChar>? {
    guard let string else { return nil }
    return strdup(string)
}
