#!/usr/bin/env bash
# Verify the Swift port against the live reference implementation.
#
# Renders the same set of panels twice — once with the real
# @ybouane/liquidglass package running in headless Chromium, once with
# LiquidGlassCore — and diffs the sampled pixels. The case list comes from the
# Swift side (`liquidglass-render --crosscheck-configs`), so both renderers are
# guaranteed to be given identical inputs.
#
# Requirements: node, chromium, python3.
#
# Usage:
#   scripts/verify-crosscheck.sh [work-dir]
#   TOLERANCE=0 scripts/verify-crosscheck.sh      # require an exact match

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-/tmp/liquidglass-crosscheck}"
TOLERANCE="${TOLERANCE:-2}"
export PATH="${SWIFT_BIN_DIR:-/workspace/swift-6.1.2-RELEASE-debian12/usr/bin}:$PATH"

echo "==> work dir: $WORK"
mkdir -p "$WORK"
cd "$WORK"

if [ ! -d node_modules/@ybouane/liquidglass ]; then
  echo "==> installing the reference package"
  npm init -y >/dev/null 2>&1
  # patch-package runs in the package's postinstall and is not needed here.
  npm install --ignore-scripts --silent @ybouane/liquidglass >/dev/null 2>&1
  npm install --ignore-scripts --silent esbuild >/dev/null 2>&1
fi

cat > bridge.ts <<'TS'
import { LiquidGlass } from '@ybouane/liquidglass';
(globalThis as any).LiquidGlass = LiquidGlass;
TS

echo "==> bundling the reference for the browser"
./node_modules/.bin/esbuild bridge.ts --bundle --format=iife --outfile=bundle.js \
  --alias:@ybouane/liquidglass=./node_modules/@ybouane/liquidglass/dist/index.js >/dev/null

echo "==> building LiquidGlassCore"
cd "$REPO_ROOT"
swift build --product liquidglass-render 2>&1 | grep -E 'error' && exit 1

.build/debug/liquidglass-render --crosscheck-configs > "$WORK/cases.json"
.build/debug/liquidglass-render --crosscheck > "$WORK/swift.json"

