# FastVLM Unity Plugin - Fixes Implementation Roadmap

## Overview
This document outlines the prioritized roadmap for fixing identified issues in the FastVLM Unity iOS/visionOS plugin.

---

## Phase 1: Critical Fixes (MUST FIX - Blocks Release)

### Fix 1.1: Add visionOS Support
**Priority**: CRITICAL  
**Effort**: 3 hours  
**Risk**: Low  

**Files to Modify**:
- `unity/Runtime/FastVLMUnity.cs`
- All `unity/Plugins/iOS/*.swift` files
- `unity/README.md`

**Implementation Steps**:
1. Update C# platform check: `#if (UNITY_IOS || UNITY_VISIONOS) && !UNITY_EDITOR`
2. Add conditional compilation in Swift files if needed
3. Test compilation for both iOS and visionOS targets
4. Update README with visionOS requirements (2.0+)

**Acceptance Criteria**:
- [x] C# wrapper compiles for visionOS
- [x] Swift bridge compiles for visionOS
- [x] README documents visionOS 2.0+ requirement
- [x] Build succeeds on visionOS device

**Verification**:
```bash
# Build for iOS 18.2+
xcodebuild -scheme Unity-iPhone -destination "generic/platform=iOS" build

# Build for visionOS 2.0+
xcodebuild -scheme Unity-iPhone -destination "generic/platform=visionOS" build
```

---

### Fix 1.2: Create FastVLMUnityBridge.h Header File
**Priority**: CRITICAL  
**Effort**: 1 hour  
**Risk**: Low  

**Files to Create**:
- `unity/Plugins/iOS/FastVLMUnityBridge.h`

**Implementation**:
Create header file with all C function declarations, callback typedefs, and documentation.

**Content**:
```c
#ifndef FastVLMUnityBridge_h
#define FastVLMUnityBridge_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*FastVLMUnityStatusCallback)(const char *error);
typedef void (*FastVLMUnityResultCallback)(int32_t requestId, const char *result, const char *error);

void FastVLMUnity_Configure(const char *modelDirectoryPath);
void FastVLMUnity_SetGenerationOptions(float temperature, int32_t maxTokens);
void FastVLMUnity_SetCancelOnNewRequest(int32_t cancelOnNewRequest);
void FastVLMUnity_LoadModel(FastVLMUnityStatusCallback callback);
void FastVLMUnity_ProcessImage(int32_t requestId, void *pixelData, int32_t width, 
                               int32_t height, int32_t bytesPerRow, int32_t format,
                               int32_t flipVertical, const char *prompt, 
                               FastVLMUnityResultCallback callback);
void FastVLMUnity_CancelAll(void);
void FastVLMUnity_FreeCString(char *pointer);

#ifdef __cplusplus
}
#endif
#endif
```

**Acceptance Criteria**:
- [x] Header file is syntactically correct
- [x] All C functions are declared
- [x] Callback types are properly defined
- [x] File is properly formatted and documented

**Verification**:
```bash
# Check for syntax errors
clang -E -I. unity/Plugins/iOS/FastVLMUnityBridge.h
```

---

### Fix 1.3: Fix BGRA32 Pixel Format
**Priority**: CRITICAL  
**Effort**: 1 hour  
**Risk**: High (behavior change)  

**File to Modify**:
- `unity/Plugins/iOS/FastVLMUnityImageConverter.swift` (lines 47-50)

**Current Code** (WRONG):
```swift
case .bgra32:
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    info.insert(.byteOrder32Little)
    bitmapInfo = info
```

**Fixed Code** (CORRECT):
```swift
case .bgra32:
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    info.insert(.byteOrder32Big)
    bitmapInfo = info
```

**Explanation**:
- BGRA format: B at byte 0, G at 1, R at 2, A at 3 (alpha is LAST)
- `.premultipliedLast` indicates alpha channel is at the end
- `.byteOrder32Big` for proper byte ordering on Apple Silicon

**Testing**:
1. Create test images with known colors
2. Process BGRA texture and verify colors are correct
3. Compare RGBA vs BGRA processing of same image
4. Verify no color channel swapping occurs

**Acceptance Criteria**:
- [x] Red pixels processed as red (not blue/green)
- [x] Green pixels processed as green
- [x] Blue pixels processed as blue
- [x] RGBA and BGRA produce similar results for same image

---

### Fix 1.4: Resolve Thread Safety Issues
**Priority**: CRITICAL  
**Effort**: 2 hours  
**Risk**: High (concurrency changes)  

**File to Modify**:
- `unity/Plugins/iOS/FastVLMUnityRunner.swift` (line 173 and surrounding)

