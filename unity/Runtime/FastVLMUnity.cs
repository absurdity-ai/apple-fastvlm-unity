//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using AOT;
using UnityEngine;

namespace Apple.FastVLM.Unity
{
    /// <summary>
    /// Supported pixel formats for the FastVLM Unity plugin.
    /// </summary>
    public enum FastVLMUnityPixelFormat
    {
        RGBA32 = 0,
        BGRA32 = 1,
    }

    /// <summary>
    /// Managed wrapper around the native FastVLM iOS plugin.
    /// </summary>
    public static class FastVLMUnity
    {
#if UNITY_IOS && !UNITY_EDITOR
        private const string DllName = "__Internal";

        private delegate void ResultCallback(int requestId, IntPtr result, IntPtr error);
        private delegate void StatusCallback(IntPtr error);

        [DllImport(DllName)]
        private static extern void FastVLMUnity_Configure(string modelDirectory);

        [DllImport(DllName)]
        private static extern void FastVLMUnity_SetGenerationOptions(float temperature, int maxTokens);

        [DllImport(DllName)]
        private static extern void FastVLMUnity_SetCancelOnNewRequest(int cancelOnNewRequest);

        [DllImport(DllName)]
        private static extern void FastVLMUnity_LoadModel(StatusCallback callback);

        [DllImport(DllName)]
        private static extern void FastVLMUnity_ProcessImage(
            int requestId,
            IntPtr pixelData,
            int width,
            int height,
            int bytesPerRow,
            int format,
            int flipVertical,
            string prompt,
            ResultCallback callback);

        [DllImport(DllName)]
        private static extern void FastVLMUnity_CancelAll();

        [DllImport(DllName)]
        private static extern void FastVLMUnity_FreeCString(IntPtr pointer);

        private static readonly Dictionary<int, TaskCompletionSource<string>> PendingRequests = new();
        private static readonly object PendingRequestsLock = new();
        private static int _nextRequestId = 1;

        private static readonly object LoadLock = new();
        private static TaskCompletionSource<bool>? _loadTask;
        private static bool _modelLoaded;

        static FastVLMUnity()
        {
            SetCancelOnNewRequest(true);
        }

        /// <summary>
        /// Configure the plugin with a model directory. If not called, the plugin uses the bundled model configuration.
        /// </summary>
        public static void Configure(string modelDirectory)
        {
            FastVLMUnity_Configure(modelDirectory ?? string.Empty);
        }

        /// <summary>
        /// Configure sampling parameters. Temperature defaults to 0.0 and maxTokens defaults to 240.
        /// </summary>
        public static void SetGenerationOptions(float temperature, int maxTokens = 240)
        {
            if (maxTokens <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(maxTokens), "Max tokens must be positive.");
            }

            FastVLMUnity_SetGenerationOptions(temperature, maxTokens);
        }

        /// <summary>
        /// When enabled, starting a new request cancels the currently running request (default true).
        /// </summary>
        public static void SetCancelOnNewRequest(bool cancelPreviousRequests)
        {
            FastVLMUnity_SetCancelOnNewRequest(cancelPreviousRequests ? 1 : 0);
        }

