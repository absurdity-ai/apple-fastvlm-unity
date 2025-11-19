# FastVLM Unity Plugin - Test Plan

## Overview
This document outlines comprehensive testing procedures for the FastVLM Unity iOS/visionOS plugin.

---

## 1. UNIT TESTS

### 1.1 C# Wrapper Tests

**Test: Configuration Validation**
```
TC-CS-001: Configure with valid path
- Input: Valid directory path containing model files
- Expected: Configuration succeeds, no exceptions
- Verify: modelConfiguration state is set

TC-CS-002: Configure with empty path
- Input: Empty string or null
- Expected: Falls back to bundled model
- Verify: Uses default resources

TC-CS-003: Configure with invalid path
- Input: Non-existent directory path
- Expected: Should throw or log warning
- Verify: Error handling is graceful

TC-CS-004: Configure with non-readable path
- Input: Directory without read permissions
- Expected: Should be handled gracefully
- Verify: Error message is clear
```

**Test: Input Validation**
```
TC-CS-005: ProcessTextureAsync with null texture
- Input: null
- Expected: Throws ArgumentNullException
- Verify: Error message is clear

TC-CS-006: ProcessTextureAsync with non-readable texture
- Input: Texture with isReadable=false
- Expected: Throws InvalidOperationException
- Verify: Suggests enabling Read/Write in import settings

TC-CS-007: ProcessWebCamFrameAsync with null WebCamTexture
- Input: null
- Expected: Throws ArgumentNullException

TC-CS-008: ProcessWebCamFrameAsync with uninitialized texture
- Input: WebCamTexture with width/height = 0
- Expected: Throws InvalidOperationException

TC-CS-009: ProcessRawBytesAsync with mismatched dimensions
- Input: Buffer too small for width*height
- Expected: Throws ArgumentException

TC-CS-010: SetGenerationOptions with invalid maxTokens
- Input: maxTokens = 0 or negative
- Expected: Throws ArgumentOutOfRangeException
```

**Test: Generation Options**
```
TC-CS-011: SetGenerationOptions with valid temperature
- Input: temperature=0.5f, maxTokens=100
- Expected: Succeeds, parameters are set
- Verify: Reflected in inference

TC-CS-012: SetGenerationOptions with extreme temperature
- Input: temperature=0f, maxTokens=500
- Expected: Succeeds (model handles it)

TC-CS-013: SetGenerationOptions with large maxTokens
- Input: maxTokens=1000
- Expected: Succeeds, inference respects limit
```

**Test: Cancellation**
```
TC-CS-014: CancelAll with pending request
- Input: Cancel while inference active
- Expected: Inference task is cancelled
- Verify: CancellationException or similar

TC-CS-015: CancelAll with no pending requests
- Input: Call CancelAll when idle
- Expected: No exceptions
```

---

## 2. INTEGRATION TESTS

### 2.1 iOS Build and Deployment

**Test: Build Configuration**
```
TC-BUILD-iOS-001: Build for iOS 18.2+ device
- Prerequisites: Xcode 16.2+, iOS device with iOS 18.2+
- Steps:
  1. Export Unity project for iOS
  2. Open generated Xcode project
  3. Add required Swift packages
  4. Build for device
- Expected: Build succeeds, no linker errors
- Verify: Symbol resolution, no undefined references

TC-BUILD-iOS-002: Verify header file is present
- Steps:
  1. Check if FastVLMUnityBridge.h is in project
  2. Verify symbols match C# declarations
- Expected: Header file is present and correct

TC-BUILD-iOS-003: Verify plugin is properly compiled
- Steps:
  1. Check build output for plugin compilation
  2. Verify FastVLM.swift is compiled
  3. Check for symbol definitions
- Expected: All symbols defined
```

### 2.2 visionOS Build and Deployment

**Test: visionOS Build Configuration**
```
TC-BUILD-visionOS-001: Build for visionOS 2.0+ device
- Prerequisites: Xcode 16.2+, visionOS device with 2.0+
- Steps:
  1. Export Unity project for visionOS
  2. Open generated Xcode project
  3. Select visionOS destination
  4. Add required Swift packages
  5. Build for device
- Expected: Build succeeds
- Verify: No iOS-specific errors

TC-BUILD-visionOS-002: Platform conditionals are respected
- Steps:
  1. Check Swift code for #if os(visionOS)
  2. Verify stubs are used when unavailable
- Expected: Proper platform handling

TC-BUILD-visionOS-003: visionOS-specific APIs compile
- Steps:
  1. Verify any visionOS APIs are available
  2. Check for availability attributes
- Expected: Correct deployment target
```

