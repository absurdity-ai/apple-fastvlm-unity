# FastVLM Unity iOS/visionOS Plugin - QA Report

**Date**: 2025-01-XX  
**Status**: Initial Analysis Complete  
**Branch**: qa-diagnose-unity-ios-visionos-plugin-issues

---

## Executive Summary

This report documents a comprehensive quality assurance analysis of the FastVLM Unity iOS/visionOS plugin implementation. The plugin provides C# and Swift bridges to integrate on-device FastVLM model inference into Unity applications targeting iOS 18.2+. Multiple critical and moderate issues have been identified across build configuration, platform support, memory management, and integration aspects.

**Total Issues Found**: 15  
**Critical Issues**: 4  
**High Issues**: 5  
**Medium Issues**: 4  
**Low Issues**: 2

---

## 1. CRITICAL ISSUES

### Issue 1.1: Missing visionOS Support (CRITICAL)
**Category**: Platform Support / Build Configuration  
**Severity**: CRITICAL  
**File(s)**: All Swift files, README.md

#### Description
The ticket specifically requests support for both iOS and visionOS, but the current implementation only targets iOS. There is:
- No visionOS-specific platform check in code
- No conditional compilation for visionOS targets
- README states "iOS 18.2 or later" with no mention of visionOS requirements
- No separate Swift files or build configuration for visionOS
- The C# wrapper doesn't have visionOS platform checks

#### Impact
- Plugin cannot be built or run on visionOS
- Violates explicit acceptance criteria in ticket

#### Recommendation
1. Create visionOS-specific build configurations
2. Add platform checks using `#if os(visionOS)` / `#if os(iOS)`
3. Update README to document visionOS 2.0+ requirement
4. Test compilation for both platforms
5. Create separate or conditional imports for visionOS-specific APIs if needed

#### Evidence
- Swift code uses no platform-specific conditionals
- C# wrapper only checks for `UNITY_IOS`
- No visionOS mention in README

---

### Issue 1.2: Missing C Header File for Plugin Declaration (CRITICAL)
**Category**: Build Configuration / Integration  
**Severity**: CRITICAL  
**File(s)**: unity/Plugins/iOS/ (missing file)

#### Description
The Swift bridge files use `@_cdecl` decorator to create C-callable functions, but there is no corresponding header file (`.h`) that declares these C functions. This is required by:
- Unity build system to properly link the plugin
- Xcode project to recognize the C interface
- Type safety during compilation

Missing functions that should be declared in a header:
```c
void FastVLMUnity_Configure(const char *modelDirectory);
void FastVLMUnity_SetGenerationOptions(float temperature, int maxTokens);
void FastVLMUnity_SetCancelOnNewRequest(int cancelOnNewRequest);
void FastVLMUnity_LoadModel(FastVLMUnityStatusCallback callback);
void FastVLMUnity_ProcessImage(int requestId, void *pixelData, int width, int height, 
                               int bytesPerRow, int format, int flipVertical, 
                               const char *prompt, FastVLMUnityResultCallback callback);
void FastVLMUnity_CancelAll(void);
void FastVLMUnity_FreeCString(char *pointer);
```

#### Impact
- Xcode project generation from Unity may fail with undefined symbol errors
- No IDE autocomplete or type checking during compilation
- Build failures on clean project setup

#### Recommendation
1. Create `FastVLMUnityBridge.h` header file with complete C declarations
2. Define callback typedef declarations matching Swift functions
3. Place in `unity/Plugins/iOS/FastVLMUnityBridge.h`
4. Include in Xcode project post-generation

---

### Issue 1.3: Incorrect BGRA32 Pixel Format Configuration (CRITICAL)
**Category**: Image Processing / Data Format  
**Severity**: CRITICAL  
**File(s)**: `unity/Plugins/iOS/FastVLMUnityImageConverter.swift` (lines 47-50)

#### Description
The BGRA32 format bitmap configuration appears incorrect:
```swift
case .bgra32:
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    info.insert(.byteOrder32Little)
    bitmapInfo = info
```

Issues identified:
1. `.premultipliedFirst` is for ARGB format (alpha in first byte), not BGRA
2. For BGRA format (B=first, G, R, A=last), should use `.premultipliedLast`
3. `.byteOrder32Little` is correct for little-endian systems (Apple Silicon), but combined with wrong alpha placement will cause color channel misinterpretation
4. RGBA32 setup (lines 44-46) also needs verification for correctness

