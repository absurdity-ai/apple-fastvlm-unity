# FastVLM Unity Plugin Environment Setup Guide

This document provides comprehensive instructions for setting up the cto VM environment to support development and deployment of fast-vlm as a Unity iOS/visionOS plugin.

## Environment Overview

The cto VM is configured as a Linux Ubuntu environment suitable for:
- Python-based model development and training
- Model export and conversion
- FastAPI/Gradio inference server setup
- Unity plugin source code preparation

**Note**: For actual iOS/visionOS plugin compilation, you need a macOS environment with Xcode and Unity.

## ✅ Completed Setup

### Python Environment

- **Python Version**: 3.12.3
- **Virtual Environment**: `fastvlm-env` (activated)
- **Package Manager**: pip 25.3

### Core Dependencies

All required Python packages are installed and verified:

#### Deep Learning Framework
- **PyTorch**: 2.6.0+cpu (CPU version for Linux)
- **TorchVision**: 0.21.0+cpu
- **Transformers**: 4.48.3
- **Tokenizers**: 0.21.0
- **SentencePiece**: 0.1.99

#### Training & Optimization
- **Accelerate**: 1.6.0
- **PEFT**: 0.13.2
- **BitsAndBytes**: 0.48.2
- **Einops**: 0.6.1
- **Einops-Extensions**: 0.0.4
- **TIMM**: 1.0.15

#### Web Serving & UI
- **Gradio**: 5.11.0
- **FastAPI**: 0.121.2
- **Uvicorn**: 0.38.0
- **Pydantic**: 2.12.4

#### Model Export & Processing
- **CoreML Tools**: 8.2
- **NumPy**: 1.26.4
- **SciKit-Learn**: 1.2.2
- **Requests**: 2.32.5
- **Markdown2**: 2.5.4
- **ShortUUID**: 1.0.11

### Project Structure

All required project files are present:

```
fast-vlm/
├── unity/
│   ├── Plugins/iOS/
│   │   ├── FastVLMUnityBridge.swift ✅
│   │   ├── FastVLMUnityRunner.swift ✅
│   │   ├── FastVLMUnityError.swift ✅
│   │   └── FastVLMUnityImageConverter.swift ✅
│   └── Runtime/
│       └── FastVLMUnity.cs ✅
├── model_export/
│   ├── export_vision_encoder.py ✅
│   └── fastvlm_mlx-vlm.patch ✅
├── llava/serve/
│   ├── gradio_web_server.py ✅
│   ├── controller.py ✅
│   └── model_worker.py ✅
├── predict.py ✅
└── pyproject.toml ✅
```

### Script Functionality

All key scripts are functional:

- **✅ predict.py**: Help command works
- **✅ export_vision_encoder.py**: Help command works  
- **✅ llava serve CLI**: Help command works

## 🍎 macOS/iOS Requirements (For Actual Plugin Compilation)

The following tools are required for iOS/visionOS plugin compilation and must be installed on a macOS environment:

### Required Tools
- **Xcode**: 16.2 or later
- **Unity**: 2022.3 or later with iOS build support
- **Swift**: 5.9 or later

### Swift Package Dependencies
When building in Unity/Xcode on macOS, add these Swift packages:
- `https://github.com/ml-explore/mlx-swift` (minimum 0.21.2)
- `https://github.com/ml-explore/mlx-swift-examples` (minimum 2.21.2)
- `https://github.com/huggingface/swift-transformers` (minimum 0.1.18)

### Target Platforms
- **iOS**: 18.2+
- **visionOS**: 1.2+
- **macOS**: 15.2+ (for testing)

## 🚀 Usage Instructions

### 1. Environment Activation

```bash
source fastvlm-env/bin/activate
```

### 2. Model Export

Export vision encoder to CoreML format:
```bash
python model_export/export_vision_encoder.py --model-path /path/to/fastvlm-checkpoint
```