### 2.3 Runtime Model Loading

**Test: Model Loading**
```
TC-RUNTIME-001: LoadModelAsync succeeds with bundled model
- Setup: Model files in Assets/Plugins/iOS/
- Steps:
  1. Call FastVLMUnity.LoadModelAsync()
  2. Wait for completion (timeout 60s)
- Expected: Task completes successfully
- Verify: _modelLoaded state is true
- Performance: < 30s on iPhone 15+

TC-RUNTIME-002: LoadModelAsync fails gracefully with missing model
- Setup: No model files
- Steps:
  1. Call FastVLMUnity.LoadModelAsync()
  2. Catch exception
- Expected: InvalidOperationException with clear message
- Verify: Error message mentions missing resources

TC-RUNTIME-003: LoadModelAsync with custom path
- Setup: Model in Application.persistentDataPath
- Steps:
  1. Call FastVLMUnity.Configure(customPath)
  2. Call FastVLMUnity.LoadModelAsync()
  3. Wait for completion
- Expected: Model loads from custom path
- Verify: Correct model configuration

TC-RUNTIME-004: Multiple LoadModelAsync calls
- Setup: Model already loaded
- Steps:
  1. Call FastVLMUnity.LoadModelAsync()
  2. Call again immediately
  3. Call multiple times
- Expected: Returns same task, doesn't reload
- Verify: Only loads once

TC-RUNTIME-005: LoadModelAsync with timeout
- Setup: Long-running load scenario
- Steps:
  1. Call LoadModelAsync(timeout: 5s)
  2. Measure actual load time
- Expected: Either completes or times out
- Verify: Doesn't hang indefinitely
```

### 2.4 Texture Processing

**Test: RGBA32 Processing**
```
TC-TEXTURE-RGBA32-001: Process solid red texture
- Setup: Create 256x256 red texture (RGBA32)
- Steps:
  1. Create Texture2D with all red pixels (255,0,0,255)
  2. Call ProcessTextureAsync(texture, "What color is this?")
- Expected: Response mentions "red"
- Verify: Color interpretation is correct

TC-TEXTURE-RGBA32-002: Process solid green texture
- Setup: Create 256x256 green texture (RGBA32)
- Steps:
  1. Create green texture
  2. Process same prompt
- Expected: Response mentions "green"
- Verify: Color channels correctly interpreted

TC-TEXTURE-RGBA32-003: Process checkerboard pattern
- Setup: Alternating black/white checkerboard
- Steps:
  1. Create checkerboard texture
  2. Call ProcessTextureAsync
- Expected: Model correctly analyzes pattern
```

**Test: BGRA32 Processing**
```
TC-TEXTURE-BGRA32-001: Process solid red texture (BGRA)
- Setup: Create 256x256 red texture (BGRA32)
- Steps:
  1. Create Texture2D with BGRA format, red pixels
  2. Call ProcessRawBytesAsync with BGRA32 format
- Expected: Response mentions "red"
- Verify: BGRA format is correctly interpreted

TC-TEXTURE-BGRA32-002: Compare RGBA vs BGRA same image
- Setup: Same image in both formats
- Steps:
  1. Process as RGBA32
  2. Process as BGRA32
  3. Compare responses
- Expected: Responses are identical or very similar
- Verify: No color channel confusion

TC-TEXTURE-BGRA32-003: Process gradient (BGRA)
- Setup: Color gradient texture
- Steps:
  1. Create gradient from red to blue
  2. Process as BGRA32
  3. Verify colors are recognized
- Expected: Both color extremes recognized correctly
```

**Test: Texture Properties**
```
TC-TEXTURE-PROPS-001: Various texture sizes
- Steps:
  1. Test 64x64 texture
  2. Test 256x256 texture
  3. Test 512x512 texture
  4. Test 1024x1024 texture
- Expected: All sizes process correctly
- Verify: Performance is acceptable at each size

TC-TEXTURE-PROPS-002: Vertical flip handling
- Setup: Texture with directional content (arrow pointing up)
- Steps:
  1. Process with flipVertical=true
  2. Process with flipVertical=false
  3. Compare responses
- Expected: Responses differ if flip is significant
- Verify: Flip parameter is effective

TC-TEXTURE-PROPS-003: Non-square textures
- Steps:
  1. Test 128x256 texture
  2. Test 256x128 texture
  3. Test wide 1024x256 texture
- Expected: All process correctly
- Verify: Aspect ratio is preserved
```

### 2.5 WebCam Processing