#### Impact
- BGRA32 textures will display with incorrect colors (color channels swapped/misaligned)
- Images from WebCam or imported as BGRA will produce garbled visual analysis results
- Model may return incorrect analysis due to corrupt input data

#### Expected Behavior
- BGRA32: B in byte 0, G in byte 1, R in byte 2, A in byte 3
- Should use `.premultipliedLast` to indicate alpha is last
- RGBA32: R in byte 0, G in byte 1, B in byte 2, A in byte 3

#### Recommendation
1. Change BGRA32 alpha info from `.premultipliedFirst` to `.premultipliedLast`
2. Consider using `.byteOrder32Big` for BGRA (verify on actual hardware)
3. Add test images with known pixel patterns to verify format handling
4. Test both RGBA and BGRA pixel layouts with actual device

---

### Issue 1.4: Thread Safety - Unsafe Sendable Conformance (CRITICAL)
**Category**: Concurrency / Thread Safety  
**Severity**: CRITICAL  
**File(s)**: `unity/Plugins/iOS/FastVLMUnityRunner.swift` (line 173)

#### Description
```swift
extension FastVLMUnityRunner.LoadState: @unchecked Sendable {}
```

The `@unchecked Sendable` conformance at the end of the file indicates thread safety requirements that are NOT actually verified. The `LoadState` enum contains:
```swift
private enum LoadState {
    case idle
    case loading(Task<ModelContainer, Error>)
    case loaded(ModelContainer)
}
```

Problems:
1. `@unchecked Sendable` suppresses compiler checks - dangerous in concurrent code
2. No synchronization around `loadState` variable access in the actor
3. The `ModelContainer` may not itself be `Sendable`
4. Callbacks are dispatched to MainActor but state mutations happen in detached tasks

#### Potential Runtime Issues
- Data races if accessed from multiple threads
- Crashes due to concurrent mutation of `loadState`
- Memory corruption in Swift runtime

#### Recommendation
1. Investigate why `ModelContainer` isn't `Sendable`
2. Either fix the underlying type or properly document the thread safety invariants
3. Consider using explicit locking if `ModelContainer` cannot be `Sendable`
4. Remove `@unchecked` and fix actual conformance issues

---

## 2. HIGH SEVERITY ISSUES

### Issue 2.1: Model Resource Loading May Fail with Unity Distribution (HIGH)
**Category**: Resource Management / Configuration  
**Severity**: HIGH  
**File(s)**: `unity/Plugins/iOS/FastVLMUnityRunner.swift` (lines 156-169)

#### Description
The `setDefaultModelDirectory()` function attempts to locate model resources:
```swift
let bundle = Bundle(for: FastVLM.self)
let defaultDirectory = bundle
    .url(forResource: "config", withExtension: "json")?
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
```

This approach has issues:
1. `Bundle(for: FastVLM.self)` may not work correctly when FastVLM is compiled as part of Unity's plugin framework
2. The `Bundle` class instance is initialized with a class from the FastVLM module, but this module might not have the resources embedded
3. No fallback if bundle lookup fails - silently sets `modelDirectoryURL = nil`
4. When called without explicit `Configure()`, model loading will silently fail

#### Impact
- Silent failures when model resources aren't properly bundled
- Users won't know why model loading fails
- No clear error message guiding developers to use `Configure()` with correct path

#### Reproduction Steps
1. Build Unity project for iOS without explicitly calling `FastVLMUnity.Configure()`
2. Attempt to load model with default resources
3. Model loading fails silently or throws cryptic error

#### Recommendation
1. Add explicit logging when default directory lookup fails
2. Throw or return error instead of silently succeeding with nil
3. Document in README the importance of calling `Configure()` or including model resources in bundle
4. Add validation in `loadModel()` to check if `modelConfiguration` is nil and provide clear error

---

### Issue 2.2: Memory Leak Risk in C String Callbacks (HIGH)
**Category**: Memory Management  
**Severity**: HIGH  
**File(s)**: Multiple - callback system

#### Description
The bridge uses `createCString()` function (line 139-141 in FastVLMUnityBridge.swift):
```swift
private func createCString(from string: String?) -> UnsafeMutablePointer<CChar>? {
    guard let string else { return nil }
    return strdup(string)
}
```

And in C#, these are freed:
```csharp
FastVLMUnity_FreeCString(resultPtr);
```