# The harness reads the case list from cases.json, so the reference renders
# exactly the frames and configs the Swift side rendered.
cat > "$WORK/ref.html" <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><style>
html,body{margin:0;background:#111}
#root{position:relative}
.panel{position:absolute}
</style></head><body>
<div id="root"></div>
<pre id="out"></pre>
<script>
// Headless Chromium throttles rAF to ~1 fps, so the library's render loop
// never advances. setTimeout is driven by virtual time, so use it instead.
window.requestAnimationFrame=function(cb){return setTimeout(function(){cb(performance.now())},16)};
window.cancelAnimationFrame=function(id){clearTimeout(id)};
</script>
<script src="bundle.js"></script>
<script>
(async()=>{
 const out=document.getElementById('out');
 try{
  const cases=await (await fetch('cases.json')).json();
  const [rw,rh]=cases.root;
  const results=[];
  for(const c of cases.cases){
   // One fresh root per case, so no neighbouring panel's shadow can leak into
   // the panel's padded crop.
   const root=document.createElement('div');
   root.id='root';root.style.width=rw+'px';root.style.height=rh+'px';
   document.body.insertBefore(root,out);

   const bg=document.createElement('canvas');
   bg.width=rw;bg.height=rh;
   bg.style.cssText='position:absolute;left:0;top:0;width:'+rw+'px;height:'+rh+'px';
   root.appendChild(bg);
   const ctx=bg.getContext('2d');
   const im=ctx.createImageData(rw,rh);
   for(let y=0;y<rh;y++)for(let x=0;x<rw;x++){
    const i=(y*rw+x)*4, check=(((x>>5)+(y>>5))%2===0)?40:0;
    im.data[i]=Math.round(255*x/(rw-1));
    im.data[i+1]=Math.round(255*y/(rh-1));
    im.data[i+2]=90+check; im.data[i+3]=255;
   }
   ctx.putImageData(im,0,0);

   const [fx,fy,fw,fh]=c.frame;
   const panel=document.createElement('div');
   panel.className='panel';
   panel.style.left=fx+'px';panel.style.top=fy+'px';
   panel.style.width=fw+'px';panel.style.height=fh+'px';
   panel.dataset.config=JSON.stringify(c.config);
   root.appendChild(panel);

   await LiquidGlass.init({root,glassElements:[panel]});
   await new Promise(r=>setTimeout(r,900));

   const canvas=panel.querySelector('canvas');
   if(!canvas){out.textContent='ERROR:no-canvas:'+c.name;return}
   const w=canvas.width,h=canvas.height;
   const c2=document.createElement('canvas');c2.width=w;c2.height=h;
   const cx=c2.getContext('2d');cx.drawImage(canvas,0,0);
   const data=cx.getImageData(0,0,w,h).data;

   const pts=[[0.5,0.5],[0.1,0.5],[0.9,0.5],[0.5,0.1],[0.5,0.9],
              [0.2,0.2],[0.8,0.8],[0.25,0.75]];
   for(let ty=0.02;ty<=0.3001;ty+=0.01) pts.push([0.5,Math.round(ty*1000)/1000]);

   const samples=[];
   for(const [sx,sy] of pts){
    const px=Math.round(sx*(w-1)),py=Math.round(sy*(h-1)),i=(py*w+px)*4;
    samples.push([Math.round(sx*100),Math.round(sy*100),data[i],data[i+1],data[i+2],data[i+3]]);
   }
   results.push({name:c.name,canvas:{w,h},samples});
   root.remove();
  }
  out.textContent=JSON.stringify({cases:results});
 }catch(e){out.textContent='ERROR:'+(e&&e.message?e.message:String(e))}
})();
</script></body></html>
HTML

echo "==> rendering with the reference library (headless Chromium)"
# A file:// page cannot always fetch a sibling JSON file, so serve the
# directory over loopback instead.
python3 -m http.server 8731 --directory "$WORK" >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT
sleep 1
timeout 900 chromium --headless=new --no-sandbox --enable-unsafe-swiftshader \
  --virtual-time-budget=180000 --dump-dom "http://127.0.0.1:8731/ref.html" > "$WORK/dom.html" 2>/dev/null
kill $SERVER_PID 2>/dev/null
trap - EXIT

python3 - "$WORK" "$TOLERANCE" <<'PY'
import html, json, re, sys
work, tolerance = sys.argv[1], int(sys.argv[2])
dom = open(f"{work}/dom.html").read()
m = re.search(r'<pre id="out">(.*?)</pre>', dom, re.S)
if not m:
    print("FAIL: reference page produced no output"); sys.exit(1)
raw = html.unescape(m.group(1))
if raw.startswith("ERROR"):
    print("FAIL: reference page errored:", raw); sys.exit(1)
ref = {c["name"]: c for c in json.loads(raw)["cases"]}
swift = {c["name"]: c for c in json.load(open(f"{work}/swift.json"))["cases"]}

total = 0
failed_cases = []
skipped = []
for name, s in swift.items():
    if not s.get("parity", True):
        skipped.append(name)
        continue
    if name not in ref:
        print(f"FAIL: reference did not render case '{name}'")
        failed_cases.append(name)
        continue
    r = ref[name]
    if r["canvas"] != s["canvas"]:
        print(f"  {name}: canvas size differs ref={r['canvas']} swift={s['canvas']}")
    n = min(len(r["samples"]), len(s["samples"]))
    worst, worst_row, fails = 0, None, 0
    for i in range(n):
        a, b = r["samples"][i], s["samples"][i]
        deltas = [abs(a[k] - b[k]) for k in range(2, 6)]
        d = max(deltas)
        total += 1
        if d > worst:
            worst, worst_row = d, (a, b, deltas)
        if d > tolerance:
            fails += 1
    print(f"  [{'PASS' if fails == 0 else 'FAIL'}] {name:<18} {n} samples, worst delta {worst}")
    if worst_row and worst > 0:
        print(f"           ref={worst_row[0][2:]} swift={worst_row[1][2:]} deltas={worst_row[2]}")
    if fails:
        failed_cases.append(name)

print()
if skipped:
    print(f"skipped {len(skipped)} deliberate-divergence case(s): {', '.join(skipped)}")
print(f"compared {total} samples across {len(swift) - len(skipped)} cases, tolerance {tolerance}")
if failed_cases:
    print(f"FAIL: {len(failed_cases)} case(s) exceeded tolerance: {', '.join(failed_cases)}")
    sys.exit(1)
print(f"PASS: every sample within {tolerance} of the reference implementation")
PY
