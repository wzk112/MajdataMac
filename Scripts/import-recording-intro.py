#!/usr/bin/env python3
"""Extract CanvasSongDetail and its animation from MajdataView 5786452 (GPL-3.0).
Usage: python import-recording-intro.py /path/to/MajdataView
Requires PyYAML. No chart media or scene placeholder text is imported.
"""
from pathlib import Path
import json, math, re, shutil, sys
import yaml

assets = Path(sys.argv[1]) / 'Assets'
dest = Path(__file__).resolve().parents[1] / 'Sources/MajdataMac/Resources/RecordingIntro'
dest.mkdir(parents=True, exist_ok=True)

def docs(path):
    text = re.sub(r'^%.*\n', '', path.read_text(encoding='utf-8-sig'), flags=re.M)
    text = re.sub(r'^--- !u!\d+ &(-?\d+).*$', r'---\nfileID: \1', text, flags=re.M)
    return {d['fileID']: d for d in yaml.safe_load_all(text)}

scene = docs(assets / 'Scenes/SampleScene.unity')
nodes = []
root = next(d['GameObject'] for d in scene.values() if d.get('GameObject', {}).get('m_Name') == 'CanvasSongDetail')
textures = {'BGColor': 'color', 'SongDetail': 'JacketInfo', 'Jacket': 'bg_dummy', **{f'C{i}': '1080Circle_Shaped' for i in range(1, 5)}}
fields = {'LevelText': 'level', 'DifficultyText': 'difficulty', 'TitleText': 'title', 'ArtistText': 'artist', 'DesText': 'designer', 'Text (2)': 'LV.', 'Text (6)': 'NOTE DESIGN'}

def node(g, parent=-1, path='', parent_size=(108,108)):
    cs = [scene[c['component']['fileID']] for c in g['m_Component']]
    t = next((c['RectTransform'] for c in cs if 'RectTransform' in c), None)
    if t is None: return
    name = g['m_Name']; path = path + '/' + name if path else name
    size = t['m_SizeDelta']; anchor = t['m_AnchorMin']; pos = t['m_AnchoredPosition']
    n = dict(name=name, path=path, parent=parent, x=pos['x']+(anchor['x']-.5)*parent_size[0],
             y=pos['y']+(anchor['y']-.5)*parent_size[1], width=size['x'], height=size['y'],
             sx=t['m_LocalScale']['x'], sy=t['m_LocalScale']['y'], color=[1,1,1,1],
             texture=textures.get(name), field=fields.get(name), fontSize=0, alignment=4,
             rotate=0, wx=0, wy=0, shadow=False)
    for c in cs:
        b = c.get('MonoBehaviour', {})
        if 'm_Color' in b: n['color'] = list(b['m_Color'].values())
        if 'm_FontData' in b:
            f=b['m_FontData']; n['fontSize']=min(f['m_MaxSize'], size['y']) if f['m_BestFit'] else f['m_FontSize']; n['alignment']=f['m_Alignment']
        if 'rotate' in b:
            for k in ['rotate','wx','wy']: n[k]=b[k]
        if 'm_EffectDistance' in b: n['shadow']=True
    index=len(nodes); nodes.append(n)
    for child in t['m_Children']:
        ct=scene[child['fileID']].get('RectTransform')
        if ct: node(scene[ct['m_GameObject']['fileID']]['GameObject'], index, path, (size['x'],size['y']))

rt=next(scene[c['component']['fileID']]['RectTransform'] for c in root['m_Component'] if 'RectTransform' in scene[c['component']['fileID']])
for ref in rt['m_Children']:
    t=scene[ref['fileID']].get('RectTransform')
    if t: node(scene[t['m_GameObject']['fileID']]['GameObject'])
animations={}
for name in ['Entry','Showing','Exit']:
    clip=next(iter(docs(assets/'Animation'/f'{name}.anim').values()))['AnimationClip']
    curves={}
    for c in clip['m_EditorCurves']:
        curves[(c['path'] or '')+':'+c['attribute']]=[[k['time'],k['value'],
            float(k['inSlope']) if math.isfinite(float(k['inSlope'])) else None,
            float(k['outSlope']) if math.isfinite(float(k['outSlope'])) else None,
            k.get('weightedMode',0),k.get('inWeight',1/3),k.get('outWeight',1/3)] for k in c['curve']['m_Curve']]
    animations[name]=dict(duration=clip['m_AnimationClipSettings']['m_StopTime'],curves=curves)
colors=next(d['MonoBehaviour']['diffColors'] for d in scene.values() if 'diffColors' in d.get('MonoBehaviour',{}))
(dest/'intro.json').write_text(json.dumps(dict(sourceCommit='5786452b45647eb15229ad601dab959288c0d88a',nodes=nodes,animations=animations,colors=[list(c.values()) for c in colors]),separators=(',',':')))
for name in set(textures.values()):
    ext='.jpg' if name=='bg_dummy' else '.png'
    shutil.copy2(assets/'UIs'/(name+ext),dest/(name+ext))
shutil.copy2(assets/'Minimoon.ttf',dest/'Minimoon.ttf')
print(f'Imported {len(nodes)} nodes, {len(animations)} clips into {dest}')
