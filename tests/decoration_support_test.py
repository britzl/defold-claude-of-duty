"""Geometry attachment regression checks; run with python3 tests/decoration_support_test.py.

Requires the same Lua interpreter as the world tests. --probes PATH also exports
short rays for checking these attachment points against native Bullet geometry.
"""
import argparse
import collections
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
AXES = ('x', 'y', 'z')
SIZES = ('w', 'h', 'd')


def load_shapes():
    source = r'''
package.path='./?.lua;'..package.path
local layout=require 'game.world.layout'
local co=coroutine.create(function() require('game.world.recipes').generate(layout,true,layout.seed) end)
local rows={}
while coroutine.status(co)~='dead' do
    local ok,s=coroutine.resume(co);assert(ok,s)
    if s then
        local fields={}
        for _,key in ipairs({'id','kind','material','surface','x','y','z','w','h','d','rotation_x','rotation_y','rotation_z'}) do
            if s[key]~=nil then
                fields[#fields+1]=string.format('%q:',key)..(type(s[key])=='number'
                    and string.format('%.12g',s[key]) or string.format('%q',s[key]))
            end
        end
        rows[#rows+1]='{'..table.concat(fields,',')..'}'
    end
end
print('['..table.concat(rows,',\n')..']')
'''
    return json.loads(subprocess.check_output(['lua', '-'], input=source, text=True, cwd=ROOT))


def point(shape, local=(0, 0, 0)):
    x, y, z = local
    for axis in AXES:
        c, s = math.cos(shape.get('rotation_'+axis, 0)), math.sin(shape.get('rotation_'+axis, 0))
        if axis == 'x':
            y, z = y*c-z*s, y*s+z*c
        elif axis == 'y':
            x, z = x*c+z*s, -x*s+z*c
        else:
            x, y = x*c-y*s, x*s+y*c
    return (x+shape['x'], y+shape['y'], z+shape['z'])


def corners(shape):
    return [point(shape, (i*shape['w'], j*shape['h'], k*shape['d']))
            for i in (-.5, .5) for j in (-.5, .5) for k in (-.5, .5)]


def bounds(shape):
    vertices = corners(shape)
    return tuple(min(v[a] for v in vertices) for a in range(3)) + tuple(max(v[a] for v in vertices) for a in range(3))


