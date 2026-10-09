#!/usr/bin/env python3
"""Import MajdataView's original sprite geometry/animation, without a Unity runtime.

Usage: python import-unity-art.py /path/to/MajdataView
Requires PyYAML and Pillow. Source: MajdataView 5786452 (GPL-3.0).
JSON retains Unity coordinates, degrees, Hermite tangents and sprite pixels/unit.
"""
from pathlib import Path
import copy, json, math, re, shutil, sys
import yaml
from PIL import Image

assets = Path(sys.argv[1]) / 'Assets'
project = Path(__file__).resolve().parents[1]
dest = project / 'Sources/MajdataMac/Resources/Original'
dest.mkdir(parents=True, exist_ok=True)

def docs(path):
    text = re.sub(r'^%.*\n', '', path.read_text(encoding='utf-8-sig'), flags=re.M)
    text = re.sub(r'^--- !u!\d+ &(-?\d+).*$', r'---\nfileID: \1', text, flags=re.M)
    return {d['fileID']: d for d in yaml.safe_load_all(text)}

metas = {}
for path in assets.rglob('*.meta'):
    if path.suffixes[-2:-1] not in [['.png'], ['.prefab']]: continue
    meta = yaml.safe_load(path.read_text())
    metas[meta['guid']] = (path.with_suffix(''), meta)

textures = {}
def sprite(ref):
    if ref.get('guid') not in metas: return None
    path, meta = metas[ref['guid']]
    if path.suffix != '.png': return None
    name = path.stem
    importer = meta['TextureImporter']
    if name not in textures:
        shutil.copy2(path, dest / path.name)
        width, height = Image.open(path).size
        textures[name] = dict(width=width, height=height, ppu=importer.get('spritePixelsToUnits', 100),
                              pivot=importer.get('spritePivot', dict(x=.5, y=.5)))
    return name

def resolve(objects, tid):
    t = copy.deepcopy(objects[tid]['Transform'])
    if 'm_GameObject' not in t:
        instance = objects[t['m_PrefabInstance']['fileID']]['PrefabInstance']
        ref = t['m_CorrespondingSourceObject']
        source = docs(metas[ref['guid']][0])
        t, g, sr = resolve(source, ref['fileID'])
        for mod in instance['m_Modification']['m_Modifications']:
            if mod['target']['fileID'] != ref['fileID']: continue
            keys = mod['propertyPath'].split('.')
            if len(keys) == 2 and keys[0] in t:
                t[keys[0]][keys[1]] = float(mod['value'])
        return t, g, sr
    g = objects[t['m_GameObject']['fileID']]['GameObject']
    components = [objects.get(c['component']['fileID'], {}) for c in g['m_Component']]
    sr = next((c['SpriteRenderer'] for c in components if 'SpriteRenderer' in c), None)
    return t, g, sr

def node(objects, tid, parent=-1, path=''):
    t, g, sr = resolve(objects, tid)
    q = t['m_LocalRotation']; p = t['m_LocalPosition']; s = t['m_LocalScale']
    return dict(name=g['m_Name'], path=path, parent=parent, x=p['x'], y=p['y'], sx=s['x'], sy=s['y'],
                angle=math.degrees(2 * math.atan2(q['z'], q['w'])),
                sprite=sprite(sr['m_Sprite']) if sr else None,
                color=list(sr['m_Color'].values()) if sr else [1, 1, 1, 1],
                enabled=bool(sr['m_Enabled']) if sr else True,
                order=sr.get('m_SortingOrder', 0) if sr else 0)

def prefab(path):
    objects = docs(path)
    root = next(i for i, d in objects.items() if 'Transform' in d and d['Transform'].get('m_Father', {}).get('fileID') == 0)
    nodes = []
    def visit(tid, parent=-1, path=''):
        n = node(objects, tid, parent, path); index = len(nodes); nodes.append(n)
        for child in objects[tid]['Transform'].get('m_Children', []):
            cid = child['fileID']; _, g, _ = resolve(objects, cid)
            visit(cid, index, (path + '/' if path else '') + g['m_Name'])
    visit(root)
    return nodes

prefabs = {n: prefab(assets / 'Prefab' / (n + '.prefab')) for n in
           ['Tap_Effect', 'TouchEffect', 'JudgeEffect', 'Hold_Effect', 'Firework', 'Touch', 'TouchHold']}
slides = {}
for path in sorted((assets / 'SlidePrefab').glob('*.prefab')):
    name = path.stem.replace('Star_', '').replace('Slide_', '').replace('_', '').lower()
    if name.startswith('l') and not name.startswith('line'): name = 'L' + name[1:]
    nodes = prefab(path)
    slides[name] = nodes[1:]

