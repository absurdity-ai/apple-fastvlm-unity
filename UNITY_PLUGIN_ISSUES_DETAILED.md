# FastVLM Unity Plugin - Detailed Issues & Fixes

## Issue 1: Missing visionOS Support

### Current State
- Only `UNITY_IOS && !UNITY_EDITOR` platform checks
- No visionOS conditional compilation
- Swift code has no platform-specific declarations

### Code Examples

**Current C# (FastVLMUnity.cs line 30):**
```csharp
#if UNITY_IOS && !UNITY_EDITOR
    // ... implementation
#else
    // ... stubs
#endif
```

**Should be:**
```csharp
#if (UNITY_IOS || UNITY_VISIONOS) && !UNITY_EDITOR
    // ... implementation
#else
    // ... stubs
#endif
```

### Files to Modify
1. `unity/Runtime/FastVLMUnity.cs` - Add UNITY_VISIONOS checks
2. `unity/Plugins/iOS/` - All Swift files should have platform guards
3. `unity/README.md` - Document visionOS requirements

### Test Cases
- Build for iOS device - should work
- Build for visionOS device - should work
- Build for macOS editor - should use stubs

---

## Issue 2: Missing Header File

### Current State
- C functions defined with `@_cdecl` in Swift
- No header file for C declarations
- C# uses P/Invoke without header reference

### Required Header File

**Create: `unity/Plugins/iOS/FastVLMUnityBridge.h`**

```c
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

// Status callback: called with error message (or NULL for success)
typedef void (*FastVLMUnityStatusCallback)(const char *error);

// Result callback: called with request ID, result string, and error string
typedef void (*FastVLMUnityResultCallback)(
    int32_t requestId,
    const char *result,
    const char *error
);

// Configure the plugin with a model directory path.
// Pass empty string or NULL to use bundled model.
void FastVLMUnity_Configure(const char *modelDirectoryPath);

// Set generation parameters.
void FastVLMUnity_SetGenerationOptions(float temperature, int32_t maxTokens);

// Control whether new requests cancel previous ones.
void FastVLMUnity_SetCancelOnNewRequest(int32_t cancelOnNewRequest);

// Load the model asynchronously.
void FastVLMUnity_LoadModel(FastVLMUnityStatusCallback callback);

// Process an image and generate text.
void FastVLMUnity_ProcessImage(
    int32_t requestId,
    void *pixelData,
    int32_t width,
    int32_t height,
    int32_t bytesPerRow,
    int32_t format,  // 0=RGBA32, 1=BGRA32
    int32_t flipVertical,
    const char *prompt,
    FastVLMUnityResultCallback callback
);

// Cancel all pending operations.
void FastVLMUnity_CancelAll(void);

// Free a C string allocated by FastVLM.
void FastVLMUnity_FreeCString(char *pointer);

#ifdef __cplusplus
}
#endif

#endif /* FastVLMUnityBridge_h */
```

### Integration Steps
1. Copy header to `unity/Plugins/iOS/FastVLMUnityBridge.h`
2. Update README with build steps for including header in Xcode project
3. Consider creating a .meta file for Unity (if using version control metadata)

---

## Issue 3: Incorrect BGRA32 Pixel Format

### Current Code (Incorrect)
```swift
// FastVLMUnityImageConverter.swift lines 47-50
case .bgra32:
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    info.insert(.byteOrder32Little)
    bitmapInfo = info
```

### Problems
1. `.premultipliedFirst` is for ARGB format (A at byte 0)
2. BGRA format has A at byte 3 (last)
3. Byte order might be incorrect

### Correct Implementation

**Option A: Using Standard Constants**
```swift
case .bgra32:
    // BGRA: byte 0=B, 1=G, 2=R, 3=A
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    info.insert(.byteOrder32Big)  // B (MSB) to A (LSB)
    bitmapInfo = info
```

**Option B: Using Explicit Bit Patterns**
```swift
case .bgra32:
    // BGRA format: 32-bit little-endian, alpha last
    let bitmapInfo = CGBitmapInfo(rawValue: 
        CGImageAlphaInfo.last.rawValue |
        CGBitmapInfo.byteOrder32Big.rawValue
    )
```

### RGBA32 Verification (lines 44-46)
Current code:
```swift
case .rgba32:
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    info.insert(.byteOrder32Big)
    bitmapInfo = info
```

This appears correct for RGBA32:
- Byte 0=R, 1=G, 2=B, 3=A (alpha last) ✓
- Big-endian ordering ✓

### Testing After Fix
```swift
// Create test image with known pattern
let testColors = [
    (r: 255, g: 0, b: 0, a: 255),    // Red
    (r: 0, g: 255, b: 0, a: 255),    // Green
    (r: 0, g: 0, b: 255, a: 255),    // Blue
]

// Verify each color processes correctly
```

---

## Issue 4: Thread Safety - Unsafe Sendable