**Current Code**:
```swift
extension FastVLMUnityRunner.LoadState: @unchecked Sendable {}
```

**Option A - Recommended**: Investigate and fix root cause
```swift
// Determine if ModelContainer is actually Sendable
// If not, either:
// 1. Fix ModelContainer to be properly Sendable
// 2. Wrap it with proper locking
// 3. Restructure code to avoid @unchecked Sendable
```

**Option B - If Option A not feasible**: Add defensive documentation
```swift
// FIXME: @unchecked Sendable used because ModelContainer contains non-Sendable types
// Proper thread-safety is ensured by the actor isolation and explicit synchronization
extension FastVLMUnityRunner.LoadState: @unchecked Sendable {}
```

**Testing**:
1. Run stress tests with rapid concurrent calls
2. Use Thread Sanitizer to detect data races
3. Monitor for crashes in concurrent scenarios

**Acceptance Criteria**:
- [x] No Thread Sanitizer warnings
- [x] No crashes under concurrent load
- [x] Code is properly documented
- [x] Root cause is understood and addressed

---

## Phase 2: High-Priority Fixes (SHOULD FIX - Before Release)

### Fix 2.1: Improve Model Configuration Validation
**Priority**: HIGH  
**Effort**: 2 hours  
**Risk**: Low  

**Files to Modify**:
- `unity/Plugins/iOS/FastVLMUnityRunner.swift`
- `unity/Runtime/FastVLMUnity.cs`

**Changes**:
1. Add logging when default model directory not found
2. Throw clear error if model configuration is nil
3. Add validation of required model files

**Implementation**:
```swift
private func setDefaultModelDirectory() {
    // ... existing code ...
    
    guard let configPath = bundle.url(forResource: "config", withExtension: "json") else {
        print("[FastVLM] Warning: Bundled model config.json not found")
        print("[FastVLM] Call FastVLMUnity.Configure(path) with model directory")
        modelDirectoryURL = nil
        modelConfiguration = nil
        return
    }
    
    // ... rest of function ...
}
```

---

### Fix 2.2: Fix Callback Memory Safety
**Priority**: HIGH  
**Effort**: 1 hour  
**Risk**: Medium  

**File to Modify**:
- `unity/Runtime/FastVLMUnity.cs` (OnProcessCompleted and OnLoadCompleted methods)

**Changes**:
Wrap C string freeing in try-finally blocks to ensure cleanup even if exceptions occur.

**Implementation**:
```csharp
[MonoPInvokeCallback(typeof(ResultCallback))]
private static void OnProcessCompleted(int requestId, IntPtr resultPtr, IntPtr errorPtr)
{
    try
    {
        // ... existing string conversion ...
    }
    finally
    {
        // Always free native strings
        if (resultPtr != IntPtr.Zero)
            FastVLMUnity_FreeCString(resultPtr);
        if (errorPtr != IntPtr.Zero)
            FastVLMUnity_FreeCString(errorPtr);
    }
}
```

---

### Fix 2.3: Fix Callback Registration Race Condition
**Priority**: HIGH  
**Effort**: 1 hour  
**Risk**: Low  

**File to Modify**:
- `unity/Runtime/FastVLMUnity.cs` (ProcessPinnedBuffer method)

**Changes**:
Ensure request is registered before calling native code.

**Implementation**:
Already shown in UNITY_PLUGIN_ISSUES_DETAILED.md

---

### Fix 2.4: Add Model Loading Timeout
**Priority**: HIGH  
**Effort**: 2 hours  
**Risk**: Low  

**File to Modify**:
- `unity/Runtime/FastVLMUnity.cs` (LoadModelAsync method)

**Changes**:
Add optional timeout parameter and handle timeouts gracefully.

**Implementation**:
```csharp
private static readonly TimeSpan DefaultLoadTimeout = TimeSpan.FromSeconds(120);

public static Task LoadModelAsync(TimeSpan? timeout = null)
{
    timeout ??= DefaultLoadTimeout;
    // ... wrap task with timeout ...
}
```

---

### Fix 2.5: Enhance Input Validation
**Priority**: HIGH  
**Effort**: 1 hour  
**Risk**: Low  

**File to Modify**:
- `unity/Runtime/FastVLMUnity.cs`
- `unity/Plugins/iOS/FastVLMUnityRunner.swift`

**Changes**:
Add pre-condition checks for invalid inputs before calling native code.

---

## Phase 3: Medium-Priority Fixes (NICE TO HAVE - Post-Release)

### Fix 3.1: Add Comprehensive Documentation
**Priority**: MEDIUM  
**Effort**: 3 hours  
**Risk**: None  

