#!/usr/bin/env python3
"""Extract MajdataView 5786452 CanvasAllPerfect, Enter curves and original SDF glyphs.
Usage: python import-all-perfect.py /path/to/MajdataView
Requires PyYAML and Pillow. No placeholder song data is copied.
"""
from pathlib import Path
import json, math, re, shutil, sys
import yaml
from PIL import Image

assets = Path(sys.argv[1]) / 'Assets'
dest = Path(__file__).resolve().parents[1] / 'Sources/MajdataMac/Resources/AllPerfect'
dest.mkdir(parents=True, exist_ok=True)

def docs(path):
    text = re.sub(r'^%.*\n', '', path.read_text(encoding='utf-8-sig'), flags=re.M)
    text = re.sub(r'^--- !u!\d+ &(-?\d+).*$', r'---\nfileID: \1', text, flags=re.M)
    return {d['fileID']: d for d in yaml.safe_load_all(text)}

scene = docs(assets / 'Scenes/SampleScene.unity')
root = next(d['GameObject'] for d in scene.values() if d.get('GameObject', {}).get('m_Name') == 'CanvasAllPerfect')
nodes = []
textures = {'bloom': 'apbloom', 'star1': 'StarWhite', 'star2': 'TouchEffparts_01', 'star3': 'StarWhite', 'star4': 'StarWhite'}
def visit(tid, parent=-1, path=''):
    t = scene[tid]['RectTransform']; g = scene[t['m_GameObject']['fileID']]['GameObject']
    name = g['m_Name']; path = path + '/' + name if path else name
    b = next((scene[c['component']['fileID']]['MonoBehaviour'] for c in g['m_Component']
              if 'm_Color' in scene[c['component']['fileID']].get('MonoBehaviour', {})), {})
    p = t['m_AnchoredPosition']; size = t['m_SizeDelta']; scale = t['m_LocalScale']
    index = len(nodes)
    nodes.append(dict(name=name, path=path, parent=parent, x=p['x'], y=p['y'], width=size['x'], height=size['y'],
                      stretch=t['m_AnchorMax']['x']-t['m_AnchorMin']['x'], sx=scale['x'], sy=scale['y'],
                      color=list(b.get('m_Color', dict(r=1,g=1,b=1,a=1)).values()), texture=textures.get(name)))
    for ref in t['m_Children']: visit(ref['fileID'], index, path)
rt = next(scene[c['component']['fileID']]['RectTransform'] for c in root['m_Component'] if 'RectTransform' in scene[c['component']['fileID']])
for ref in rt['m_Children']: visit(ref['fileID'])

clip = next(iter(docs(assets/'Animation/Enter.anim').values()))['AnimationClip']
curves = {}
for c in clip['m_EditorCurves']:
    curves[(c['path'] or '')+':'+c['attribute']] = [[k['time'], k['value'],
        float(k['inSlope']) if math.isfinite(float(k['inSlope'])) else None,
        float(k['outSlope']) if math.isfinite(float(k['outSlope'])) else None,
        k.get('weightedMode', 0), k.get('inWeight', 1/3), k.get('outWeight', 1/3)] for k in c['curve']['m_Curve']]

# Preserve the actual TMP font atlas/metrics, avoiding platform font substitutions.
font_docs = docs(assets/'Minimoon SDF.asset')
font = next(d['MonoBehaviour'] for d in font_docs.values() if 'MonoBehaviour' in d)
texture = next(d['Texture2D'] for d in font_docs.values() if 'Texture2D' in d)
assert texture['m_TextureFormat'] == 1
atlas = Image.frombytes('L', (texture['m_Width'], texture['m_Height']), bytes.fromhex(texture['_typelessdata']))
glyphs = {}
padding = font['m_AtlasPadding']
for c in font['m_CharacterTable']:
    character = chr(c['m_Unicode'])
    if character not in 'ALLPERFECT': continue
    g = next(g for g in font['m_GlyphTable'] if g['m_Index'] == c['m_GlyphIndex'])
    r = g['m_GlyphRect']; m = g['m_Metrics']; x, y = r['m_X'], r['m_Y']
    image = atlas.crop((x-padding, y-padding, x+r['m_Width']+padding, y+r['m_Height']+padding))
    image.transpose(Image.Transpose.FLIP_TOP_BOTTOM).convert('RGB').save(dest/(character+'.png'))
    glyphs[character] = dict(width=r['m_Width']+padding*2, height=r['m_Height']+padding*2,
        x=m['m_HorizontalBearingX']-padding, y=m['m_HorizontalBearingY']+padding, advance=m['m_HorizontalAdvance'])
material = docs(assets/'TextMesh Pro/Resources/Fonts & Materials/LiberationSans SDF.asset')[2180264]['Material']['m_SavedProperties']
floats = {k:v for entry in material['m_Floats'] for k,v in entry.items()}
colors = {k:list(v.values()) for entry in material['m_Colors'] for k,v in entry.items()}
manifest = dict(sourceCommit='5786452b45647eb15229ad601dab959288c0d88a', nodes=nodes,
    animation=dict(duration=clip['m_AnimationClipSettings']['m_StopTime'], curves=curves), glyphs=glyphs,
    fontSize=15, pointSize=font['m_FaceInfo']['m_PointSize'], lineHeight=font['m_FaceInfo']['m_LineHeight'],
    material=floats, colors=colors)
(dest/'outro.json').write_text(json.dumps(manifest, separators=(',', ':'), allow_nan=False)+'\n')
for name in set(textures.values()):
    folder = 'UIs' if name == 'apbloom' else 'Sprite'
    shutil.copyfile(assets/folder/(name+'.png'), dest/(name+'.png'))
print(f'Imported {len(nodes)} AP nodes, {len(curves)} curves, {len(glyphs)} SDF glyphs.')