**Test: WebCam Streaming**
```
TC-WEBCAM-001: WebCamTexture basic processing
- Prerequisites: Device with camera
- Setup: Create WebCamTexture and play it
- Steps:
  1. Create WebCamTexture
  2. Call Play()
  3. Wait for first frame (check isPlaying)
  4. Call ProcessWebCamFrameAsync
- Expected: Inference completes successfully
- Verify: Returns text response

TC-WEBCAM-002: Multiple consecutive WebCam frames
- Setup: WebCamTexture streaming
- Steps:
  1. Process frame 1 with prompt A
  2. Wait for completion
  3. Process frame 2 with prompt B
  4. Process frame 3 with prompt A again
- Expected: Each completes independently
- Verify: Responses are different for different frames

TC-WEBCAM-003: WebCam frame during model loading
- Setup: WebCamTexture but model not yet loaded
- Steps:
  1. Create WebCamTexture, don't call LoadModelAsync
  2. Try to process frame immediately
- Expected: Throws error about model not loaded
- Verify: Error handling is clear

TC-WEBCAM-004: WebCam texture size verification
- Steps:
  1. Get WebCamTexture before Play()
  2. Verify width/height are 0
  3. Call Play()
  4. Wait and verify width/height > 0
- Expected: Size properly reflects streaming status
```

### 2.6 Inference and Result Handling

**Test: Inference Execution**
```
TC-INFER-001: Basic inference
- Setup: Model loaded, prompt "Describe this image"
- Steps:
  1. Process test texture
  2. Wait for result
  3. Verify result is string
- Expected: Result is non-empty string
- Verify: Response makes sense

TC-INFER-002: Inference with temperature variation
- Steps:
  1. Set temperature to 0.0 (deterministic)
  2. Process same image twice
  3. Compare results
- Expected: Results are identical
- Verify: Temperature 0 = deterministic

TC-INFER-003: Inference with high temperature
- Steps:
  1. Set temperature to 1.0
  2. Process multiple times
  3. Observe variation
- Expected: Results vary
- Verify: Temperature affects randomness

TC-INFER-004: Inference with different prompts
- Setup: Same image
- Steps:
  1. Process with prompt "Count objects"
  2. Process with prompt "Describe colors"
  3. Process with prompt "What is this?"
- Expected: Responses vary based on prompt
- Verify: Model is responsive to prompt

TC-INFER-005: Long inference operation
- Setup: Model loaded
- Steps:
  1. Set maxTokens to 500
  2. Process image with open-ended prompt
  3. Measure time
- Expected: Completes without timeout
- Verify: Time is reasonable (< 60s)

TC-INFER-006: Empty prompt handling
- Steps:
  1. Call ProcessTextureAsync with empty string prompt
  2. Observe result
- Expected: Model handles gracefully
  (either generates default response or error)
```

**Test: Error Handling in Inference**
```
TC-ERROR-001: Inference with invalid texture data
- Setup: Corrupted or minimal texture
- Steps:
  1. Create 1x1 texture
  2. Try to process
- Expected: Either succeeds or throws clear error
- Verify: No crashes

TC-ERROR-002: Inference during model loading
- Setup: Model loading in progress
- Steps:
  1. Start LoadModelAsync
  2. Immediately call ProcessTextureAsync
- Expected: Either queued or returns error
- Verify: Doesn't crash

TC-ERROR-003: Memory pressure during inference
- Setup: Device with limited memory
- Steps:
  1. Fill available memory
  2. Try to process image
- Expected: Graceful failure or automatic cleanup
- Verify: App doesn't crash

TC-ERROR-004: Multiple concurrent inferences
- Setup: Model loaded
- Steps:
  1. Call ProcessTextureAsync(image1)
  2. Immediately call ProcessTextureAsync(image2)
  3. SetCancelOnNewRequest(true) should cancel #1
- Expected: Only second completes
- Verify: First is cancelled
```

---

## 3. PERFORMANCE TESTS

### 3.1 Memory Usage

**Test: Peak Memory During Model Loading**
```
TC-PERF-MEM-001: Measure peak memory
- Setup: Device with known free memory
- Steps:
  1. Record initial free memory
  2. Call LoadModelAsync
  3. Record peak memory during loading
  4. Record final memory after loading
- Expected: Peak < 500MB, final < 400MB
- Verify: Memory is released after loading

TC-PERF-MEM-002: Memory after multiple inferences
- Setup: Model loaded
- Steps:
  1. Process 10 consecutive images
  2. Measure memory before, during, after each
- Expected: No sustained memory growth
- Verify: Memory released between inferences

TC-PERF-MEM-003: Memory leak detection
- Setup: Model loaded
- Steps:
  1. Process image 100 times
  2. Measure memory growth
  3. Calculate leak rate
- Expected: Leak rate < 1KB per inference
- Verify: No major leaks
```

