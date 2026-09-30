# LiteRT Embedded Inference

### Qualcomm QNN HTP inference on Radxa Dragon Q6A / Qualcomm QCS6490

A reproducible embedded AI inference demo showing how **Google LiteRT** can execute a quantized neural network on the **Qualcomm Hexagon HTP accelerator** through **QNN** on the **Radxa Dragon Q6A**.

The project is designed as a compact, reproducible example of **heterogeneous AI execution on an embedded Linux platform**.

---

## 🚀 What this project demonstrates

This project goes beyond a simple TensorFlow Lite inference benchmark.

It demonstrates the complete execution path:

```text
                    MobileNetV2 INT8
                           │
                           ▼
                      LiteRT Runtime
                           │
                           ▼
                Qualcomm Compiler Plugin
                           │
                           ▼
                          QNN
                           │
                           ▼
                    Qualcomm HTP
                           │
                           ▼
                       QCS6490
```

The demo covers:

- LiteRT model loading
- CPU execution
- Qualcomm accelerator selection
- LiteRT → QNN graph lowering
- Qualcomm HTP compilation
- QNN context-binary generation
- persistent compilation cache
- HTP graph execution
- CPU vs HTP latency measurement

The entire example is launched with **one command**.

---

# ⚡ Quick Start

Clone the repository on a **Radxa Dragon Q6A** and run:

```bash
git clone <repository-url>
cd LiteRT-Embedded-Inference
./run_demo.sh
```

That's it.

On a fresh system, `run_demo.sh` automatically invokes the environment setup when the required artifacts are not present.

The setup process:

```text
Fresh Q6A
   │
   ├── download LiteRT source
   ├── checkout pinned LiteRT revision
   ├── apply Q6A build patch
   ├── download QAIRT
   ├── download build dependencies
   ├── configure CMake
   ├── build LiteRT
   ├── build Qualcomm compiler plugin
   ├── build Qualcomm dispatch library
   ├── install required QNN runtime libraries
   ├── download MobileNetV2 INT8
   │
   ▼
run CPU benchmark
   │
   ▼
compile model for HTP
   │
   ▼
store HTP context in cache
   │
   ▼
run HTP benchmark
   │
   ▼
print final result
```

After the first successful setup, the same command can be used again:

```bash
./run_demo.sh
```

The existing HTP compilation cache is reused.

---

# 📊 Benchmark

Measured on a **Radxa Dragon Q6A / Qualcomm QCS6490** with **MobileNetV2 1.0 224 INT8**.

| Metric | CPU | Qualcomm HTP |
|---|---:|---:|
| First run | 33.399 ms | 3.284 ms |
| Fastest run | 31.880 ms | 1.391 ms |
| Slowest run | 33.399 ms | 3.284 ms |
| **Average — 20 runs** | **32.028 ms** | **1.580 ms** |

### Average latency improvement

```text
CPU   : 32.028 ms
HTP   :  1.580 ms

HTP speedup: 20.27×
```

The benchmark is based on a real execution on the QCS6490 HTP accelerator.

These figures are measurements from the specific test system and configuration used for this project. They should not be interpreted as a universal performance specification for every QCS6490 device.

---

# 🧠 HTP compilation and caching

The first HTP execution performs on-device graph compilation.

LiteRT invokes the Qualcomm compiler plugin, which lowers the model into a QNN graph and generates a Qualcomm context binary.

The resulting compiled context is stored in the local cache:

```text
q6a_jit_demo/cache/
```

Subsequent executions load the compiled model from the cache instead of recompiling the graph.

The measured benchmark therefore represents **inference using a previously compiled HTP model**.

The project also keeps the full execution logs:

```text
q6a_jit_demo/benchmark/cpu.log
q6a_jit_demo/benchmark/htp.log
```

This keeps the normal terminal output clean while preserving the complete low-level QNN trace for debugging and analysis.

---

# 🏗️ Software architecture

The runtime stack used by the demo is:

```text
┌───────────────────────────────────────────────┐
│                 Application                   │
│                  run_model                   │
└───────────────────────┬───────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────┐
│                    LiteRT                    │
│             Model + Runtime + API            │
└───────────────────────┬───────────────────────┘
                        │
             ┌──────────┴──────────┐
             │                     │
             ▼                     ▼
      CPU / XNNPACK        Qualcomm Compiler
                                   │
                                   ▼
                                  QNN
                                   │
                                   ▼
                                  HTP
                                   │
                                   ▼
                           Hexagon V68 DSP
```

This is the important architectural point of the project:

**the same LiteRT model can be routed through different execution backends.**

The benchmark compares the CPU execution path with the Qualcomm HTP execution path.

---

# 🔧 Platform

| Component        | Configuration            |
|------------------|--------------------------|
| Board            | Radxa Dragon Q6A         |
| SoC              | Qualcomm QCS6490         |
| CPU architecture | ARM64 / AArch64          |
| OS               | Ubuntu 24.04             |
| Accelerator      | Qualcomm Hexagon HTP     |
| HTP architecture | Hexagon V68              |
| AI runtime       | LiteRT                   |
| Qualcomm runtime | QNN                      |
| Qualcomm SDK     | QAIRT 2.47.0.260601      |
| Model            | MobileNetV2 1.0 224 INT8 |
| Benchmark        | 20 inference runs        |

---

# 📦 Runtime components

The final demo contains the LiteRT and Qualcomm runtime components required for execution:

```text
q6a_jit_demo/
├── run_model
├── model/
│   └── model.tflite
│
├── lib/
│   ├── libLiteRt.so
│   ├── libLiteRtDispatch_Qualcomm.so
│   ├── libLiteRtCompilerPlugin_Qualcomm.so
│   │
│   ├── libQnnSystem.so
│   ├── libQnnHtp.so
│   ├── libQnnHtpPrepare.so
│   ├── libQnnHtpV68Stub.so
│   ├── libQnnHtpV68Skel.so
│   ├── libQnnIr.so
│   └── libQnnSaver.so
│
├── cache/
└── benchmark/
```

The Hexagon-side HTP component is:

```text
libQnnHtpV68Skel.so
```

which corresponds to the QCS6490 / Hexagon V68 target used by this demo.

---

# 🛠️ Reproducible build environment

The repository does not contain the complete LiteRT source tree or Qualcomm SDK.

Instead, the environment is prepared automatically by:

```text
setup_q6a.sh
```

The script creates a local dependency area:

```text
.deps/
```

and downloads the required components there.

The important version alignment is:

```text
LiteRT commit : 145c7523ff08d5e57ab5c582141775eea47da9c7
QAIRT         : 2.47.0.260601
Target        : QCS6490 / Hexagon V68
```

This version alignment is important because the Qualcomm backend uses HTP/QNN APIs supplied by the selected QAIRT SDK.

---

# 🔨 What gets built

The setup script builds the LiteRT components required by the demo:

```text
run_model
qnn_compiler_plugin
dispatch_api_qualcomm_so
litert_runtime_c_api_shared_lib
```

The resulting binaries are then collected into:

```text
q6a_jit_demo/
```

No manual copying of LiteRT or QNN libraries is required.

---

# 📁 Repository layout

```text
LiteRT-Embedded-Inference/
│
├── README.md
├── setup_q6a.sh
├── run_demo.sh
│
├── patches/
│   └── litert-q6a.patch
│
├── q6a_jit_demo/
│   ├── run_model
│   │
│   ├── model/
│   │   └── model.tflite
│   │
│   ├── lib/
│   │   ├── LiteRT libraries
│   │   └── QNN / HTP libraries
│   │
│   ├── cache/
│   │   └── generated HTP context
│   │
│   └── benchmark/
│       ├── cpu.log
│       └── htp.log
│
└── .deps/
    └── generated build dependencies
```

`.deps/` is generated locally and should not be committed.

---

# ▶️ Running the benchmark