        /// <summary>
        /// Ensure the model is loaded before issuing inference requests.
        /// </summary>
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
            return _loadTask!.Task;
        }

        /// <summary>
        /// Run FastVLM against a readable Texture2D. Texture data is copied on the CPU prior to dispatch.
        /// </summary>
        public static Task<string> ProcessTextureAsync(Texture2D texture, string prompt, bool flipVertical = true)
        {
            if (texture == null)
            {
                throw new ArgumentNullException(nameof(texture));
            }

            if (!texture.isReadable)
            {
                throw new InvalidOperationException("Texture must be readable. Enable Read/Write on the Texture2D import settings.");
            }

            Color32[] pixels = texture.GetPixels32();
            return ProcessColorsAsync(pixels, texture.width, texture.height, prompt, flipVertical);
        }

        /// <summary>
        /// Run FastVLM on the latest frame of a WebCamTexture.
        /// </summary>
        public static Task<string> ProcessWebCamFrameAsync(WebCamTexture webCamTexture, string prompt, bool flipVertical = true)
        {
            if (webCamTexture == null)
            {
                throw new ArgumentNullException(nameof(webCamTexture));
            }

            if (webCamTexture.width <= 0 || webCamTexture.height <= 0)
            {
                throw new InvalidOperationException("WebCamTexture has not started streaming yet.");
            }

            Color32[] pixels = webCamTexture.GetPixels32();
            return ProcessColorsAsync(pixels, webCamTexture.width, webCamTexture.height, prompt, flipVertical);
        }

        /// <summary>
        /// Run FastVLM on raw pixel bytes. Data must remain valid for the duration of the call.
        /// </summary>
        public static Task<string> ProcessRawBytesAsync(
            byte[] pixelBytes,
            int width,
            int height,
            int bytesPerRow,
            FastVLMUnityPixelFormat format,
            string prompt,
            bool flipVertical = true)
        {
            if (pixelBytes == null)
            {
                throw new ArgumentNullException(nameof(pixelBytes));
            }

            if (width <= 0 || height <= 0 || bytesPerRow <= 0)
            {
                throw new ArgumentOutOfRangeException("Width, height, and bytesPerRow must be positive.");
            }

            if (pixelBytes.Length < bytesPerRow * height)
            {
                throw new ArgumentException("Pixel buffer is smaller than expected for the specified dimensions.", nameof(pixelBytes));
            }

            var handle = GCHandle.Alloc(pixelBytes, GCHandleType.Pinned);
            try
            {
                return ProcessPinnedBuffer(handle.AddrOfPinnedObject(), width, height, bytesPerRow, format, prompt, flipVertical);
            }
            finally
            {
                handle.Free();
            }
        }

        /// <summary>
        /// Cancel all pending requests and abort the active inference if possible.
        /// </summary>
        public static void CancelAll()
        {
            FastVLMUnity_CancelAll();

            lock (PendingRequestsLock)
            {
                foreach (TaskCompletionSource<string> pending in PendingRequests.Values)
                {
                    pending.TrySetCanceled();
                }

                PendingRequests.Clear();
            }
        }

        private static Task<string> ProcessColorsAsync(Color32[] pixels, int width, int height, string prompt, bool flipVertical)
        {
            if (pixels == null)
            {
                throw new ArgumentNullException(nameof(pixels));
            }

            if (width <= 0 || height <= 0)
            {
                throw new ArgumentOutOfRangeException("Width and height must be positive.");
            }

            if (pixels.Length < width * height)
            {
                throw new ArgumentException("Pixel buffer does not match the supplied dimensions.", nameof(pixels));
            }

            byte[] raw = new byte[pixels.Length * 4];
            Buffer.BlockCopy(pixels, 0, raw, 0, raw.Length);
            return ProcessRawBytesAsync(raw, width, height, width * 4, FastVLMUnityPixelFormat.RGBA32, prompt, flipVertical);
        }

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

            return tcs.Task;
        }

        [MonoPInvokeCallback(typeof(ResultCallback))]
        private static void OnProcessCompleted(int requestId, IntPtr resultPtr, IntPtr errorPtr)
        {
            string? result = null;
            string? error = null;

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

        [MonoPInvokeCallback(typeof(StatusCallback))]
        private static void OnLoadCompleted(IntPtr errorPtr)
        {
            string? error = null;
            if (errorPtr != IntPtr.Zero)
            {
                error = Marshal.PtrToStringAnsi(errorPtr);
                FastVLMUnity_FreeCString(errorPtr);
            }

            TaskCompletionSource<bool>? tcs;
            lock (LoadLock)
            {
                tcs = _loadTask;
                if (string.IsNullOrEmpty(error))
                {
                    _modelLoaded = true;
                }
                _loadTask = null;
            }

            if (tcs == null)
            {
                return;
            }

            if (!string.IsNullOrEmpty(error))
            {
                tcs.TrySetException(new InvalidOperationException(error));
            }
            else
            {
                tcs.TrySetResult(true);
            }
        }
#else
        public static void Configure(string modelDirectory)
        {
            Debug.LogWarning("FastVLMUnity is only available when building for iOS devices.");
        }

        public static void SetGenerationOptions(float temperature, int maxTokens = 240)
        {
        }

        public static void SetCancelOnNewRequest(bool cancelPreviousRequests)
        {
        }

        public static Task LoadModelAsync()
        {
            return Task.FromException(new PlatformNotSupportedException("FastVLMUnity is only supported on iOS."));
        }

        public static Task<string> ProcessTextureAsync(Texture2D texture, string prompt, bool flipVertical = true)
        {
            return Task.FromException<string>(new PlatformNotSupportedException("FastVLMUnity is only supported on iOS."));
        }

        public static Task<string> ProcessWebCamFrameAsync(WebCamTexture webCamTexture, string prompt, bool flipVertical = true)
        {
            return Task.FromException<string>(new PlatformNotSupportedException("FastVLMUnity is only supported on iOS."));
        }

        public static Task<string> ProcessRawBytesAsync(
            byte[] pixelBytes,
            int width,
            int height,
            int bytesPerRow,
            FastVLMUnityPixelFormat format,
            string prompt,
            bool flipVertical = true)
        {
            return Task.FromException<string>(new PlatformNotSupportedException("FastVLMUnity is only supported on iOS."));
        }

        public static void CancelAll()
        {
        }
#endif
    }
}
