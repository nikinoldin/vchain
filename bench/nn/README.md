# Beat This! model scripts

The scripts behind the NN front end (`docs/beat-tracking.md`, "The NN front end"). They run in the bench venv
(`~/Music/vChainBench/.venv`, created by `bench/tools/annotate.sh`; add packages with
`VIRTUAL_ENV=~/Music/vChainBench/.venv uv pip install coremltools onnxruntime onnx`). **Converted models are not
committed**: final0 is 39 MB as fp16 Core ML, small0 4 MB. The weights are MIT (Beat This! README: "The code and the
published model weights are released under the MIT license").

**The app's model:** `make_model.sh` (→ `make_model.py`) converts Beat This! final0 to
`~/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage` (mlprogram, fp16, fixed 600 frames = 12 s,
outputs `beat` and `downbeat`). That is the model the app ships: `build.sh` and `scripts/release.sh` bundle it into
`Contents/Resources` (`VCHAIN_NN_MODEL` points them elsewhere); without it `build.sh` builds drum-only with a warning
and a release refuses to build. The Command Line Tools have no `coremlcompiler`, so the app compiles the `.mlpackage`
at first launch with `MLModel.compileModel(at:)` into `~/Library/Application Support/vChain/NN` (a few seconds, once)
and runs it on the Neural Engine on its own thread (`Sources/VChainNN`).

- `common.py`: loads a checkpoint and swaps `rotary_embedding_torch`'s cached rotary embedding for a stateless,
  bit-identical one, which tracing needs.
- `make_model.py`: the conversion `make_model.sh` runs.
- `coreml_conv.py`: `torch.jit.trace` and `coremltools.convert` to an mlprogram at fixed T (300 / 600 frames), fp16/fp32,
  and times each compute unit. Includes a patch for a coremltools 9 + numpy 2 bug in `_cast`. Flexible shapes convert
  but run 5-10x slower; use fixed T. Ask for `.cpuAndNeuralEngine` explicitly; `.all` picks the GPU.
- `onnx_export.py`: `torch.onnx.export(dynamo=True, opset 18)` with a dynamic T axis, verified against torch and
  timed in onnxruntime (an alternative runtime; the app uses Core ML).
- `rolling.py`: the causal rolling-window evaluation (the last W s every STEP s, a grid fit to the window's beats,
  a majority vote for the bar), scored against truth. Usage in its docstring.
- `rolling_dump.py`: precomputes what the rolling window reports for each bench file as `<id>.nn.tsv`, read by
  VChainBench's NN pipelines from `~/Music/vChainBench/nn-final0-w12/` by default (usage in its docstring).
- `logmel_fixture.py` + `fixtures/`: reference log-mel frames from the Python front end, checked against the C++ port
  (`unit_logmel.cpp`).