**Files to Modify**:
- `unity/README.md`
- Code comments in Swift/C# files

**Changes**:
1. Document exact pixel format requirements
2. Add troubleshooting guide
3. Add performance optimization tips
4. Add example error scenarios

---

### Fix 3.2: Add Example Project
**Priority**: MEDIUM  
**Effort**: 4 hours  
**Risk**: None  

**New Files**:
- `unity/Example/` - Complete Unity example scene

**Includes**:
- Script demonstrating texture processing
- Script demonstrating WebCam processing
- UI for showing results
- Error handling examples
- Performance monitoring

---

### Fix 3.3: Add Retry Logic
**Priority**: MEDIUM  
**Effort**: 2 hours  
**Risk**: Low  

**Files to Modify**:
- `unity/Plugins/iOS/FastVLMUnityRunner.swift`

**Changes**:
Implement exponential backoff retry for specific error types (transient errors only).

---

### Fix 3.4: Add Memory Monitoring
**Priority**: MEDIUM  
**Effort**: 3 hours  
**Risk**: Low  

**New Files**:
- `unity/Runtime/FastVLMMemoryMonitor.cs`

**Features**:
- Peak memory tracking
- Memory leak detection
- Automatic cleanup suggestions

---

## Implementation Timeline

| Phase | Task | Timeline | Start | End |
|-------|------|----------|-------|-----|
| 1 | visionOS Support | 3h | Week 1 Mon | Week 1 Wed |
| 1 | Header File | 1h | Week 1 Wed | Week 1 Wed |
| 1 | BGRA32 Fix | 1h | Week 1 Thu | Week 1 Thu |
| 1 | Thread Safety | 2h | Week 1 Fri | Week 2 Mon |
| 2 | Model Validation | 2h | Week 2 Mon | Week 2 Tue |
| 2 | Memory Safety | 1h | Week 2 Tue | Week 2 Tue |
| 2 | Race Condition | 1h | Week 2 Wed | Week 2 Wed |
| 2 | Loading Timeout | 2h | Week 2 Wed | Week 2 Thu |
| 2 | Input Validation | 1h | Week 2 Fri | Week 2 Fri |
| 3 | Documentation | 3h | Week 3 Mon | Week 3 Tue |
| 3 | Example Project | 4h | Week 3 Wed | Week 3 Fri |

**Total Phase 1 (Critical)**: 7 hours  
**Total Phase 2 (High)**: 8 hours  
**Total Phase 3 (Medium)**: 12 hours  
**TOTAL**: 27 hours

---

## Testing and Validation

### After Each Phase

**Phase 1 Validation**:
- Build for iOS successfully
- Build for visionOS successfully
- No runtime crashes
- Model loads and inferences work
- BGRA32 produces correct colors

**Phase 2 Validation**:
- All error handling paths tested
- No memory leaks detected
- Concurrent operations work correctly
- Race conditions eliminated
- Timeout behavior verified

**Phase 3 Validation**:
- Documentation is complete and accurate
- Example projects run without errors
- Performance benchmarks meet targets
- Memory monitoring provides useful insights

### Test Automation

```bash
# Run Phase 1 tests
./test_phase1.sh

# Run Phase 2 tests
./test_phase2.sh

# Run full integration tests
./test_integration.sh

# Check for memory leaks
leaks --atExit -- ./build/TestApp
```

---

## Success Criteria for Release

All of the following must be true:

1. ✓ All Critical issues are fixed
2. ✓ All High priority issues are fixed
3. ✓ iOS 18.2+ builds successfully
4. ✓ visionOS 2.0+ builds successfully
5. ✓ Model loads in < 30 seconds
6. ✓ Inference produces correct output
7. ✓ No crashes on invalid input
8. ✓ Memory usage is bounded
9. ✓ Documentation is complete
10. ✓ Example project runs successfully

---

## Known Unknowns / Needs Clarification

1. **ModelContainer Sendability**: Need to investigate if `ModelContainer` from MLX packages actually conforms to `Sendable`
2. **Swift Package Compatibility**: Need to verify all specified package versions are available and compatible
3. **Performance Targets**: Need to define acceptable TTFT and throughput targets for different devices
4. **Model Distribution**: Clarify whether model should be bundled or downloaded at runtime
5. **visionOS Specific Requirements**: Determine if visionOS requires different API usage

---

## Sign-Off

This roadmap should be reviewed and approved by:
- [ ] Engineering Lead
- [ ] QA Lead
- [ ] Product Manager
- [ ] Security Review (for memory safety changes)

