"""Packages the Lambda backend into backend/lambda.zip.

Usage (from the project root):   python build.py

Dependencies are downloaded as Linux (manylinux) wheels for Python 3.12,
so the zip works on AWS Lambda even when you build it on Windows or macOS.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BACKEND = ROOT / "backend"
BUILD = BACKEND / "_build"
ZIP_BASE = BACKEND / "lambda"          # -> backend/lambda.zip

shutil.rmtree(BUILD, ignore_errors=True)
BUILD.mkdir(parents=True)

print("Installing dependencies for AWS Lambda (Linux, Python 3.12)...")
subprocess.check_call([
    sys.executable, "-m", "pip", "install",
    "-r", str(BACKEND / "requirements.txt"),
    "-t", str(BUILD),
    "--platform", "manylinux2014_x86_64",
    "--implementation", "cp",
    "--python-version", "3.12",
    "--only-binary=:all:",
    "--upgrade", "--quiet",
])

shutil.copy(BACKEND / "lambda_function.py", BUILD / "lambda_function.py")

zip_path = shutil.make_archive(str(ZIP_BASE), "zip", BUILD)
size_mb = Path(zip_path).stat().st_size / 1024 / 1024
print(f"Created {zip_path} ({size_mb:.1f} MB)")
