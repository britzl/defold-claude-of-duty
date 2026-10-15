"""Full-map Bullet route matrix, real traversal and inspection captures on Mac.
Run with PYTHONPATH=automation-bridge-python. Owns and closes its test engine.
"""
import argparse
import json
import math
import shutil
import time
from pathlib import Path
from automation_bridge import editor, engine
from world_navigation import read_navigation

ROOT = Path(__file__).resolve().parents[1]
VIEWS = ('north_plaza', 'east_alley', 'ruin_yard', 'cross_street', 'gate',
         'e1_shop', 'e1_top', 'e3_room')


def main(quick=False):
    output = ROOT / ('build/full-market-quick-validation' if quick else 'build/full-market-validation')
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180)
    report = {'player_routes': [], 'ai_routes': [], 'views': []}

    def cmd(name, data=None):
        return game.command(name, data or {})['result']

    def running():
        if cmd('ui.snapshot')['paused']:
            cmd('ui.focus', {'focused': True})
            cmd('ui.pause', {'paused': False})

    def drive(segments):
        running()
        cmd('movement.drive', {'segments': segments})
        def complete():
            running()
            return cmd('movement.result')['complete']
        engine.wait_until(complete, timeout=25)
        result = cmd('movement.result')['result']
        assert not result['recovery_failed'] and result['jumps'] == 0, result

    def walk_to(point):
        for _ in range(100):
            p = cmd('gameplay.snapshot')
            dx, dz = point['x']-p['x'], point['z']-p['z']
            distance = math.hypot(dx, dz)
            if distance < .13:
                drive([dict(ticks=12)])
                p = cmd('gameplay.snapshot')
                assert abs(p['y']-point['y']) < .08 and p['grounded'], (point, p)
                return
            speed = min(3, distance*3)
            ticks = max(12, min(120, int(distance/speed*96)))
            drive([dict(ticks=ticks, move_x=dx/distance*speed/(4.57*.92),
                        move_z=dz/distance*speed/(4.57*(.8 if dz > 0 else 1)))])
        raise AssertionError(('Player stuck', point, cmd('gameplay.snapshot')))

    def player_route(name, points):
        cmd('movement.reset', dict(x=points[0]['x'], y=points[0]['y']+.005,
                                   z=points[0]['z'], yaw=0))
        for point in points[1:]:
            walk_to(point)
        for point in reversed(points[:-1]):
            walk_to(point)
        report['player_routes'].append(name)
        print('PASS player route in both directions', name, flush=True)

    try:
        engine.wait_until(lambda: game.state('world').value['ready'], timeout=60)
        engine.wait_until(lambda: len(cmd('ai.snapshot')['actors']) == 6, timeout=5)
        cmd('ai.configure', {'enabled': False})
        running()
        game.wait_frames(5)
        report['world'] = cmd('world.snapshot')
        assert report['world']['batches'] < 560 and report['world']['mesh_bytes'] < 32*1024*1024
        assert report['world']['colliders'] < 1240
        assert cmd('ui.snapshot')['map_rectangles'] == report['world']['colliders']
        valid = cmd('world.validate', {'capsules': True})
        assert valid['max_error'] < 1e-5
        assert all(n['supported'] for n in valid['nodes']), valid
        blocked = [e for e in valid['edges'] if not all(e[k] for k in ('clear', 'forward', 'reverse'))]
        assert not blocked, blocked
        report['physics'] = valid
        print('PASS all nodes supported and all edges capsule-clear in both directions', flush=True)
        nav = read_navigation(cmd)
        nodes = {n['id']: n for n in nav['nodes']}
        # Each of the six original actors must route from its actual spawn to
        # every region/floor. Production walkability queries test each attachment.
        destinations = ['street_north', 'street_south', 'street_gate',
                        'west_near/rear_north', 'west_far/rear_south',
                        'east_loop/ruin_yard', 'east_far/rear_south',
                        'W2/bedroom', 'E2/bedroom', 'E2/floor2/bedroom',
                        'E1/bedroom', 'E1/floor2/bedroom', 'E3/room',
                        'W2/storage', 'W2/living', 'E1/storage', 'E3/storage', 'E3/ruin']
        for actor in cmd('ai.snapshot')['actors']:
            for name in destinations:
                route = cmd('ai.route', {'id': actor['id'], 'target': nodes[name]})['points']
                assert route, (actor['id'], name)
                report['ai_routes'].append([actor['id'], name, len(route)])
            print('PASS route matrix', actor['id'], len(destinations), flush=True)
        if not quick:
            for flank in nav['flanks']:
                player_route(flank['id'], flank['points'])
            # All five flights, with no teleport between floors or on the return.
            for building, floors in (('W2', 2), ('E2', 3), ('E1', 3)):
                names = [building+'/walk', building+'/door', building+'/room']
                for floor in range(1, floors):
                    prefix = building+('/' if floor == 1 else f'/floor{floor}/')
                    names += [prefix+s for s in ('stair_approach', 'stair_bottom', 'stair_top',
                                                 'upper_hall', 'upper_room', 'bedroom',
                                                 'upper_room', 'upper_hall')]
                player_route(building+'_all_floors', [nodes[n] for n in names])
            player_route('E1_alley_entrance', [nodes[n] for n in
                ('east_loop/alley', 'E1/alley_outside', 'E1/alley_door', 'E1/alley_inside', 'E1/room')])
            player_route('E3_ground_room', [nodes[n] for n in ('E3/street', 'E3/walk', 'E3/door', 'E3/room')])
            for name,names in (
                ('W2_storage', ('W2/room','W2/shop_back','W2/storage_door','W2/storage')),
                ('W2_living', ('W2/room','W2/stair_approach','W2/living')),
                ('E1_storage', ('E1/room','E1/storage')),
                ('E3_storage', ('E3/room','E3/storage')),
                ('E3_ruin', ('E3/room','E3/ruin')),
            ):
                player_route(name,[nodes[n] for n in names])
            player_route('gate_and_south_gap', [nodes[n] for n in
                ('street_gate', 'street_cross', 'street_south_gap', 'street_south')])
            # Real patrol locomotion exercises both newly added flights and the
            # eastern bypass. The player remains hidden in another building.
            cmd('movement.reset', dict(x=-10, y=3.35, z=2, yaw=0))
            for start, targets in (
                ('E1/room', ['E1/bedroom', 'E1/floor2/bedroom', 'E1/room']),
                ('east_loop/north_entry', ['east_loop/rear_north', 'east_loop/ruin_yard',
                                          'east_loop/south_entry', 'east_loop/north_entry']),
            ):
                cmd('ai.configure', {'enabled': False})
                cmd('ai.reset', {'position': nodes[start], 'yaw': 0})
                game.wait_frames(5)
                for name in targets:
                    target = nodes[name]
                    cmd('ai.patrol', {'points': [target]})
                    cmd('ai.configure', {'enabled': True})
                    def arrived():
                        running()
                        e = cmd('ai.snapshot')['actors'][0]
                        assert not e['recovery_failed'], e
                        return math.dist([e[k] for k in ('x', 'y', 'z')],
                                         [target[k] for k in ('x', 'y', 'z')]) < .5
                    engine.wait_until(arrived, timeout=100, message='AI stuck reaching '+name)
                    print('PASS live AI patrol', name, flush=True)
            report['live_ai'] = True
        cmd('ai.configure', {'enabled': False})
        for name in VIEWS:
            running()
            cmd('world.view', {'name': name})
            game.wait_frames(20)
            running()
            game.wait_frames(2)
            assert not cmd('ui.snapshot')['paused'], 'Focus loss obscured inspection capture'
            shot = game.screenshot(resolution_multiplier=.75)
            shutil.copyfile(shot.path, output/(name+'.png'))
            report['views'].append(name)
        print('PASS eight full-map inspection captures', flush=True)
        (output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if 'ERROR:' in line]
    assert not errors, '\n'.join(errors)
    print('PASS clean shutdown', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--quick', action='store_true', help='Physics, six-actor route matrix and captures only')
    main(parser.parse_args().quick)
