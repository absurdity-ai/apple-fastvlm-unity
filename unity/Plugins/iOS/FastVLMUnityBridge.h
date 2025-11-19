//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

#ifndef FastVLMUnityBridge_h
#define FastVLMUnityBridge_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Callback invoked when an asynchronous operation completes with a status result.
/// @param error Error message if the operation failed, NULL for success.
typedef void (*FastVLMUnityStatusCallback)(const char *error);

/// Callback invoked when image processing is complete.
/// @param requestId The ID of the request that was processed.
/// @param result The generated text output, or NULL if an error occurred.
/// @param error Error message if processing failed, NULL if successful.
typedef void (*FastVLMUnityResultCallback)(
    int32_t requestId,
    const char *result,
    const char *error
);

/// Configure the plugin with a model directory path.
/// @param modelDirectoryPath Absolute path to the directory containing model files (config.json, weights, etc.).
///        Pass empty string or NULL to use bundled model resources.
void FastVLMUnity_Configure(const char *modelDirectoryPath);

/// Set text generation parameters.
/// @param temperature Sampling temperature (0.0 = deterministic, higher = more random).
/// @param maxTokens Maximum number of tokens to generate (must be > 0).
void FastVLMUnity_SetGenerationOptions(float temperature, int32_t maxTokens);

/// Control whether new requests automatically cancel previous ones.
/// @param cancelOnNewRequest 1 to cancel previous requests, 0 to allow concurrent requests.
void FastVLMUnity_SetCancelOnNewRequest(int32_t cancelOnNewRequest);

/// Load the FastVLM model asynchronously.
/// Call this once before issuing inference requests. The callback will be invoked
/// on the main thread when loading completes.
/// @param callback Called with error=NULL on success, or error message on failure.
void FastVLMUnity_LoadModel(FastVLMUnityStatusCallback callback);

/// Process an image and generate descriptive text.
/// The image data is interpreted based on the format parameter.
/// The callback will be invoked on the main thread when processing completes.
/// @param requestId Unique identifier for this request (used to correlate with callback).
/// @param pixelData Pointer to pixel buffer (RGBA32 or BGRA32 format).
/// @param width Image width in pixels (must be > 0).
/// @param height Image height in pixels (must be > 0).
/// @param bytesPerRow Bytes per scan line (typically width * 4).
/// @param format Pixel format: 0 for RGBA32, 1 for BGRA32.
/// @param flipVertical 1 to flip image vertically, 0 otherwise.
/// @param prompt Text prompt for the model (e.g., "Describe this image").
/// @param callback Called with result and error when processing completes.
void FastVLMUnity_ProcessImage(
    int32_t requestId,
    void *pixelData,
    int32_t width,
    int32_t height,
    int32_t bytesPerRow,
    int32_t format,
    int32_t flipVertical,
    const char *prompt,
    FastVLMUnityResultCallback callback
);

/// Cancel all pending operations and abort the active inference.
void FastVLMUnity_CancelAll(void);

/// Free a C string allocated by FastVLM plugin.
/// This must be called for strings returned by callbacks to prevent memory leaks.
/// @param pointer The pointer to free (typically result or error from callback).
void FastVLMUnity_FreeCString(char *pointer);

#ifdef __cplusplus
}
#endif

#endif /* FastVLMUnityBridge_h */