Problems:
1. If the C# callback never gets invoked (e.g., due to crash or memory corruption), the string is leaked
2. If an exception occurs in the callback between receiving the pointer and freeing it, leak occurs
3. No try-finally block in C# to guarantee cleanup
4. If multiple strings are returned and an exception occurs after first free but before second, second free will be skipped

#### Potential Issues
Memory leaks in long-running applications (e.g., repeated inference calls):
- Each failed callback = 1KB+ leaked (error message + result string)
- After 1000 requests: 1-2MB+ leaked
- Eventually crashes app due to memory pressure

#### Evidence
C# callback implementation (FastVLMUnity.cs, lines 285-295):
```csharp
if (resultPtr != IntPtr.Zero)
{
    result = Marshal.PtrToStringAnsi(resultPtr);
    FastVLMUnity_FreeCString(resultPtr);  // Not in try block!
}

if (errorPtr != IntPtr.Zero)
{
    error = Marshal.PtrToStringAnsi(errorPtr);
    FastVLMUnity_FreeCString(errorPtr);   // Not in try block!
}
```

#### Recommendation
1. Add try-finally blocks around C string handling
2. Consider using try-catch wrapper in callback
3. Implement reference counting for C strings
4. Add defensive null checks before free

---

### Issue 2.3: No Validation of Model Configuration Before Use (HIGH)
**Category**: Error Handling / Validation  
**Severity**: HIGH  
**File(s)**: `unity/Plugins/iOS/FastVLMUnityRunner.swift` (lines 118-121)

#### Description
In `loadContainer()`:
```swift
guard let modelConfiguration, let modelDirectoryURL else {
    throw FastVLMUnityError.modelDirectoryMissing
}
```

Then immediately:
```swift
var isDirectory: ObjCBool = false
if !FileManager.default.fileExists(atPath: modelDirectoryURL.path, isDirectory: &isDirectory)
    || !isDirectory.boolValue
{
    throw FastVLMUnityError.modelResourcesMissing(modelDirectoryURL.path)
}
```

Issues:
1. If model path is set but config.json is actually missing, the error occurs late (during file validation)
2. No check that required model files exist (weights, tokenizer, etc.)
3. No validation that model version/format is compatible
4. Error messages don't distinguish between "directory missing" vs "directory doesn't contain valid model"

#### Impact
- Users get vague error messages
- No way to pre-validate model setup before attempting inference
- Hard to debug model setup issues

#### Recommendation
1. Add explicit validation of all required model files during `loadModel()` call
2. Create detailed error messages listing missing files
3. Add public validation method: `ValidateModelPath(string path) -> ValidationResult`

---

### Issue 2.4: No Timeout or Cancellation Support for Model Loading (HIGH)
**Category**: Resource Management / User Experience  
**Severity**: HIGH  
**File(s)**: `unity/Plugins/iOS/FastVLMUnityRunner.swift`, `unity/Runtime/FastVLMUnity.cs`

#### Description
The `LoadModelAsync()` method has no timeout mechanism:
```csharp
public static Task LoadModelAsync()
{
    // ... returns _loadTask!.Task without timeout
}
```

And in Swift:
```swift
func loadModel() async throws {
    _ = try await loadContainer()
}
```

Issues:
1. Model loading can take 10-30+ seconds on some devices
2. No timeout if loading hangs
3. No cancellation token or way to cancel loading
4. Main thread callback might be delayed indefinitely
5. Users have no feedback that loading is in progress

#### Potential Issues
- App appears frozen during model loading
- No way to cancel long operations
- Network-like requests appear to hang

#### Recommendation
1. Add timeout parameter (e.g., 60 seconds) to LoadModelAsync
2. Implement CancellationToken support
3. Add progress callback
4. Display loading progress in UI

---

### Issue 2.5: Callback Registration Race Condition (HIGH)
**Category**: Concurrency / Race Conditions  
**Severity**: HIGH  
**File(s)**: `unity/Runtime/FastVLMUnity.cs` (lines 257-276)

#### Description
In `ProcessPinnedBuffer()`:
```csharp
int requestId = Interlocked.Increment(ref _nextRequestId);
var tcs = new TaskCompletionSource<string>();

lock (PendingRequestsLock)
{
    PendingRequests[requestId] = tcs;
}

FastVLMUnity_ProcessImage(..., OnProcessCompleted);
```

Issue:
- `requestId` is incremented and stored AFTER the call to native code
- If native code calls callback immediately (synchronously or very quickly), it might use a requestId that hasn't been registered yet
- This is a classic TOCTOU (time-of-check-time-of-use) race condition