### Current Code (Problematic)
```swift
// FastVLMUnityRunner.swift
actor FastVLMUnityRunner {
    private enum LoadState {
        case idle
        case loading(Task<ModelContainer, Error>)
        case loaded(ModelContainer)
    }
    
    private var loadState: LoadState = .idle
    // ...
}

extension FastVLMUnityRunner.LoadState: @unchecked Sendable {}
```

### Root Cause
The `@unchecked Sendable` indicates that `LoadState` contains something that's not actually `Sendable` (likely `ModelContainer`).

### Investigation Steps
1. Check if `ModelContainer` conforms to `Sendable`
2. Check if `Task<ModelContainer, Error>` is properly constrained

### Solution Options

**Option A: Fix ModelContainer Conformance**
```swift
// If ModelContainer isn't Sendable, make it Sendable:
extension ModelContainer: @unchecked Sendable {
    // If truly thread-safe, this is acceptable but should be verified
}
```

**Option B: Use Explicit Locking**
```swift
actor FastVLMUnityRunner {
    private let stateLock = NSLock()
    private var loadState: LoadState = .idle
    
    func setLoadState(_ newState: LoadState) {
        stateLock.withLock {
            loadState = newState
        }
    }
}
```

**Option C: Eliminate the Unsafe Conformance**
```swift
// Refactor to avoid @unchecked Sendable altogether
actor FastVLMUnityRunner {
    private var loadStateCache: ModelContainer?
    
    // Use more targeted Sendable conformance
}
```

### Recommendation
Investigate whether `ModelContainer` actually needs to be `Sendable`. If it contains non-thread-safe components, proper synchronization is needed.

---

## Issue 5: Model Resource Loading May Fail Silently

### Current Code
```swift
// FastVLMUnityRunner.swift lines 156-169
private func setDefaultModelDirectory() {
    let bundle = Bundle(for: FastVLM.self)
    let defaultDirectory = bundle
        .url(forResource: "config", withExtension: "json")?
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()

    if let defaultDirectory {
        modelDirectoryURL = defaultDirectory
        modelConfiguration = ModelConfiguration(directory: defaultDirectory)
    } else {
        modelDirectoryURL = nil
        modelConfiguration = nil
    }
}
```

### Problems
1. Silently fails - no logging or error indication
2. Later load attempts throw `modelDirectoryMissing` without context
3. User doesn't know they need to call `Configure()`

### Better Implementation

```swift
private func setDefaultModelDirectory() {
    let bundle = Bundle(for: FastVLM.self)
    
    guard let configPath = bundle.url(forResource: "config", withExtension: "json") else {
        print("[FastVLM] Warning: Could not find bundled model config.json")
        print("[FastVLM] You must call FastVLMUnity.Configure(path) with a valid model directory")
        modelDirectoryURL = nil
        modelConfiguration = nil
        return
    }
    
    let defaultDirectory = configPath
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
    
    modelDirectoryURL = defaultDirectory
    modelConfiguration = ModelConfiguration(directory: defaultDirectory)
    
    // Verify the directory is actually valid
    var isDir: ObjCBool = false
    if !FileManager.default.fileExists(atPath: defaultDirectory.path, isDirectory: &isDir) 
        || !isDir.boolValue {
        print("[FastVLM] Error: Model directory not found at \(defaultDirectory.path)")
        modelDirectoryURL = nil
        modelConfiguration = nil
    }
}
```

### Validation During Load

```swift
func loadModel() async throws {
    if modelConfiguration == nil {
        throw FastVLMUnityError.modelDirectoryMissing
    }
    _ = try await loadContainer()
}
```

---

## Issue 6: Memory Leak Risk in C String Callbacks

### Current Code

**Swift Bridge:**
```swift
private func createCString(from string: String?) -> UnsafeMutablePointer<CChar>? {
    guard let string else { return nil }
    return strdup(string)
}
```

**C# Wrapper:**
```csharp
if (resultPtr != IntPtr.Zero)
{
    result = Marshal.PtrToStringAnsi(resultPtr);
    FastVLMUnity_FreeCString(resultPtr);
}

if (errorPtr != IntPtr.Zero)
{
    error = Marshal.PtrToStringAnsi(errorPtr);
    FastVLMUnity_FreeCString(errorPtr);
}
```

### Problems
- No exception safety: if exception occurs between string allocation and free, leak occurs
- If callback isn't called, allocation leaks
- Multiple free operations vulnerable to exceptions

### Better Implementation (C#)

