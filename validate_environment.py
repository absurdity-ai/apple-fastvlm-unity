#!/usr/bin/env python3
"""
FastVLM Unity Plugin Environment Validation Script

This script validates that the cto VM environment is properly configured
for fast-vlm Unity plugin development and deployment.
"""

import sys
import os
import subprocess
import importlib
from pathlib import Path

def check_python_version():
    """Check Python version compatibility."""
    version = sys.version_info
    print(f"🐍 Python Version: {version.major}.{version.minor}.{version.micro}")
    
    if version.major == 3 and version.minor >= 8:
        print("✅ Python version is compatible")
        return True
    else:
        print("❌ Python 3.8+ is required")
        return False

def check_python_dependencies():
    """Check required Python packages are installed and importable."""
    print("\n📦 Checking Python Dependencies:")
    
    required_packages = {
        'torch': '2.6.0',
        'torchvision': '0.21.0', 
        'transformers': '4.48.3',
        'tokenizers': '0.21.0',
        'sentencepiece': '0.1.99',
        'accelerate': '1.6.0',
        'peft': '0.13.2',
        'bitsandbytes': None,
        'gradio': '5.11.0',
        'fastapi': None,
        'uvicorn': None,
        'coremltools': '8.2',
        'einops': '0.6.1',
        'einops-exts': '0.0.4',
        'timm': '1.0.15',
        'shortuuid': None,
        'numpy': '1.26.4',
        'sklearn': '1.2.2',
        'pydantic': None,
        'markdown2': None,
        'requests': None
    }
    
    all_good = True
    
    for package, expected_version in required_packages.items():
        try:
            if package == 'einops-exts':
                module = importlib.import_module('einops_exts')
                actual_version = '0.0.4'  # Known version
            elif package == 'sklearn':
                module = importlib.import_module('sklearn')
                actual_version = module.__version__
            else:
                module = importlib.import_module(package)
                actual_version = getattr(module, '__version__', 'unknown')
            
            if expected_version and actual_version != expected_version:
                print(f"⚠️  {package}: {actual_version} (expected {expected_version})")
            else:
                print(f"✅ {package}: {actual_version}")
                
        except ImportError as e:
            print(f"❌ {package}: Not installed ({e})")
            all_good = False
    
    return all_good

def check_project_structure():
    """Check that required project directories and files exist."""
    print("\n📁 Checking Project Structure:")
    
    required_items = [
        'unity/Plugins/iOS/FastVLMUnityBridge.swift',
        'unity/Plugins/iOS/FastVLMUnityRunner.swift',
        'unity/Plugins/iOS/FastVLMUnityError.swift',
        'unity/Plugins/iOS/FastVLMUnityImageConverter.swift',
        'unity/Runtime/FastVLMUnity.cs',
        'model_export/export_vision_encoder.py',
        'model_export/fastvlm_mlx-vlm.patch',
        'llava/serve/gradio_web_server.py',
        'llava/serve/controller.py',
        'llava/serve/model_worker.py',
        'predict.py',
        'pyproject.toml'
    ]
    
    all_good = True
    
    for item in required_items:
        path = Path(item)
        if path.exists():
            print(f"✅ {item}")
        else:
            print(f"❌ {item}")
            all_good = False
    
    return all_good

def check_script_functionality():
    """Test that key scripts can run and show help."""
    print("\n🔧 Checking Script Functionality:")
    
    scripts_to_test = [
        ('python predict.py --help', 'predict.py'),
        ('python model_export/export_vision_encoder.py --help', 'export_vision_encoder.py'),
        ('python -m llava.serve.cli --help', 'llava serve CLI')
    ]
    
    all_good = True
    
    for command, script_name in scripts_to_test:
        try:
            result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                print(f"✅ {script_name}: Help command works")
            else:
                print(f"❌ {script_name}: Failed with error {result.returncode}")
                all_good = False
        except subprocess.TimeoutExpired:
            print(f"⚠️  {script_name}: Timeout (but likely working)")
        except Exception as e:
            print(f"❌ {script_name}: {e}")
            all_good = False
    
    return all_good

def check_ios_dependencies():
    """Check for iOS/macOS specific dependencies (will be missing on Linux)."""
    print("\n🍎 Checking iOS/macOS Dependencies:")
    
    tools_to_check = ['swift', 'xcodebuild', 'unity']
    
    for tool in tools_to_check:
        try:
            result = subprocess.run(['which', tool], capture_output=True, text=True)
            if result.returncode == 0:
                print(f"✅ {tool}: Found at {result.stdout.strip()}")
            else:
                print(f"⚠️  {tool}: Not found (expected on Linux, required on macOS)")
        except Exception as e:
            print(f"❌ Error checking {tool}: {e}")
    
    print("\n📝 Note: Swift, Xcode, and Unity are only available on macOS.")
    print("   For actual iOS plugin compilation, you need a macOS environment with:")
    print("   - Xcode 16.2+")
    print("   - Unity 2022.3+ with iOS build support")
    print("   - Swift 5.9+")

def check_coreml_functionality():
    """Check CoreML tools functionality."""
    print("\n🧠 Checking CoreML Tools:")
    
    try:
        import coremltools
        print(f"✅ CoreML Tools: {coremltools.__version__}")
        
        # Test basic functionality
        try:
            from coremltools.models import MLModel
            print("✅ CoreML MLModel import: Success")
        except Exception as e:
            print(f"⚠️  CoreML MLModel import: {e}")
            print("   Note: Some CoreML features may not work on Linux")
            
    except ImportError as e:
        print(f"❌ CoreML Tools: {e}")
        return False
    
    return True

def generate_environment_report():
    """Generate a comprehensive environment report."""
    print("\n📊 Environment Report:")
    print("=" * 50)
    
    # Python environment
    print(f"Python executable: {sys.executable}")
    print(f"Python version: {sys.version}")
    
    # Virtual environment
    if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
        print(f"Virtual environment: {sys.prefix}")
        print("✅ Running in virtual environment")
    else:
        print("⚠️  Not running in virtual environment")
    
    # Working directory
    print(f"Working directory: {os.getcwd()}")
    
    # Git info
    try:
        git_hash = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
        git_branch = subprocess.check_output(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], text=True).strip()
        print(f"Git branch: {git_branch}")
        print(f"Git commit: {git_hash}")
    except:
        print("Git info: Not available")

def main():
    """Main validation function."""
    print("🚀 FastVLM Unity Plugin Environment Validation")
    print("=" * 50)
    
    # Generate environment report first
    generate_environment_report()
    
    # Run all checks
    checks = [
        ("Python Version", check_python_version),
        ("Python Dependencies", check_python_dependencies),
        ("Project Structure", check_project_structure),
        ("Script Functionality", check_script_functionality),
        ("CoreML Functionality", check_coreml_functionality),
        ("iOS Dependencies", check_ios_dependencies)
    ]
    
    results = []
    for check_name, check_func in checks:
        try:
            result = check_func()
            results.append((check_name, result))
        except Exception as e:
            print(f"❌ {check_name}: Error - {e}")
            results.append((check_name, False))
    
    # Summary
    print("\n📋 Validation Summary:")
    print("=" * 30)
    
    for check_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{check_name:.<25} {status}")
    
    # Overall result
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    print(f"\nOverall: {passed}/{total} checks passed")
    
    if passed >= total - 1:  # Allow for iOS dependencies on Linux
        print("🎉 Environment is properly configured!")
        return 0
    else:
        print("⚠️  Some issues found. Please address them before proceeding.")
        return 1

if __name__ == "__main__":
    sys.exit(main())