#### Potential Issues
- Callbacks processed before request is registered
- `OnProcessCompleted` returns early (line 306-308) because request isn't in dictionary
- Task never completes, caller waits forever
- Silent hang that's hard to debug

#### Recommendation
1. Register request ID before calling native code
2. Use lock to ensure atomicity

---

## 3. MEDIUM SEVERITY ISSUES

### Issue 3.1: Weak Callback Type Safety (MEDIUM)
**Category**: Type Safety / Build  
**Severity**: MEDIUM  
**File(s)**: `unity/Runtime/FastVLMUnity.cs` (lines 33-34)

#### Description
```csharp
private delegate void ResultCallback(int requestId, IntPtr result, IntPtr error);
private delegate void StatusCallback(IntPtr error);
```

And in C#:
```csharp
[DllImport(DllName)]
private static extern void FastVLMUnity_ProcessImage(..., ResultCallback callback);
```

Issues:
1. Delegate type signatures must exactly match C function signatures
2. No validation that C# delegates match Swift @convention(c) signatures
3. If mismatch occurs, crashes are hard to debug
4. No documentation of exact signature requirements

#### Recommendation
1. Create header file with exact C signatures
2. Add comments documenting delegate requirements
3. Consider using typed wrapper instead of IntPtr for result/error

---

### Issue 3.2: Insufficient Input Validation in C# Wrapper (MEDIUM)
**Category**: Input Validation / Error Handling  
**Severity**: MEDIUM  
**File(s)**: `unity/Runtime/FastVLMUnity.cs`

#### Description
Several validation gaps:
1. `ProcessTextureAsync()` - Doesn't validate texture is actually readable on the platform
2. `ProcessColorsAsync()` - Validates length but not null bytes
3. `ProcessRawBytesAsync()` - Doesn't validate pixel data format matches specified dimensions
4. `Configure()` - Accepts empty string without validation

Issues:
```csharp
public static void Configure(string modelDirectory)
{
    FastVLMUnity_Configure(modelDirectory ?? string.Empty);  // Empty string silently accepted
}
```

#### Impact
- Invalid data passed to native code
- Hard-to-debug native crashes
- Poor error messages

#### Recommendation
1. Add validation that model directory exists and is readable
2. Add validation that texture data makes sense
3. Throw exceptions for obviously invalid inputs

---

### Issue 3.3: Missing Documentation of Pixel Format Requirements (MEDIUM)
**Category**: Documentation / Integration  
**Severity**: MEDIUM  
**File(s)**: README.md, FastVLMUnity.cs

#### Description
The README states (line 154):
```
The plugin expects RGBA32 or BGRA32 pixel layouts. The helper methods convert Unity `Color32[]` 
buffers into the correct format automatically.
```

But:
1. No explanation of what "correct format" means
2. No documentation of byte order requirements
3. No warning about pixel format conversions being CPU-intensive
4. No explanation of when to use each format
5. No mention that BGRA might have issues (given Issue 1.3)

#### Impact
- Developers don't understand performance implications of format choice
- Confusion about byte order and color channel mappings
- Potential data corruption if format misunderstood

#### Recommendation
1. Document exact byte order for each format
2. Add performance notes about format conversion
3. Add troubleshooting section for color issues
4. Provide test images for format validation

---

### Issue 3.4: No Error Recovery or Retry Logic (MEDIUM)
**Category**: Error Handling / Robustness  
**Severity**: MEDIUM  
**File(s)**: `unity/Plugins/iOS/FastVLMUnityRunner.swift`, `unity/Runtime/FastVLMUnity.cs`

#### Description
Error handling is minimal:
```swift
catch {
    throw error  // Just re-throw, no context added
}
```

No automatic retry for:
- Transient memory errors
- GPU allocation failures  
- Model initialization failures
- Inference timeouts

#### Impact
- Single transient failure causes entire operation to fail
- No resilience to temporary resource constraints
- User-facing errors are unhelpful

#### Recommendation
1. Implement exponential backoff retry for specific error types
2. Add better error messages with recovery suggestions
3. Consider automatic model reload on certain failures

---

## 4. LOW SEVERITY ISSUES

### Issue 4.1: Platform Availability Checking (LOW)
**Category**: Build / Platform Support  
**Severity**: LOW  
**File(s)**: Code uses iOS-specific APIs

