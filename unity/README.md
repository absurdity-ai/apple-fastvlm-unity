# Unity iOS Plugin for FastVLM

This folder contains a native iOS plugin and a managed C# wrapper that expose the on-device FastVLM vision language model to Unity applications. The plugin lets you submit frames from either `Texture2D` assets or live `WebCamTexture` streams and returns the generated string output from FastVLM.

The implementation reuses the Swift components that power the sample app in [`app/`](../app) and wraps them with C-callable entry points that can be invoked from Unity builds targeting iOS 18.2 or later.

## Contents

```
unity/
├── Plugins/
│   └── iOS/
│       ├── FastVLMUnityBridge.swift      # C-callable bridge between Unity and Swift
│       ├── FastVLMUnityError.swift       # Plugin error definitions
│       ├── FastVLMUnityImageConverter.swift
│       └── FastVLMUnityRunner.swift      # Async actor that orchestrates FastVLM
├── Runtime/
│   └── FastVLMUnity.cs                   # Managed C# wrapper used from Unity scripts
└── README.md
```

## Prerequisites

- Unity 2022.3 or later with iOS build support.
- Xcode 16.2 or later targeting iOS 18.2+.
- Apple Silicon device for running the model on-device.
- A downloaded FastVLM model (see below).

## Integration steps

1. **Copy the plugin files into your Unity project**

   - Create `Assets/Plugins/iOS/` inside your Unity project if it does not already exist.
   - Copy the contents of `unity/Plugins/iOS/` from this repository into `Assets/Plugins/iOS/`.
   - Copy `unity/Runtime/FastVLMUnity.cs` into a folder that is included in your Unity build (for example `Assets/FastVLM/Runtime/`).

2. **Add the FastVLM Swift sources**

   The native plugin depends on the Swift implementation that lives in [`app/FastVLM`](../app/FastVLM). Add the following files to your Unity project (they can also be placed under `Assets/Plugins/iOS/`):

   - `app/FastVLM/FastVLM.swift`
   - `app/FastVLM/FastVLM.h`
   - `app/FastVLM/MediaProcessingExtensions.swift`

   After exporting to Xcode, confirm these files are part of the **UnityFramework** target (File Inspector → Target Membership). The plugin code compiles inside `UnityFramework`, so the FastVLM sources must be included there.

3. **Install Swift package dependencies in Xcode**

   Open the generated Xcode project (`Unity-iPhone.xcodeproj`) after exporting from Unity and add the following Swift packages (matching the versions used by the sample app):

   - [`https://github.com/ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift) – minimum version **0.21.2**.
   - [`https://github.com/ml-explore/mlx-swift-examples`](https://github.com/ml-explore/mlx-swift-examples) – minimum version **2.21.2**.
   - [`https://github.com/huggingface/swift-transformers`](https://github.com/huggingface/swift-transformers) – minimum version **0.1.18**.

   Add the `MLX`, `MLXFast`, `MLXNN`, `MLXRandom`, `MLXLMCommon`, `MLXVLM`, and `Transformers` products to the **UnityFramework** target so the plugin sources can import them. For any products that ship as dynamic frameworks, also add them to the **Unity-iPhone** target with "Embed & Sign" enabled so they are packaged into the final app.

4. **Bundle the FastVLM resources**

   Download a FastVLM model using the helper script (run from the repository root):

   ```bash
   chmod +x app/get_pretrained_mlx_model.sh
   app/get_pretrained_mlx_model.sh --model 0.5b --dest <some/output/directory>
   ```

   Copy the resulting directory (which contains `config.json`, weights, tokenizer files, etc.) into a writable location on the device. Two common approaches:

   - Ship the model inside `StreamingAssets` and move it to `Application.persistentDataPath` on first launch, or
   - Download the model on device and store it in `Application.persistentDataPath`.

   Pass the absolute directory path to `FastVLMUnity.Configure` before loading the model. If you skip configuration the plugin will look for the default resources bundled alongside the Swift sources.

5. **Build and run**

   Build your Unity project for iOS, open the Xcode project, verify that the Swift packages and source files above are present, then deploy to an iOS device running 18.2 or later.

## Using the C# wrapper

The managed wrapper exposes asynchronous helpers to run inferences from Unity scripts.

```csharp
using System.Threading.Tasks;
using Apple.FastVLM.Unity;
using UnityEngine;

public class FastVLMTextureExample : MonoBehaviour
{
    [SerializeField] private Texture2D sourceTexture;
    [TextArea] public string prompt = "Describe this image";

    private async void Start()
    {
        // Configure the model directory (optional if you bundled the default resources)
        string modelDirectory = System.IO.Path.Combine(Application.persistentDataPath, "fastvlm");
        FastVLMUnity.Configure(modelDirectory);

        await FastVLMUnity.LoadModelAsync();

        string response = await FastVLMUnity.ProcessTextureAsync(sourceTexture, prompt);
        Debug.Log($"FastVLM response: {response}");
    }
}
```

To work with a live `WebCamTexture`, reuse the same API:

```csharp
public class FastVLMWebCamExample : MonoBehaviour
{
    private WebCamTexture _webCam;
    [TextArea] public string prompt = "What is happening in this frame?";

    private async void OnEnable()
    {
        _webCam = new WebCamTexture();
        _webCam.Play();

        await FastVLMUnity.LoadModelAsync();
        InvokeRepeating(nameof(RequestFrameAnalysis), 1.0f, 2.0f);
    }

    private async void RequestFrameAnalysis()
    {
        if (_webCam == null || !_webCam.isPlaying)
        {
            return;
        }

        string response = await FastVLMUnity.ProcessWebCamFrameAsync(_webCam, prompt);
        Debug.Log($"FastVLM webcam response: {response}");
    }

    private void OnDisable()
    {
        if (_webCam != null)
        {
            _webCam.Stop();
        }

        FastVLMUnity.CancelAll();
    }
}
```

### Additional configuration

- `FastVLMUnity.SetGenerationOptions(float temperature, int maxTokens)` lets you customise sampling.
- `FastVLMUnity.SetCancelOnNewRequest(bool)` controls whether a new request cancels any in-flight inference (enabled by default).
- `FastVLMUnity.ProcessRawBytesAsync(...)` provides direct access if you already manage pixel buffers.
- `FastVLMUnity.CancelAll()` aborts the active inference and clears any pending callbacks.

## Notes & limitations

- The plugin expects RGBA32 or BGRA32 pixel layouts. The helper methods convert Unity `Color32[]` buffers into the correct format automatically.
- Model loading can take several seconds depending on the model size and device. Always await `LoadModelAsync` before issuing the first inference.
- Because iOS enforces a watchdog timeout on the main thread, avoid blocking operations. The native plugin executes FastVLM inference asynchronously and delivers the result back on the main thread.
- Ensure that the downloaded model assets remain readable at runtime (for example, mark copied files with the `Always Included Files` flag if you move them into `StreamingAssets`).

With this setup you can drive FastVLM directly from Unity on iOS, enabling low-latency, on-device multimodal interactions.