def disconnected(shapes):
    # Conservative broad-phase check: disconnected bounds prove a defect;
    # connected bounds still need the targeted attachment probes below.
    boxes = [bounds(s) for s in shapes]
    parent = list(range(len(shapes)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    active = []
    for i in sorted(range(len(shapes)), key=lambda n: boxes[n][0]):
        a = boxes[i]
        active = [j for j in active if boxes[j][3]+.01 >= a[0]]
        for j in active:
            b = boxes[j]
            if all(a[k] <= b[k+3]+.01 and b[k] <= a[k+3]+.01 for k in (1, 2)):
                parent[root(i)] = root(j)
        active.append(i)
    groups = collections.defaultdict(list)
    for i, shape in enumerate(shapes):
        groups[root(i)].append(shape)
    return [g for g in groups.values() if not any(s.get('surface') for s in g)]


def ray_box(start, end, shape):
    lo, hi = 0, 1
    for i, axis in enumerate(AXES):
        lower, upper = shape[axis]-shape[SIZES[i]]/2, shape[axis]+shape[SIZES[i]]/2
        delta = end[i]-start[i]
        if abs(delta) < 1e-10:
            if not lower-1e-8 <= start[i] <= upper+1e-8:
                return None
        else:
            a, b = sorted(((lower-start[i])/delta, (upper-start[i])/delta))
            lo, hi = max(lo, a), min(hi, b)
            if lo > hi+1e-8:
                return None
    return lo


def attachment_probes(shapes):
    by_id = {s['id']: s for s in shapes}
    solids = [s for s in shapes if s.get('surface')]
    probes = []

    def probe(label, start, end, prefix):
        hits = [(t, s) for s in solids if s['id'].startswith(prefix)
                and (t := ray_box(start, end, s)) is not None]
        assert hits, 'No structural backing: '+label
        t, shape = min(hits, key=lambda h: h[0])
        assert t > 1e-6, 'Decoration buried inside a structural solid: '+label
        # Coincident structural faces (for example a ruin slab and its lower
        # mass) may be reported in either order by Bullet's broad phase.
        length = math.dist(start, end)
        equivalent = [s['id'] for s in solids if (other := ray_box(start, end, s)) is not None
                      and abs(other-t)*length < .006]
        probes.append({'label': label, 'from': dict(zip(AXES, start)), 'to': dict(zip(AXES, end)),
                       'expected_id': shape['id'], 'expected_ids': equivalent,
                       'expected_point': [a+(b-a)*t for a, b in zip(start, end)]})

    for s in shapes:
        name = s['id']
        building = name.split('/')[0]+'/'
        if '/pipe/mount/' in name or ('/anchor/' in name and not name.endswith(('/arm', '/brace'))):
            # Find the wall immediately behind the fixing, in any orientation.
            start = point(s)
            candidates = []
            for axis in range(3):
                for side in (-1, 1):
                    end = list(start)
                    end[axis] += side*.12
                    for wall in solids:
                        if wall['surface'] == 'plaster' and (t := ray_box(start, end, wall)) is not None:
                            if t > .01:
                                candidates.append((t, end, wall))
            assert candidates, 'Floating fixing: '+name
            _, end, wall = min(candidates, key=lambda c: c[0])
            probe(name, start, end, wall['id'])
        elif '/window/' in name and name.endswith('/shutter'):
            backing = by_id[name.removesuffix('/shutter')]
            a, b = bounds(s), bounds(backing)
            assert all(a[i] <= b[i+3]+1e-8 and b[i] <= a[i+3]+1e-8 for i in range(3)), 'Floating shutter: '+name
            probe(name, point(s), point(backing), backing['id'])
        elif name.endswith('/roof/sheet'):
            low = min(v[1] for v in corners(s))
            cap = by_id[building+'coping']
            assert abs(low-(cap['y']+cap['h']/2)) < 1e-7, 'Sheet misses visible roof cap: '+name
            for i, v in enumerate(corners(s)):
                if abs(v[1]-low) < 1e-8:
                    # The decorative cap is above the native roof collider.
                    probe(name+'/'+str(i), (v[0], v[1]+.04, v[2]),
                          (v[0], cap['y']-cap['h']/2-.04, v[2]), building)
        elif '/balcony/' in name and '/bracket/' in name:
            a = point(s, (0, -s['h']/2, 0))
            hits = [wall for wall in solids if wall['id'].startswith(building) and ray_box(a, a, wall) is not None]
            assert hits, 'Balcony bracket has no wall attachment: '+name
            wall = hits[0]
            # The exterior-facing endpoint sits slightly inside its wall.
            side = 1 if a[0] > wall['x'] else -1
            probe(name, (a[0]+side*.12, a[1], a[2]), (a[0]-side*.04, a[1], a[2]), wall['id'])
        elif '/ruin/rebar/' in name:
            a = point(s, (0, -s['h']/2, 0))
            probe(name, (a[0], a[1]+.02, a[2]), (a[0], a[1]-.02, a[2]), building+'ruin/slab/back')
        elif '/ruin/break/' in name:
            side = int(name.split('/')[-1])
            a = (s['x'], s['y']-s['h']/2+.1, s['z'])
            probe(name, (a[0], a[1], a[2]+side*(s['d']/2+.02)), a, building+'ruin/wall/')
        elif name.startswith('gate/') and ('/merlon/' in name or '/bags/1/' in name):
            x, y, z = s['x'], s['y']-s['h']/2, s['z']
            probe(name, (x, y+.06, z), (x, y-.06, z), 'gate/')

    # Every suspended span must terminate in a fixing at both ends.
    for family in ('cable', 'laundry'):
        for index in range(1, 7):
            prefix = f'dressing/{family}/{index}'
            for edge, segment, sign in (('start', 1, -1), ('end', 12, 1)):
                beam = by_id[f'{prefix}/{segment}']
                a = point(beam, (0, sign*beam['h']/2, 0))
                anchor = by_id[f'{prefix}/anchor/{edge}']
                arm = by_id.get(anchor['id']+'/arm')
                if arm:
                    root = point(arm, (0, -arm['h']/2, 0))
                    tip = point(arm, (0, arm['h']/2, 0))
                    assert ray_box(root, root, anchor) is not None, 'Laundry arm misses its wall fixing: '+anchor['id']
                    assert math.dist(a, tip) < 1e-8, 'Laundry misses its support arm: '+anchor['id']
                else:
                    assert ray_box(a, a, anchor) is not None, 'Cable misses its fixing: '+prefix+'/'+edge
    return probes


def laundry_clearance(shapes):
    architecture = [(s, bounds(s)) for s in shapes
                    if s['id'].split('/')[0].startswith(('W', 'E', 'B'))]
    cloths = [s for s in shapes if s['id'].startswith('dressing/laundry/') and '/cloth/' in s['id']]
    for cloth in cloths:
        a = bounds(cloth)
        for structure, b in architecture:
            assert not all(a[i] < b[i+3]-1e-6 and b[i] < a[i+3]-1e-6 for i in range(3)), (
                'Laundry intersects architecture: '+cloth['id']+' / '+structure['id'])

    # The reported E2 span belongs in the masonry band between window rows.
    # A stand-off alone would stop clipping but still drape cloth over the opening.
    window = next(s for s in shapes if s['id'] == 'E2/window/1/-3.25/lintel')
    for cloth in cloths:
        if cloth['id'].startswith('dressing/laundry/4/'):
            assert bounds(cloth)[1] > bounds(window)[4]+.1, 'Laundry hangs across the E2 window'
    return len(cloths)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--probes', type=Path)
    args = parser.parse_args()
    shapes = load_shapes()
    loose = disconnected(shapes)
    assert not loose, f'{len(loose)} disconnected decoration groups: '+', '.join(g[0]['id'] for g in loose[:12])
    print(f'PASS no disconnected decoration groups among {len(shapes)} generated shapes')
    probes = attachment_probes(shapes)
    print(f'PASS {len(probes)} structural attachment probes and all cable/laundry endpoints')
    count = laundry_clearance(shapes)
    print(f'PASS all {count} laundry cloths clear architecture and the E2 window opening')
    if args.probes:
        args.probes.parent.mkdir(parents=True, exist_ok=True)
        args.probes.write_text(json.dumps(probes, indent=2)+'\n')


if __name__ == '__main__':
    main()
