#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO="$ROOT/q6a_jit_demo"

REQUIRED=(
  "$DEMO/run_model"
  "$DEMO/lib/libLiteRt.so"
  "$DEMO/lib/libLiteRtDispatch_Qualcomm.so"
  "$DEMO/lib/libLiteRtCompilerPlugin_Qualcomm.so"
  "$DEMO/lib/libQnnSystem.so"
  "$DEMO/lib/libQnnHtp.so"
  "$DEMO/lib/libQnnHtpPrepare.so"
  "$DEMO/lib/libQnnHtpV68Stub.so"
  "$DEMO/lib/libQnnHtpV68Skel.so"
  "$DEMO/model/model.tflite"
)

MISSING=0

for f in "${REQUIRED[@]}"; do
  if [ ! -f "$f" ]; then
    MISSING=1
  fi
done

if [ "$MISSING" -ne 0 ]; then
  echo
  echo "LiteRT/QNN demo environment is not built."
  echo "Running automatic setup..."
  echo
  "$ROOT/setup_q6a.sh"
fi

for f in "${REQUIRED[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: required artifact is missing:"
    echo "  $f"
    false
  fi
done

export LD_LIBRARY_PATH="$DEMO/lib:${LD_LIBRARY_PATH:-}"
export ADSP_LIBRARY_PATH="$DEMO/lib"

mkdir -p "$DEMO/benchmark" "$DEMO/cache"

CPU_LOG="$DEMO/benchmark/cpu.log"
HTP_WARMUP_LOG="$DEMO/benchmark/htp_warmup.log"
HTP_LOG="$DEMO/benchmark/htp.log"

echo
echo "============================================================"
echo "        LiteRT Embedded Inference — Dragon Q6A"
echo "============================================================"
echo
echo "Model    : MobileNetV2 1.0 224 INT8"
echo "Platform : Qualcomm QCS6490"
echo "Backend  : Qualcomm QNN HTP"
echo "QAIRT    : 2.47.0.260601"
echo "Runs     : 20"
echo

echo "[1/3] CPU benchmark..."

"$DEMO/run_model" \
  --graph="$DEMO/model/model.tflite" \
  --accelerator=cpu \
  --iterations=20 \
  > "$CPU_LOG" 2>&1

grep -q "Model run completed" "$CPU_LOG" || {
  echo "ERROR: CPU benchmark failed."
  tail -40 "$CPU_LOG"
  false
}

echo "      done."

echo
echo "[2/3] HTP preparation..."

CACHE_FILE="$(
  find "$DEMO/cache" \
    -type f \
    -print -quit \
    2>/dev/null || true
)"

if [ -z "$CACHE_FILE" ]; then
  echo "      first HTP load: compiling and caching..."

  "$DEMO/run_model" \
    --graph="$DEMO/model/model.tflite" \
    --accelerator=npu \
    --dispatch_library_dir="$DEMO/lib" \
    --compiler_plugin_library_dir="$DEMO/lib" \
    --compiler_cache_dir="$DEMO/cache" \
    --iterations=1 \
    > "$HTP_WARMUP_LOG" 2>&1

  grep -q "Model run completed" "$HTP_WARMUP_LOG" || {
    echo "ERROR: HTP preparation failed."
    tail -80 "$HTP_WARMUP_LOG"
    false
  }

  echo "      cache created."
else
  echo "      cached HTP model found."
fi

echo
echo "[3/3] HTP benchmark..."

"$DEMO/run_model" \
  --graph="$DEMO/model/model.tflite" \
  --accelerator=npu \
  --dispatch_library_dir="$DEMO/lib" \
  --compiler_plugin_library_dir="$DEMO/lib" \
  --compiler_cache_dir="$DEMO/cache" \
  --iterations=20 \
  > "$HTP_LOG" 2>&1

grep -q "Model run completed" "$HTP_LOG" || {
  echo "ERROR: HTP benchmark failed."
  tail -80 "$HTP_LOG"
  false
}

CPU_FIRST=$(awk '/First run took/{print $(NF-1)}' "$CPU_LOG" | tail -1)
CPU_FAST=$(awk '/Fastest run took/{print $(NF-1)}' "$CPU_LOG" | tail -1)
CPU_SLOW=$(awk '/Slowest run took/{print $(NF-1)}' "$CPU_LOG" | tail -1)
CPU_AVG=$(awk '/All runs took average/{print $(NF-1)}' "$CPU_LOG" | tail -1)

HTP_FIRST=$(awk '/First run took/{print $(NF-1)}' "$HTP_LOG" | tail -1)
HTP_FAST=$(awk '/Fastest run took/{print $(NF-1)}' "$HTP_LOG" | tail -1)
HTP_SLOW=$(awk '/Slowest run took/{print $(NF-1)}' "$HTP_LOG" | tail -1)
HTP_AVG=$(awk '/All runs took average/{print $(NF-1)}' "$HTP_LOG" | tail -1)

SPEEDUP=$(awk \
  -v cpu="$CPU_AVG" \
  -v htp="$HTP_AVG" \
  'BEGIN {printf "%.2fx", cpu / htp}')

CACHE_HIT="NO"

if grep -q "Flatbuffer model initialized from cached model" "$HTP_LOG"; then
  CACHE_HIT="YES"
fi

echo
echo
echo "============================================================"
echo "                 BENCHMARK RESULT"
echo "============================================================"
echo
printf "%-24s %14s %14s\n" "Metric" "CPU" "Qualcomm HTP"
printf "%-24s %14s %14s\n" "------------------------" "--------------" "--------------"
printf "%-24s %11s us %11s us\n" "First run" "$CPU_FIRST" "$HTP_FIRST"
printf "%-24s %11s us %11s us\n" "Fastest run" "$CPU_FAST" "$HTP_FAST"
printf "%-24s %11s us %11s us\n" "Slowest run" "$CPU_SLOW" "$HTP_SLOW"
printf "%-24s %11s us %11s us\n" "Average (20 runs)" "$CPU_AVG" "$HTP_AVG"
echo
printf "%-24s %14s\n" "HTP speedup" "$SPEEDUP"
printf "%-24s %14s\n" "HTP cache hit" "$CACHE_HIT"
echo
echo "Model      : MobileNetV2 1.0 224 INT8"
echo "Platform   : Radxa Dragon Q6A / Qualcomm QCS6490"
echo "Backend    : Qualcomm QNN HTP"
echo "QAIRT      : 2.47.0.260601"
echo "Iterations : 20"
echo
echo "Detailed logs:"
echo "  $CPU_LOG"
echo "  $HTP_LOG"
echo
echo "============================================================"
