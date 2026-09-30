#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS="$ROOT/.deps"
LITERT_ROOT="$DEPS/LiteRT"
LITERT_SOURCE="$LITERT_ROOT/litert"
LITERT_BUILD="$LITERT_SOURCE/cmake_build"

QAIRT_VERSION="2.47.0.260601"
QAIRT_ROOT="$DEPS/qairt/$QAIRT_VERSION"
QAIRT_ZIP="$DEPS/qairt-${QAIRT_VERSION}.zip"
QAIRT_URL="https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/2.47.0.260601/v2.47.0.260601.zip"

FP16_ROOT="$DEPS/FP16"

LITERT_COMMIT="145c7523ff08d5e57ab5c582141775eea47da9c7"
LITERT_URL="https://github.com/google-ai-edge/LiteRT.git"

PATCH="$ROOT/patches/litert-q6a.patch"
DEMO="$ROOT/q6a_jit_demo"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1"
    false
  }
}

need_cmd git
need_cmd cmake
need_cmd wget
need_cmd unzip
need_cmd tar
need_cmd file

test -f "$PATCH"

mkdir -p "$DEPS" "$DEMO/lib" "$DEMO/model" "$DEMO/cache" "$DEMO/benchmark"

echo
echo "============================================================"
echo "1. LITERT SOURCE"
echo "============================================================"

if [ ! -d "$LITERT_ROOT/.git" ]; then
  git clone --filter=blob:none --no-checkout \
    "$LITERT_URL" \
    "$LITERT_ROOT"
fi

git -C "$LITERT_ROOT" fetch --quiet origin
git -C "$LITERT_ROOT" checkout --detach "$LITERT_COMMIT"

echo "LiteRT:"
git -C "$LITERT_ROOT" log -1 --format='%H %ad %s' --date=short

echo
echo "============================================================"
echo "2. APPLY Q6A BUILD PATCH"
echo "============================================================"

PATCH_STAMP="$LITERT_ROOT/.q6a_patch_applied"

if [ ! -f "$PATCH_STAMP" ]; then
  git -C "$LITERT_ROOT" apply --check "$PATCH"
  git -C "$LITERT_ROOT" apply "$PATCH"
  touch "$PATCH_STAMP"
  echo "Patch applied."
else
  echo "Patch already applied."
fi

echo
echo "============================================================"
echo "3. FP16"
echo "============================================================"

if [ ! -d "$FP16_ROOT/.git" ]; then
  git clone --depth 1 \
    https://github.com/Maratyszcza/FP16.git \
    "$FP16_ROOT"
fi

echo "FP16=$FP16_ROOT"

echo
echo "============================================================"
echo "4. QAIRT 2.47.0.260601"
echo "============================================================"

if [ ! -f "$QAIRT_ROOT/include/QNN/HTP/QnnHtpDeviceConfigShared.h" ]; then

  mkdir -p "$DEPS"

  if [ ! -f "$QAIRT_ZIP" ]; then
    wget -c -O "$QAIRT_ZIP" "$QAIRT_URL"
  fi

  QAIRT_TMP="$DEPS/qairt_extract"

  rm -rf "$QAIRT_TMP"
  mkdir -p "$QAIRT_TMP"

  unzip -q "$QAIRT_ZIP" -d "$QAIRT_TMP"

  SDK_ROOT="$(
    find "$QAIRT_TMP" \
      -type f \
      -path '*/include/QNN/HTP/QnnHtpDeviceConfigShared.h' \
      -print -quit \
    | sed 's#/include/QNN/HTP/QnnHtpDeviceConfigShared.h$##'
  )"

  test -n "$SDK_ROOT"

  rm -rf "$QAIRT_ROOT"
  mkdir -p "$QAIRT_ROOT"

  cp -a "$SDK_ROOT/include" "$QAIRT_ROOT/"
  cp -a "$SDK_ROOT/lib" "$QAIRT_ROOT/"

  if [ -d "$SDK_ROOT/bin" ]; then
    cp -a "$SDK_ROOT/bin" "$QAIRT_ROOT/"
  fi

  rm -rf "$QAIRT_TMP"
  rm -f "$QAIRT_ZIP"
fi

test -f \
  "$QAIRT_ROOT/include/QNN/HTP/QnnHtpDeviceConfigShared.h"

test -f \
  "$QAIRT_ROOT/lib/aarch64-oe-linux-gcc11.2/libQnnSystem.so"

test -f \
  "$QAIRT_ROOT/lib/aarch64-oe-linux-gcc11.2/libQnnHtp.so"

test -f \
  "$QAIRT_ROOT/lib/aarch64-oe-linux-gcc11.2/libQnnHtpPrepare.so"