### 3.2 Performance Metrics

**Test: Time-To-First-Token (TTFT)**
```
TC-PERF-TTFT-001: Measure TTFT
- Setup: Model loaded
- Steps:
  1. Process image with timing instrumentation
  2. Record time from start to first token
- Expected: TTFT < 3000ms on iPhone 15+
- Verify: Acceptable user experience

TC-PERF-TTFT-002: TTFT consistency
- Setup: Model loaded
- Steps:
  1. Measure TTFT for 10 consecutive inferences
  2. Calculate mean and std dev
- Expected: Variation < 20%
- Verify: Consistent performance

TC-PERF-TTFT-003: TTFT with different image sizes
- Steps:
  1. Measure TTFT for 256x256 image
  2. Measure TTFT for 512x512 image
  3. Measure TTFT for 1024x1024 image
- Expected: TTFT increases slightly with size
- Verify: Scaling is reasonable
```

### 3.3 Throughput

**Test: Inference Throughput**
```
TC-PERF-TPU-001: Inferences per minute
- Setup: Model loaded, multiple images ready
- Steps:
  1. Process 10 images sequentially
  2. Measure total time
  3. Calculate throughput
- Expected: At least 3-5 inferences per minute
- Verify: Performance is acceptable

TC-PERF-TPU-002: Sustained throughput
- Setup: Model loaded
- Steps:
  1. Process 50 images continuously
  2. Measure throughput at each 10-image interval
  3. Observe for degradation
- Expected: Throughput remains constant
- Verify: No performance degradation
```

---

## 4. STRESS TESTS

### 4.1 Concurrency Stress

**Test: Rapid Sequential Calls**
```
TC-STRESS-SEQ-001: Rapid fire inferences
- Setup: Model loaded
- Steps:
  1. Call ProcessTextureAsync 20 times rapidly
  2. Observe if CancelOnNewRequest is respected
  3. Count completed vs cancelled
- Expected: No crashes, proper cancellation
- Verify: Behavior matches SetCancelOnNewRequest setting
```

**Test: Memory Pressure**
```
TC-STRESS-MEM-001: Long running app
- Setup: Model loaded
- Steps:
  1. Run app for 30 minutes
  2. Process image every 10 seconds
  3. Monitor memory growth
- Expected: No memory issues
- Verify: App remains responsive
```

---

## 5. REGRESSION TESTS

### 5.1 Version Compatibility

**Test: iOS Version Compatibility**
```
TC-COMPAT-iOS-001: iOS 18.2 device
TC-COMPAT-iOS-002: iOS 18.3 device
TC-COMPAT-iOS-003: Latest iOS device

Each should:
- Build successfully
- Load model
- Process textures
- Return results
```

**Test: visionOS Version Compatibility**
```
TC-COMPAT-VISION-001: visionOS 2.0 device
TC-COMPAT-VISION-002: visionOS 2.1 device

Each should:
- Build successfully (with visionOS target)
- Load model
- Process textures (adjust for visionOS input method)
- Return results
```

### 5.2 Swift Package Compatibility

**Test: Swift Package Versions**
```
TC-PKG-001: Test with specified minimum versions
- mlx-swift 0.21.2
- mlx-swift-examples 2.21.2
- swift-transformers 0.1.18

Each should build successfully and inference should work

TC-PKG-002: Test with latest compatible versions
- Use latest patch versions of each package
- Verify no breaking changes
```

---

## 6. MANUAL TESTING CHECKLIST

- [ ] iOS build successful
- [ ] visionOS build successful
- [ ] Model loads in < 30 seconds
- [ ] First inference produces output
- [ ] RGBA32 texture colors correct
- [ ] BGRA32 texture colors correct
- [ ] WebCam texture streaming works
- [ ] Multiple inferences work
- [ ] Cancellation works
- [ ] Custom model path works
- [ ] Error messages are helpful
- [ ] No crashes on invalid input
- [ ] Memory usage stays bounded
- [ ] App remains responsive
- [ ] Inference output is reasonable

---

## 7. DOCUMENTATION VALIDATION

- [ ] README is up-to-date
- [ ] Code examples work as written
- [ ] Platform requirements clearly stated
- [ ] Setup steps are complete
- [ ] Error messages are documented
- [ ] Performance expectations documented
- [ ] Troubleshooting guide is helpful

