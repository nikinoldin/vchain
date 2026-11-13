# SPDX-License-Identifier: GPL-3.0-or-later
import sys, os, torch, numpy as np, traceback
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
import onnxruntime as ort
out = os.path.dirname(os.path.abspath(__file__))
for name in ["final0", "small0"]:
    m = Wrap(get_model(name)).eval()
    x = torch.randn(1, 600, 128)
    path = f"{out}/{name}.onnx"
    try:
        T = torch.export.Dim("T", min=16, max=4096)
        prog = torch.onnx.export(m, (x,), path, dynamo=True, input_names=["spect"], output_names=["beat","downbeat"],
                                 dynamic_shapes={"x": {1: T}}, opset_version=18, external_data=False)
        print(name, "dynamo export ok (dynamic T)")
    except Exception as e:
        traceback.print_exc(limit=3)
        print(name, "dynamo dynamic failed; trying legacy fixed")
        torch.onnx.export(m, (x,), path, dynamo=False, input_names=["spect"], output_names=["beat","downbeat"], opset_version=17,
                          dynamic_axes={"spect": {1: "T"}})
    print(" size MB", os.path.getsize(path)/1e6)
    import onnx; mp = onnx.load(path); print(" opset", [ (o.domain, o.version) for o in mp.opset_import], "ops", sorted({n.op_type for n in mp.graph.node}))
    for thr in [1, 4]:
        so = ort.SessionOptions(); so.intra_op_num_threads = thr; so.inter_op_num_threads = 1
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        s = ort.InferenceSession(path, so, providers=["CPUExecutionProvider"])
        for T in [300, 600, 1500]:
            xi = torch.randn(1, T, 128)
            with torch.inference_mode(): rb, rd = m(xi)
            ob, od = s.run(None, {s.get_inputs()[0].name: xi.numpy()})
            d = max(np.abs(ob - rb.numpy()).max(), np.abs(od - rd.numpy()).max())
            ms = bench(lambda: s.run(None, {s.get_inputs()[0].name: xi.numpy()}))
            print(f" ort cpu threads={thr} T={T}: {ms:.1f} ms  maxdiff={d:.2e}", flush=True)