test -f \
  "$QAIRT_ROOT/lib/aarch64-oe-linux-gcc11.2/libQnnHtpV68Stub.so"

test -f \
  "$QAIRT_ROOT/lib/hexagon-v68/unsigned/libQnnHtpV68Skel.so"

echo "QAIRT=$QAIRT_ROOT"

echo
echo "============================================================"
echo "5. CONFIGURE LITERT"
echo "============================================================"

cmake -S "$LITERT_SOURCE" -B "$LITERT_BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLITERT_ENABLE_GPU=OFF \
  -DLITERT_ENABLE_QUALCOMM=ON \
  -DLITERT_ENABLE_SAMSUNG=OFF \
  -DLITERT_ENABLE_NEUROPILOT=OFF \
  -DQAIRT_HEADERS_DIR="$QAIRT_ROOT/include/QNN" \
  -DFP16_SOURCE_DIR="$FP16_ROOT"

echo
echo "============================================================"
echo "6. BUILD REQUIRED TARGETS"
echo "============================================================"

cmake --build "$LITERT_BUILD" \
  --target \
    run_model \
    qnn_compiler_plugin \
    dispatch_api_qualcomm_so \
    litert_runtime_c_api_shared_lib \
  -j1

echo
echo "============================================================"
echo "7. COPY LITERT ARTIFACTS"
echo "============================================================"

cp -f \
  "$LITERT_BUILD/tools/run_model" \
  "$DEMO/run_model"

cp -f \
  "$LITERT_BUILD/c/libLiteRt.so" \
  "$DEMO/lib/"

cp -f \
  "$LITERT_BUILD/vendors/qualcomm/dispatch/libLiteRtDispatch_Qualcomm.so" \
  "$DEMO/lib/"

cp -f \
  "$LITERT_BUILD/vendors/qualcomm/compiler/libLiteRtCompilerPlugin_Qualcomm.so" \
  "$DEMO/lib/"

echo
echo "============================================================"
echo "8. COPY QAIRT RUNTIME"
echo "============================================================"

QAIRT_LIB="$QAIRT_ROOT/lib/aarch64-oe-linux-gcc11.2"

for f in \
  libQnnSystem.so \
  libQnnHtp.so \
  libQnnHtpPrepare.so \
  libQnnHtpV68Stub.so
do
  cp -f "$QAIRT_LIB/$f" "$DEMO/lib/"
done

cp -f \
  "$QAIRT_ROOT/lib/hexagon-v68/unsigned/libQnnHtpV68Skel.so" \
  "$DEMO/lib/"

for f in \
  libQnnIr.so \
  libQnnSaver.so
do
  if [ -f "$QAIRT_LIB/$f" ]; then
    cp -f "$QAIRT_LIB/$f" "$DEMO/lib/"
  fi
done

echo
echo "============================================================"
echo "9. MOBILE-NET V2 INT8 MODEL"
echo "============================================================"

MODEL_TGZ="$DEPS/mobilenet_v2_1.0_224_quant.tgz"
MODEL_URL="https://storage.googleapis.com/download.tensorflow.org/models/tflite_11_05_08/mobilenet_v2_1.0_224_quant.tgz"

if [ ! -f "$DEMO/model/model.tflite" ]; then
  if [ ! -f "$MODEL_TGZ" ]; then
    wget -c -O "$MODEL_TGZ" "$MODEL_URL"
  fi

  MODEL_TMP="$DEPS/mobilenet_extract"

  rm -rf "$MODEL_TMP"
  mkdir -p "$MODEL_TMP"

  tar -xzf "$MODEL_TGZ" -C "$MODEL_TMP"

  cp -f \
    "$MODEL_TMP/mobilenet_v2_1.0_224_quant.tflite" \
    "$DEMO/model/model.tflite"

  rm -rf "$MODEL_TMP"
  rm -f "$MODEL_TGZ"
fi

test -f "$DEMO/model/model.tflite"

echo
echo "============================================================"
echo "10. VERIFY FINAL DEMO"
echo "============================================================"

file \
  "$DEMO/run_model" \
  "$DEMO/lib/libLiteRt.so" \
  "$DEMO/lib/libLiteRtDispatch_Qualcomm.so" \
  "$DEMO/lib/libLiteRtCompilerPlugin_Qualcomm.so"

echo
echo "QAIRT:"
strings "$DEMO/lib/libQnnHtp.so" \
  | grep -E 'AISW_VERSION|2\.47\.0' \
  | head -3

echo
echo "============================================================"
echo "SETUP COMPLETE"
echo "============================================================"
echo
echo "Run:"
echo "  ./run_demo.sh"
echo
