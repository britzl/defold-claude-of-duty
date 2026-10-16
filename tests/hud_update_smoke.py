"""Check retained HUD/minimap updates across movement, damage and pool reuse.
PYTHONPATH=automation-bridge-python python3 tests/hud_update_smoke.py
Requires the open Defold editor. Owns and closes its engine.
"""
from pathlib import Path
import math
from automation_bridge import editor, engine


def main():
    project=editor.open_project(Path(__file__).resolve().parents[1],start_if_needed=False)
    game=project.build_and_run(timeout=180,focus=True)
    def cmd(name,data=None): return game.command(name,data or {})["result"]
    def settle(): game.wait_frames(30,timeout=20)
    def resume():
        cmd("ui.focus",{"focused":True});cmd("ui.pause",{"paused":False})
    def text(name): return game.element(name_exact=name).text
    def map_snapshot():
        page=game.elements_page(type="gui_node_box",name="map_",visible=True,limit=500)
        assert not page.truncated and page.next_cursor is None
        border=game.element(name_exact="map_background").bounds
        rows={}
        for node in page.elements:
            if not node.name.removeprefix("map_").isdigit(): continue
            b=node.bounds
            assert b.x>=border.x-1 and b.y>=border.y-1,(node.name,b,border)
            assert b.x+b.w<=border.x+border.w+1 and b.y+b.h<=border.y+border.h+1
            rows[node.name]=tuple(round(v,3) for v in (b.x,b.y,b.w,b.h))
        assert 0<len(rows)<=256
        return rows
    def place(x,y,z,yaw=0):
        resume();cmd("movement.reset",{"x":x,"y":y,"z":z,"yaw":yaw});settle()
        cmd("ui.pause",{"paused":True});settle()
        return map_snapshot()
    try:
        engine.wait_until(lambda:cmd("world.snapshot")["ready"] and cmd("renderer.snapshot")["ready"],timeout=90)
        game.resize(960,640);settle()
        cmd("ai.configure",{"enabled":False})
        initial=place(0,.004,10)
        assert text("health")=="HEALTH 100" and text("heading")=="000"
        settle();assert map_snapshot()==initial
        for point in ((-10,.15,0,-math.pi/2),(10,6.55,-7,0),(0,.004,-45,math.pi)):
            other=place(*point);assert other!=initial
        returned=place(0,.004,10);assert returned==initial,"Pooled map nodes did not restore exactly"
        east=place(0,.004,10,-math.pi/2)
        assert text("heading")=="090" and east==initial,"North-up map must not rotate with the player"
        for w,h in ((640,360),(400,600),(960,640)):
            game.resize(w,h);settle();map_snapshot()
        assert map_snapshot()==initial,"Anchoring changed unchanged map geometry"
        resume();cmd("gameplay.damage",{"target":"player","amount":25});settle()
        assert text("health")=="HEALTH 75"
        cmd("weapons.drive",{"segments":[{"ticks":90},{"ticks":1,"fire":True},{"ticks":45}]})
        engine.wait_until(lambda:cmd("weapons.result")["complete"],timeout=15)
        settle();assert "30 / 210" in text("ammo"),text("ammo")
        cmd("gameplay.damage",{"target":"player","amount":999});settle()
        assert text("health")=="HEALTH 0" and text("death")=="YOU WERE ELIMINATED"
        cmd("gameplay.restart");cmd("ai.configure",{"enabled":False});resume();settle()
        assert text("health")=="HEALTH 100" and not text("death"),(text("health"),text("death"),cmd("gameplay.snapshot"))
        assert "31 / 210" in text("ammo")
        print("PASS stationary/map-return equality, pooled node reuse, floor changes, compass, resize, damage, ammo, death and restart",flush=True)
    finally:
        game.close_engine();game.close()
    errors=[line for line in project.console.read().lines if "ERROR:" in line or "WARNING:" in line]
    assert not errors,errors


if __name__=="__main__": main()