animations = {}
for name in ['tapEffect', 'breakEffect', 'JudgePerfect', 'JudgeBreak', 'touch', 'fire',
             'StarOver', 'BreakStarOver', 'TouchJudge', 'HoldShine', 'SlideFadeIn', 'JudgeBreakShine']:
    clip = next(iter(docs(assets / 'Animation' / (name + '.anim')).values()))['AnimationClip']
    curves = {}
    for c in clip['m_EditorCurves']:
        keys = []
        for k in c['curve']['m_Curve']:
            # Infinite tangents encode stepped (boolean) curves, represented by null.
            keys.append([k['time'], k['value'], float(k['inSlope']) if math.isfinite(float(k['inSlope'])) else None,
                         float(k['outSlope']) if math.isfinite(float(k['outSlope'])) else None,
                         k.get('weightedMode', 0), k.get('inWeight', 1/3), k.get('outWeight', 1/3)])
        curves[(c['path'] or '') + ':' + c['attribute']] = keys
    animations[name] = dict(duration=clip['m_AnimationClipSettings']['m_StopTime'], curves=curves)

for guid, (path, _) in metas.items():
    if path.stem in ['Normal', 'Each', 'Break', 'EachLine1', 'EachLine2', 'EachLine3', 'EachLine4',
                     'Hold_End', 'Hold_Each_End', 'Hold_Break_End', 'Hex', 'Star', 'CircleMask', 'CircleMiss']:
        sprite(dict(guid=guid))

# The Hold particle system emits identical concentric rings: no motion or random size.
particle = next(d['ParticleSystem'] for d in docs(assets / 'Prefab/Hold_Effect.prefab').values() if 'ParticleSystem' in d)
size_keys = particle['SizeModule']['curve']['maxCurve']['m_Curve']
gradient = particle['ColorModule']['gradient']['maxGradient']
alpha_keys = [[gradient['atime'+str(i)] / 65535, gradient['key'+str(i)]['a']] for i in range(gradient['m_NumAlphaKeys'])]
hold_particles = dict(lifetime=particle['InitialModule']['startLifetime']['scalar'],
                      rate=particle['EmissionModule']['rateOverTime']['scalar'],
                      size=particle['SizeModule']['curve']['scalar'] * 1.2, alpha=alpha_keys)
animations['HoldParticleSize'] = dict(duration=1, curves={':size': [[k['time'],k['value'],k['inSlope'],k['outSlope'],0,1/3,1/3] for k in size_keys]})
# Core and renderer share the same complete child ordering, including the judge node.
core_paths = {name: [[n['x']/4.8,-n['y']/4.8] for n in nodes] for name,nodes in slides.items()}
(project / 'Sources/MajdataCore/Resources/slide-paths.json').write_text(json.dumps(core_paths, separators=(',',':')))

source = (assets / 'Scripts/JsonDataLoader.cs').read_text(encoding='utf-8-sig')
block = source.split('SLIDE_AREA_STEP_MAP =')[1].split('private static readonly')[0]
steps = {name: list(map(int, re.findall(r'\d+', values))) for name, values in
         re.findall(r'\{"([^"]+)", new List<int>\(\)\{([^}]+)\}', block)}
manifest = dict(sourceCommit='5786452b45647eb15229ad601dab959288c0d88a',
                holdParticles=hold_particles, textures=textures, prefabs=prefabs, slides=slides, animations=animations, areaSteps=steps)
(project / 'Sources/MajdataCore/Resources/slide-area-steps.json').write_text(json.dumps(steps, separators=(',', ':')))
(dest / 'art.json').write_text(json.dumps(manifest, separators=(',', ':'), allow_nan=False))
print(f'Imported {len(slides)} paths, {len(textures)} textures, {len(animations)} animations.')

# Sensor hit testing uses circles derived from RectTransform sizes, not wedge artwork.
scene = docs(assets / 'Scenes/SampleScene.unity')
root_id = next(d['fileID'] for d in scene.values() if d.get('GameObject', {}).get('m_Name') == 'Sensors')
root = next(d['RectTransform'] for d in scene.values() if d.get('RectTransform', {}).get('m_GameObject', {}).get('fileID') == root_id)
sensors = []
for child in root['m_Children']:
    t = scene[child['fileID']]['RectTransform']
    g = scene[t['m_GameObject']['fileID']]['GameObject']
    sensor = next(scene[c['component']['fileID']]['MonoBehaviour'] for c in g['m_Component'] if 'Type' in scene[c['component']['fileID']].get('MonoBehaviour', {}))
    # Root has no parent; center anchors and pivot are 0.5. Anchored position is local translation.
    assert t['m_AnchorMin'] == t['m_AnchorMax'] == {'x': .5, 'y': .5}
    sx = root['m_LocalScale']['x']; sy = root['m_LocalScale']['y']
    radius = max(t['m_SizeDelta']['x'] * abs(t['m_LocalScale']['x'] * sx), t['m_SizeDelta']['y'] * abs(t['m_LocalScale']['y'] * sy)) / 2
    sensors.append(dict(id=sensor['Type'], name=g['m_Name'], x=t['m_AnchoredPosition']['x'] * sx, y=-t['m_AnchoredPosition']['y'] * sy, radius=radius))
sensors.sort(key=lambda s: s['id'])
assert len(sensors) == 33 and [s['id'] for s in sensors] == list(range(33))
(project / 'Sources/MajdataCore/Resources/sensors.json').write_text(json.dumps(sensors, separators=(',', ':')))
print('Imported 33 sensor centers and radii from SampleScene.unity.')