The normal user interface is deliberately reduced to one command:

```bash
./run_demo.sh
```

The script runs:

```text
CPU benchmark
      │
      ▼
HTP cache preparation
      │
      ▼
HTP benchmark
      │
      ▼
CPU vs HTP summary
```

The terminal displays only the final benchmark summary.

Detailed Qualcomm/QNN diagnostics remain available in:

```text
q6a_jit_demo/benchmark/
```

---

# 📈 Example output

A successful run produces a compact result similar to:

```text
============================================================
                 BENCHMARK RESULT
============================================================

Metric                              CPU   Qualcomm HTP
------------------------ -------------- --------------
First run                      33399 us        3284 us
Fastest run                    31880 us        1391 us
Slowest run                    33399 us        3284 us
Average (20 runs)              32028 us        1580 us

HTP speedup                      20.27x
HTP cache hit                       YES

Model      : MobileNetV2 1.0 224 INT8
Platform   : Radxa Dragon Q6A / Qualcomm QCS6490
Backend    : Qualcomm QNN HTP
QAIRT      : 2.47.0.260601
Iterations : 20
```

---

# 🎯 Why this project exists

The purpose of this project is not simply to demonstrate that a neural network can run on an embedded board.

It demonstrates the **system-level path from an AI model to a heterogeneous accelerator**:

```text
Model
  ↓
AI Runtime
  ↓
Compiler / Graph Lowering
  ↓
Accelerator API
  ↓
Device Runtime
  ↓
Dedicated AI Hardware
```

This makes the project useful for studying and demonstrating:

- embedded AI runtimes;
- heterogeneous CPU / accelerator execution;
- compiler-plugin architecture;
- graph lowering;
- QNN integration;
- accelerator dispatch;
- memory and tensor handling;
- compiled-model caching;
- inference latency;
- first-run versus steady-state execution.

---

# 🧩 Engineering perspective

The project is intentionally built from the perspective of an **embedded systems / Linux engineer**.

The interesting part is not only the neural network itself, but the software infrastructure around it:

```text
             Embedded AI System
                    │
      ┌─────────────┼─────────────┐
      │             │             │
      ▼             ▼             ▼
    Linux         LiteRT         QNN
      │             │             │
      └─────────────┼─────────────┘
                    │
                    ▼
                  HTP
```

The demo therefore provides a practical example of how an embedded operating system and runtime coordinate CPU-side software with a dedicated accelerator.

---

# ⚠️ Scope and limitations

This repository is specifically targeted at:

```text
Radxa Dragon Q6A
Qualcomm QCS6490
Linux / Ubuntu
Hexagon V68
Qualcomm QNN HTP
```

The benchmark uses one quantized MobileNetV2 model and is intended primarily as a reproducible engineering demonstration.

A different model may require different QNN operator support, tensor types, quantization parameters, or compiler transformations.

The benchmark numbers depend on the exact hardware configuration, software versions, model, and runtime state.

---

# 📚 LiteRT Qualcomm documentation

The relevant Qualcomm documentation is available inside the LiteRT source tree used by the project:

```text
litert/vendors/qualcomm/doc/HTP_INSTRUCTIONS.md
litert/vendors/qualcomm/doc/QAIRT_SDK.md
litert/vendors/qualcomm/doc/LITERT_QNN_NATIVE_RUN.md
```

These documents describe the Qualcomm backend, QAIRT integration, and HTP execution flow.

---

# ✅ Result

This project provides a complete, reproducible example of:

```text
                 LiteRT
                    │
                    ▼
          Qualcomm Compiler Plugin
                    │
                    ▼
                   QNN
                    │
                    ▼
                  HTP
                    │
                    ▼
              Qualcomm QCS6490
```

with a measured result on the target device of approximately:

```text
                    32.0 ms
CPU  ──────────────────────────────────

HTP  ── 1.58 ms

             ≈ 20.27× lower
             average inference latency
```

The entire experiment can be reproduced from a clean checkout with:

```bash
./run_demo.sh
```