```csharp
[MonoPInvokeCallback(typeof(ResultCallback))]
private static void OnProcessCompleted(int requestId, IntPtr resultPtr, IntPtr errorPtr)
{
    string? result = null;
    string? error = null;

    try
    {
        if (resultPtr != IntPtr.Zero)
        {
            result = Marshal.PtrToStringAnsi(resultPtr);
        }

        if (errorPtr != IntPtr.Zero)
        {
            error = Marshal.PtrToStringAnsi(errorPtr);
        }

        TaskCompletionSource<string>? tcs = null;
        lock (PendingRequestsLock)
        {
            if (PendingRequests.TryGetValue(requestId, out tcs))
            {
                PendingRequests.Remove(requestId);
            }
        }

        if (tcs == null)
        {
            return;
        }

        if (!string.IsNullOrEmpty(error))
        {
            tcs.TrySetException(new InvalidOperationException(error));
        }
        else if (result != null)
        {
            tcs.TrySetResult(result);
        }
        else
        {
            tcs.TrySetResult(string.Empty);
        }
    }
    finally
    {
        // Always free native strings
        if (resultPtr != IntPtr.Zero)
        {
            FastVLMUnity_FreeCString(resultPtr);
        }

        if (errorPtr != IntPtr.Zero)
        {
            FastVLMUnity_FreeCString(errorPtr);
        }
    }
}
```

---

## Issue 7: Callback Registration Race Condition

### Current Code
```csharp
// FastVLMUnity.cs ProcessPinnedBuffer
int requestId = Interlocked.Increment(ref _nextRequestId);
var tcs = new TaskCompletionSource<string>();

lock (PendingRequestsLock)
{
    PendingRequests[requestId] = tcs;
}

FastVLMUnity_ProcessImage(
    requestId,
    pixelData,
    width,
    height,
    bytesPerRow,
    (int)format,
    flipVertical ? 1 : 0,
    prompt ?? string.Empty,
    OnProcessCompleted);
```

### Problem
Native code could invoke `OnProcessCompleted` callback immediately, before request is registered in dictionary. Callback would then return early without completing the task.

### Better Implementation

```csharp
private static Task<string> ProcessPinnedBuffer(
    IntPtr pixelData,
    int width,
    int height,
    int bytesPerRow,
    FastVLMUnityPixelFormat format,
    string prompt,
    bool flipVertical)
{
    int requestId = Interlocked.Increment(ref _nextRequestId);
    var tcs = new TaskCompletionSource<string>();

    // REGISTER REQUEST BEFORE CALLING NATIVE CODE
    lock (PendingRequestsLock)
    {
        PendingRequests[requestId] = tcs;
    }

    try
    {
        // Now safe to call native code - callback will find registered request
        FastVLMUnity_ProcessImage(
            requestId,
            pixelData,
            width,
            height,
            bytesPerRow,
            (int)format,
            flipVertical ? 1 : 0,
            prompt ?? string.Empty,
            OnProcessCompleted);
    }
    catch
    {
        // If native call fails, clean up registration
        lock (PendingRequestsLock)
        {
            PendingRequests.Remove(requestId);
        }
        throw;
    }

    return tcs.Task;
}
```

---

## Issue 8: Model Loading Timeout

### Current Code
```csharp
public static Task LoadModelAsync()
{
    lock (LoadLock)
    {
        if (_modelLoaded)
        {
            return Task.CompletedTask;
        }

        if (_loadTask != null)
        {
            return _loadTask.Task;
        }

        _loadTask = new TaskCompletionSource<bool>();
    }

    FastVLMUnity_LoadModel(OnLoadCompleted);
    return _loadTask!.Task;  // No timeout!
}
```

### Problem
Caller waits indefinitely if model loading hangs.

### Better Implementation

```csharp
private static readonly TimeSpan DefaultLoadTimeout = TimeSpan.FromSeconds(120);

public static Task LoadModelAsync(TimeSpan? timeout = null)
{
    timeout ??= DefaultLoadTimeout;
    
    lock (LoadLock)
    {
        if (_modelLoaded)
        {
            return Task.CompletedTask;
        }

        if (_loadTask != null)
        {
            return _loadTask.Task;
        }

        _loadTask = new TaskCompletionSource<bool>();
    }

    FastVLMUnity_LoadModel(OnLoadCompleted);
    
    var task = _loadTask!.Task;
    
    // Wrap with timeout
    return task.TimeoutAfter(timeout.Value);
}

private static async Task<T> TimeoutAfter<T>(this Task<T> task, TimeSpan timeout)
{
    using (var cts = new CancellationTokenSource(timeout))
    {
        try
        {
            return await task.ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw new TimeoutException($"Model loading timed out after {timeout.TotalSeconds} seconds");
        }
    }
}
```

---

## Summary of Fixes

| Issue | Priority | Effort | Risk |
|-------|----------|--------|------|
| visionOS Support | CRITICAL | Medium | Low |
| Header File | CRITICAL | Low | Low |
| BGRA32 Format | CRITICAL | Low | High |
| Thread Safety | CRITICAL | Medium | High |
| Model Loading Validation | HIGH | Low | Low |
| Callback Memory Safety | HIGH | Low | Medium |
| Callback Race Condition | HIGH | Low | Medium |
| Model Loading Timeout | HIGH | Medium | Low |
| Input Validation | MEDIUM | Low | Low |
| Documentation | MEDIUM | Low | Low |

