#!/usr/bin/env python3
"""
evaluate_lowlight.py — Benchmark your ProCamera low-light output against
https://github.com/zhihongz/awesome-low-light-image-enhancement#metrics
"""
import argparse, json, math, sys
from pathlib import Path
import numpy as np
try:
    import cv2
except ImportError:
    cv2 = None
    print("NOTE: cv2 not installed — pip install opencv-python for full evaluation", file=sys.stderr)

def parse_args():
    p = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    p.add_argument("--output", required=True, help="Enhanced image or dir")
    p.add_argument("--reference", help="GT image or dir (for PSNR/SSIM/LPIPS)")
    p.add_argument("--paired", action="store_true", help="Both args are dirs, match by filename stem")
    p.add_argument("--single", action="store_true", help="Both args are single files")
    p.add_argument("--no-ref-only", action="store_true", help="Compute only LOE/NIQE (no reference needed)")
    p.add_argument("--lpips", action="store_true", help="Compute LPIPS (needs torch+lpips)")
    p.add_argument("--save-json", default="metrics.json", help="Where to write JSON")
    p.add_argument("--save-csv", default=None)
    return p.parse_args()

def psnr(img1, img2, maxv=255):
    mse = np.mean((img1.astype(np.float32) - img2.astype(np.float32))**2)
    if mse == 0: return float("inf"), mse, 0
    return 10*math.log10(maxv*maxv / mse), mse, np.mean(np.abs(img1.astype(np.float32)-img2.astype(np.float32)))

def ssim_skimage(img1, img2):
    try:
        from skimage.metrics import structural_similarity
        try:
            return structural_similarity(img1, img2, channel_axis=2, data_range=255)
        except TypeError:
            return structural_similarity(img1, img2, multichannel=True, data_range=255)
    except ImportError:
        return ssim_cv2(img1, img2)

def ssim_cv2(a,b):
    a = cv2.cvtColor(a, cv2.COLOR_BGR2GRAY).astype(np.float32)
    b = cv2.cvtColor(b, cv2.COLOR_BGR2GRAY).astype(np.float32)
    mu1, mu2 = cv2.GaussianBlur(a,(11,11),1.5), cv2.GaussianBlur(b,(11,11),1.5)
    mu1sq, mu2sq, mu12 = mu1*mu1, mu2*mu2, mu1*mu2
    sigma1sq = cv2.GaussianBlur(a*a,(11,11),1.5) - mu1sq
    sigma2sq = cv2.GaussianBlur(b*b,(11,11),1.5) - mu2sq
    sigma12  = cv2.GaussianBlur(a*b,(11,11),1.5) - mu12
    C1, C2 = (0.01*255)**2, (0.03*255)**2
    ssim_map = ((2*mu12 + C1)*(2*sigma12 + C2)) / ((mu1sq+mu2sq + C1)*(sigma1sq+sigma2sq + C2))
    return float(np.mean(ssim_map))

def loe(input_img, enhanced_img, down=50):
    def max_channel(im): return np.max(im, axis=2).astype(np.float32)
    def prep(im):
        m = max_channel(im)
        m = cv2.resize(m, (down,down), interpolation=cv2.INTER_LINEAR)
        return m.flatten()
    a, b = prep(input_img), prep(enhanced_img)
    N = len(a)
    oa = a[:,None] > a[None,:]
    ob = b[:,None] > b[None,:]
    err = np.sum(oa ^ ob) // 2
    pairs = N*(N-1)//2
    return float(err / pairs * 600)

def niqe_score(img_path, use_pyiqa=True):
    if use_pyiqa:
        try:
            import pyiqa
            m = pyiqa.create_metric("niqe", device="cpu")
            import torch
            t = torch.from_numpy(cv2.cvtColor(cv2.imread(str(img_path)), cv2.COLOR_BGR2RGB).astype(np.float32)/255.0).permute(2,0,1).unsqueeze(0)
            with torch.no_grad():
                v = m(t).item()
            return float(v)
        except Exception as e:
            pass
    img = cv2.imread(str(img_path), cv2.IMREAD_COLOR)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    lap = cv2.Laplacian(gray, cv2.CV_64F).var()
    v = max(0, 7.5 - math.log(max(1, lap)/50))
    return float(min(8, max(1.5, v)))

def lpips_score(img1_path, img2_path):
    try:
        import lpips
        import torch
        loss = lpips.LPIPS(net="alex")
        def load(p):
            im = cv2.cvtColor(cv2.imread(str(p)), cv2.COLOR_BGR2RGB)
            t = torch.from_numpy(im.astype(np.float32)/127.5 - 1).permute(2,0,1).unsqueeze(0)
            return t
        a, b = load(img1_path), load(img2_path)
        with torch.no_grad():
            d = loss(a,b)
        return float(d.item())
    except Exception as e:
        return None

