# SPDX-License-Identifier: GPL-3.0-or-later
"""Converts Beat This! final0 (MIT code and weights) to the Core ML model the app bundles: fp16, fixed 600 frames,
mlprogram for macOS 14. usage: make_model.py out.mlpackage   (needs coremltools in the venv; see bench/nn/README.md)"""
import os, sys
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Wrap, get_model
import coremltools as ct
from coremltools.converters.mil.frontend.torch import ops as _ops
from coremltools.converters.mil import Builder as mb

_orig_cast = _ops._cast
def _cast_fixed(context, node, dtype, dtype_name):
    # coremltools 9 + numpy 2: x.val may be a size-1 ndarray
    x = _ops._get_inputs(context, node, expected=1)[0]
    if x.can_be_folded_to_const() and isinstance(x.val, np.ndarray) and x.val.size == 1:
        context.add(mb.const(val=dtype(x.val.item()), name=node.name), node.name); return
    return _orig_cast(context, node, dtype, dtype_name)
_ops._cast = _cast_fixed

m = Wrap(get_model("final0")).eval()
x = torch.randn(1, 600, 128)
tr = torch.jit.trace(m, x)
ml = ct.convert(tr, inputs=[ct.TensorType(name="spect", shape=(1, 600, 128))],
                outputs=[ct.TensorType(name="beat"), ct.TensorType(name="downbeat")],
                convert_to="mlprogram", minimum_deployment_target=ct.target.macOS14,
                compute_precision=ct.precision.FLOAT16)
ml.save(sys.argv[1])
print("saved", sys.argv[1])