#### Description
No explicit platform availability checks for iOS 18.2 minimum requirement. Potential issues:
- Code might compile for iOS 17.x by accident
- No @available annotations on iOS 18.2+ features
- No version checking in Configure method

#### Recommendation
Add minimum deployment target checks in build configuration

---

### Issue 4.2: Missing Integration Tests or Example Project (LOW)
**Category**: Testing / Quality Assurance  
**Severity**: LOW  
**File(s)**: unity/ directory

#### Description
No example Unity project demonstrating:
- Proper configuration and setup
- Error handling patterns
- Performance optimization techniques
- Texture vs WebCam usage

#### Recommendation
Create example Unity scene demonstrating all major features

---

## 5. BUILD AND COMPILATION ISSUES

### Issue 5.1: Swift Package Dependency Versions Not Verified
**Category**: Build Configuration  
**File(s)**: README.md (lines 51-53)

The README specifies package versions but doesn't verify they're actually compatible:
- mlx-swift 0.21.2
- mlx-swift-examples 2.21.2
- swift-transformers 0.1.18

Unknown:
1. Are these versions actually available?
2. Are they tested together?
3. What happens if user installs different versions?
4. Are there known incompatibilities?

### Issue 5.2: No Build Target Configuration Documentation
**Category**: Build Configuration  
**File(s)**: README.md

Missing:
1. Exact steps to configure build target in Xcode
2. Required build settings
3. Linking configuration
4. Deployment target settings
5. Code signing requirements

---

## 6. INTEGRATION AND RUNTIME ISSUES

### Issue 6.1: Model Loading Silent Failure
When Configure() is not called and default model loading fails, error is unclear:
- Throws `FastVLMUnityError.modelDirectoryMissing`
- But user never called Configure, so unclear what they should do

### Issue 6.2: WebCam Texture Size Validation
In C#, checking webCamTexture.width/height might race if texture stops playing:
```csharp
if (webCamTexture.width <= 0 || webCamTexture.height <= 0)
{
    throw new InvalidOperationException("WebCamTexture has not started streaming yet.");
}
```

Race condition: texture could stop between check and GetPixels32() call.

### Issue 6.3: Memory Spike During Inference
No documentation of:
- Peak memory usage during model loading (often 200-400MB)
- Peak memory during inference (100-200MB)
- Peak temporary buffers during image conversion
- GC pressure and allocation patterns

---

## 7. SUMMARY OF ACTIONABLE ISSUES

### Must Fix Before Release (Critical Path)
1. ✗ Add visionOS support and platform conditionals
2. ✗ Create FastVLMUnityBridge.h header file
3. ✗ Fix BGRA32 pixel format configuration
4. ✗ Resolve thread safety issues (@unchecked Sendable)

### Should Fix (High Priority)
5. ✗ Add model configuration validation
6. ✗ Fix callback registration race condition
7. ✗ Add memory safety in callbacks
8. ✗ Implement model loading timeout
9. ✗ Improve error messages for configuration issues

### Nice to Have (Medium Priority)
10. ✗ Add comprehensive test examples
11. ✗ Improve pixel format documentation
12. ✗ Add retry logic for transient failures
13. ✗ Create example Unity project

---

## 8. TESTING RECOMMENDATIONS

### Manual Testing Checklist
- [ ] Build for iOS 18.2+ device successfully
- [ ] Build for visionOS 2.0+ device successfully
- [ ] Model loads and initializes correctly
- [ ] RGBA32 texture processing produces correct results
- [ ] BGRA32 texture processing produces correct results  
- [ ] WebCam texture streaming works
- [ ] Prompt processing returns valid output
- [ ] Multiple consecutive inferences work
- [ ] Cancel operation works correctly
- [ ] Memory usage stays bounded over time
- [ ] Error handling doesn't crash app
- [ ] Custom model paths work correctly

### Automated Testing Recommendations
- Unit tests for C# wrapper
- Integration tests with mock Swift bridge
- Memory leak detection
- Performance benchmarks

---

## 9. DELIVERABLES AND FOLLOW-UP

This analysis identified 15 issues:
- **4 Critical** (must fix)
- **5 High** (should fix)
- **4 Medium** (nice to have)
- **2 Low** (documentation/polish)

Recommended next steps:
1. Fix all Critical issues (1.1-1.4)
2. Fix High issues (2.1-2.5)
3. Create fixes implementation plan with PR reviews
4. Add comprehensive testing
5. Update documentation