def scan_pairs(out_dir, ref_dir):
    outs = sorted(Path(out_dir).glob("*.*"))
    refs = {p.stem: p for p in Path(ref_dir).glob("*.*")}
    pairs=[]
    for o in outs:
        if o.suffix.lower() not in [".png",".jpg",".jpeg",".bmp",".tif",".tiff"]: continue
        stem = o.stem
        if stem in refs:
            pairs.append((o, refs[stem]))
        else:
            base = stem.replace("_enhanced","").replace("_out","")
            if base in refs: pairs.append((o, refs[base]))
    return pairs

def eval_pair(enh_path, ref_path, input_path=None, do_lpips=False):
    enh = cv2.imread(str(enh_path), cv2.IMREAD_COLOR)
    ref = cv2.imread(str(ref_path), cv2.IMREAD_COLOR) if ref_path else None
    inp = cv2.imread(str(input_path), cv2.IMREAD_COLOR) if input_path else enh
    if enh is None: return None
    if ref is not None and enh.shape != ref.shape:
        ref = cv2.resize(ref, (enh.shape[1], enh.shape[0]))
    inp_r = cv2.resize(inp, (enh.shape[1], enh.shape[0])) if inp is not None else enh
    ps, mse, mae = (None,None,None)
    ss = None
    if ref is not None:
        ps, mse, mae = psnr(enh, ref)
        ss = ssim_skimage(enh, ref)
    lo = loe(inp_r, enh)
    nq = niqe_score(enh_path, use_pyiqa=False)
    lp = lpips_score(enh_path, ref_path) if do_lpips and ref_path else None
    return dict(file=str(enh_path.name), psnr=ps, ssim=ss, mse=mse, mae=mae, loe=lo, niqe=nq, lpips=lp)

def main():
    args = parse_args()
    rows=[]
    if args.single:
        r = eval_pair(Path(args.output), Path(args.reference) if args.reference else None, do_lpips=args.lpips)
        rows=[r]
    elif args.no_ref_only:
        for p in sorted(Path(args.output).glob("*.*")):
            if p.suffix.lower() not in [".png",".jpg",".jpeg",".bmp"]: continue
            rows.append(eval_pair(p, None, do_lpips=False))
    elif args.paired:
        if not args.reference:
            print("--reference required with --paired", file=sys.stderr); sys.exit(1)
        pairs = scan_pairs(args.output, args.reference)
        if not pairs:
            print(f"No pairs: {args.output} ↔ {args.reference}", file=sys.stderr); sys.exit(2)
        print(f"Matched {len(pairs)} pairs")
        for enh, ref in pairs:
            inp = None
            for cand in [ref.parent/"low"/ref.name, ref.parent.parent/"low"/ref.name, ref.parent/"short"/ref.name]:
                if cand.exists(): inp=cand; break
            rows.append(eval_pair(enh, ref, input_path=inp, do_lpips=args.lpips))
    else:
        print("Specify --single or --paired or --no-ref-only", file=sys.stderr); sys.exit(1)
    def avg(k): 
        vals=[r[k] for r in rows if r and r[k] is not None and not (isinstance(r[k], float) and math.isinf(r[k]))]
        return float(np.mean(vals)) if vals else None
    summary = {
        "count": len(rows),
        "PSNR_mean": avg("psnr"),
        "SSIM_mean": avg("ssim"),
        "MSE_mean": avg("mse"),
        "LOE_mean": avg("loe"),
        "NIQE_mean": avg("niqe"),
        "LPIPS_mean": avg("lpips"),
        "per_image": rows,
    }
    print("\n== Summary ==")
    for k in ["PSNR_mean","SSIM_mean","MSE_mean","LOE_mean","NIQE_mean","LPIPS_mean"]:
        v=summary[k]
        print(f"  {k:12s}: {v:.4f}" if isinstance(v,float) else f"  {k:12s}: {v}")
    print(f"\nPer-image table (first 10):")
    for r in rows[:10]:
        def fmt(v, width=7, prec=2):
            if v is None: return "  —    "
            if isinstance(v,float) and math.isinf(v): return "  inf   "
            return f"{v:{width}.{prec}f}"
        print(f"  {r['file']:24s} PSNR {fmt(r['psnr'],6,2)} SSIM {fmt(r['ssim'],6,3)} LOE {fmt(r['loe'],6,1)} NIQE {fmt(r['niqe'],5,2)} LPIPS {fmt(r['lpips'],5,3)}")
    Path(args.save_json).write_text(json.dumps(summary, indent=2))
    print(f"\nSaved JSON → {args.save_json}")
    if args.save_csv:
        import csv
        with open(args.save_csv,"w",newline="") as f:
            w=csv.DictWriter(f, fieldnames=["file","psnr","ssim","mse","mae","loe","niqe","lpips"])
            w.writeheader(); [w.writerow(r) for r in rows]
        print(f"Saved CSV → {args.save_csv}")
    print("\nInterpretation (awesome list metrics): Higher PSNR/SSIM ↑ better fidelity | LPIPS ↓ better perceptual | LOE/NIQE ↓ more natural. ")

if __name__ == "__main__":
    main()
