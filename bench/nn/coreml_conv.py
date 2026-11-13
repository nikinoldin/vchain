# SPDX-License-Identifier: GPL-3.0-or-later
import sys, os, torch, numpy as np, traceback, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
import coremltools as ct
from coremltools.converters.mil.frontend.torch import ops as _ops
from coremltools.converters.mil import Builder as mb
_orig_cast = _ops._cast
def _cast_fixed(context, node, dtype, dtype_name):
    # numpy-2 fix: x.val may be a size-1 ndarray -> dtype(arr) raises
    x = _ops._get_inputs(context, node, expected=1)[0]
    if x.can_be_folded_to_const() and isinstance(x.val, np.ndarray) and x.val.size == 1:
        context.add(mb.const(val=dtype(x.val.item()), name=node.name), node.name); return
    return _orig_cast(context, node, dtype, dtype_name)
_ops._cast = _cast_fixed
out = os.path.dirname(os.path.abspath(__file__))
names = sys.argv[1:] or ["final0", "small0"]
def du(p): return subprocess.check_output(["du","-sk",p]).split()[0].decode()
for name in names:
    m = Wrap(get_model(name)).eval()
    for T in [300, 600]:
        x = torch.randn(1, T, 128)
        with torch.inference_mode(): rb, rd = m(x)
        tr = torch.jit.trace(m, x)
        for prec in ["fp16", "fp32"]:
            path = f"{out}/{name}_T{T}_{prec}.mlpackage"
            try:
                ml = ct.convert(tr, inputs=[ct.TensorType(name="spect", shape=(1, T, 128))],
                                outputs=[ct.TensorType(name="beat"), ct.TensorType(name="downbeat")],
                                convert_to="mlprogram", minimum_deployment_target=ct.target.macOS14,
                                compute_precision=ct.precision.FLOAT16 if prec=="fp16" else ct.precision.FLOAT32)
                ml.save(path)
            except Exception:
                traceback.print_exc(limit=-6); print(name, T, prec, "CONVERT FAILED"); continue
            print(f"{name} T={T} {prec} package {int(du(path))/1024:.1f} MB", flush=True)
            for cu in ["CPU_ONLY", "CPU_AND_GPU", "CPU_AND_NE", "ALL"]:
                mm = ct.models.MLModel(path, compute_units=getattr(ct.ComputeUnit, cu))
                inp = {"spect": x.numpy()}
                o = mm.predict(inp)
                d = max(np.abs(o["beat"]-rb.numpy()).max(), np.abs(o["downbeat"]-rd.numpy()).max())
                ms = bench(lambda: mm.predict(inp))
                print(f"  {cu:12s} {ms:7.1f} ms  maxdiff={d:.3f}", flush=True)
