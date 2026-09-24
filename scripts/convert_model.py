#!/usr/bin/env python3
"""
convert_model.py — SOTA low-light → ANE-optimized CoreML (iOS Neural Engine)
"""
import argparse, pathlib
parser = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--model", choices=["retinexformer","hvi","liteie","snr","zero-dce"], required=True, help="SOTA name")
parser.add_argument("--weights", help="path .pth pretrained")
parser.add_argument("--out", required=True, help="output .mlpackage dir or .mlmodel path")
parser.add_argument("--quant", choices=["fp16","int8","int4","none"], default="fp16", help="ANE quantization")
parser.add_argument("--size", type=int, default=512, help="square input (must be %%16==0, 256 or 512 for ANE)")
parser.add_argument("--target", default="ios16", choices=["ios16","ios17","ios18"], help="minimum deployment (iOS16 = ML Program ANE)")
args = parser.parse_args()
assert args.size % 16 == 0, "ANE tiling requires HW %16==0 (use 256 or 512)"
out = pathlib.Path(args.out)
out.parent.mkdir(parents=True, exist_ok=True)
SNIPPET = """
import torch, coremltools as ct
weights = '{weights}'
size = {size}
{import_arch}
model.load_state_dict(torch.load(weights, map_location='cpu')['params'] if 'params' in torch.load(weights) else torch.load(weights))
model.eval()
example = torch.rand(1,3,size,size)
traced = torch.jit.trace(model, example)
ml = ct.convert(
    traced,
    inputs=[ct.ImageType(name='input', shape=example.shape, scale=1/255.0, bias=[0,0,0])],
    compute_units=ct.ComputeUnit.CPU_AND_NE,
    compute_precision=ct.precision.FLOAT16 if '{quant}'!='int8' and '{quant}'!='int4' else ct.precision.FLOAT32,
    minimum_deployment_target=ct.target.{targetUpper},
)
if '{quant}' == 'int8':
    from coremltools.optimize.coreml import linear_quantize_weights
    from coremltools.optimize.coreml import OptimizationConfig, OpLinearQuantizerConfig
    cfg = OptimizationConfig(global_config=OpLinearQuantizerConfig(mode='linear_symmetric', dtype='int8'))
    ml = linear_quantize_weights(ml, config=cfg)
elif '{quant}' == 'int4':
    from coremltools.optimize.coreml import palettize_weights as pw
    from coremltools.optimize.coreml import OptimizationConfig, OpPalettizerConfig
    cfg = OptimizationConfig(global_config=OpPalettizerConfig(mode='kmeans', nbits=4))
    ml = pw(ml, config=cfg)
ml.save('{out}')
print(f'Saved {{out}} — ANE ready.')
"""
IMPORTS = {
"retinexformer": "from basicsr.archs.retinexformer_arch import Retinexformer; model = Retinexformer()",
"hvi": "from hvi_cidnet import HVI_CIDNet; model = HVI_CIDNet()",
"liteie": "from liteie import LiteIE; model = LiteIE()",
"snr": "from snr_aware import SNRAwareEnhancer; model = SNRAwareEnhancer()",
"zero-dce": "from model import ZeroDCE; model = ZeroDCE()",
}
target_map = {"ios16":"iOS16","ios17":"iOS17","ios18":"iOS18"}
code = SNIPPET.format(weights=args.weights or "net_g.pth", size=args.size, import_arch=IMPORTS[args.model], quant=args.quant, out=str(out), targetUpper=target_map[args.target])
print(code)
print(f"\nDry-run template for {args.model} → {args.out} ({args.size}×{args.size}, {args.quant}, {args.target}, ML Program).")