Export full model to MLX format:
```bash
# Clone mlx-vlm first
git clone https://github.com/Blaizzy/mlx-vlm.git
cd mlx-vlm 
git checkout 1884b551bc741f26b2d54d68fa89d4e934b9a3de
git apply ../model_export/fastvlm_mlx-vlm.patch
pip install -e .

# Export model
python -m mlx_vlm.convert --hf-path /path/to/fastvlm-checkpoint \
                          --mlx-path /path/to/exported-fastvlm \
                          --only-llm
```

### 3. Inference Server

Start Gradio web interface:
```bash
python -m llava.serve.gradio_web_server --model-path /path/to/model --port 7860
```

Start FastAPI server:
```bash
python -m llava.serve.controller --host 0.0.0.0 --port 10000
```

### 4. Unity Plugin Integration

On macOS with Unity and Xcode:

1. **Copy plugin files** to Unity project:
   ```
   Assets/Plugins/iOS/ (from unity/Plugins/iOS/)
   Assets/FastVLM/Runtime/ (from unity/Runtime/)
   ```

2. **Add Swift sources** from `app/FastVLM/`:
   - `FastVLM.swift`
   - `FastVLM.h`
   - `MediaProcessingExtensions.swift`

3. **Install Swift packages** in Xcode (see requirements above)

4. **Configure model path** and build

## 📱 Model Download

Download pretrained models using the provided script:

```bash
chmod +x app/get_pretrained_mlx_model.sh

# Download 0.5B model (fast, mobile-friendly)
app/get_pretrained_mlx_model.sh --model 0.5b --dest app/FastVLM/model

# Download 1.5B model (balanced)
app/get_pretrained_mlx_model.sh --model 1.5b --dest app/FastVLM/model

# Download 7B model (accurate, larger)
app/get_pretrained_mlx_model.sh --model 7b --dest app/FastVLM/model
```

## 🧪 Environment Validation

Run the validation script to verify setup:

```bash
source fastvlm-env/bin/activate
python validate_environment.py
```

Expected output:
```
🎉 Environment is properly configured!
Overall: 5/6 checks passed
```

The only expected failure is "iOS Dependencies" on Linux, which is normal.

## 📊 Performance Notes

### Model Sizes & Performance
- **0.5B**: ~1GB, fastest inference, ideal for mobile
- **1.5B**: ~3GB, balanced performance
- **7B**: ~12GB, most accurate, requires newer devices

### Deployment Targets
- **iOS**: Real-time inference on A17 Pro and later
- **visionOS**: Optimized for spatial computing
- **macOS**: Development and testing

## 🔧 Troubleshooting

### Common Issues

1. **CoreML Warnings**: Expected on Linux - CoreML features are macOS-only
2. **Torch CPU Version**: Normal for Linux environment, GPU version available on macOS
3. **Missing iOS Tools**: Expected on Linux - use macOS for actual iOS builds

### Performance Optimization

1. **Model Quantization**: Use 4-bit/8-bit quantization for mobile deployment
2. **Batch Processing**: Process multiple images when possible
3. **Memory Management**: Monitor memory usage on mobile devices

## 📚 Additional Resources

- [Unity Plugin README](unity/README.md) - Detailed integration guide
- [Model Export Guide](model_export/README.md) - Export instructions
- [App Documentation](app/README.md) - SwiftUI app usage
- [LLaVA Serve Documentation](llava/serve/) - Server setup

## 🎯 Next Steps

1. **Download Models**: Use the model download script for testing
2. **Test Export**: Verify model export scripts work with your checkpoints
3. **Setup macOS Environment**: Prepare Xcode/Unity for iOS compilation
4. **Unity Integration**: Follow the Unity plugin integration steps
5. **Deploy & Test**: Build and test on target iOS/visionOS devices

---

**Environment Status**: ✅ Ready for development  
**Last Updated**: 2025-01-19  
**Python Environment**: fastvlm-env  
**Validation**: All checks passed (except expected iOS dependencies on Linux)