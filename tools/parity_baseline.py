"""Validate the parity contract and lock local reference identities/capture evidence.

No build, network, engine, or third-party Python packages are needed. A capture
receipt is provenance, not proof that engines look or behave equivalently.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SCOPES = {
    "defold": ("game", "main", "render", "world", "weapons", "soldiers", "physics", "audio", "audiosynth", "worldmesh", "input", "game.project"),
    "threejs": ("src", "package.json", "package-lock.json", "index.html", "vite.config.js"),
    "kaigen": ("src", "shaders", "assets", "gameplay_blocks", "hzproject.hzt", "web"),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def fingerprint(root, scopes):
    """Hash unambiguous path/length/content records; ignore timestamps and Git state."""
    paths = []
    for scope in scopes:
        path = root / scope
        if not path.exists():
            raise ValueError(f"Missing source scope: {path}")
        if path.is_dir():
            paths.extend(p for p in path.rglob("*") if p.is_file())
        else:
            paths.append(path)
    digest = hashlib.sha256()
    for path in sorted(paths):
        relative = path.relative_to(root).as_posix().encode()
        data = path.read_bytes()
        digest.update(relative + b"\0" + str(len(data)).encode() + b"\0" + data)
    return {"sha256": digest.hexdigest(), "files": len(paths), "scopes": list(scopes)}


def revision(root):
    if not (root / ".git").exists():
        return None
    return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()


def validate_contract(contract, roots):
    if contract["schema_version"] != 1:
        raise ValueError("Unsupported contract version")
    scenarios = contract["scenarios"]
    ids = [s["id"] for s in scenarios]
    if not ids or len(ids) != len(set(ids)):
        raise ValueError("Scenario IDs must be nonempty and unique")
    for scenario in scenarios:
        for key in ("feature", "procedure", "expect", "current"):
            if not scenario.get(key):
                raise ValueError(f"Missing {key}: {scenario['id']}")
        for reference in scenario["references"]:
            engine, relative = reference.split(":", 1)
            if engine not in roots or not (roots[engine] / relative).is_file():
                raise ValueError(f"Missing reference: {reference}")
        for relative in scenario["coverage"]:
            if not (roots["defold"] / relative).is_file():
                raise ValueError(f"Missing coverage: {relative}")
    for adaptation in contract["adaptations"]:
        if adaptation["gate"] not in ids:
            raise ValueError(f"Unknown adaptation gate: {adaptation['gate']}")
    return len(ids)


def legacy_fingerprint(engine, root):
    """Existing capture formats predate the path/length-delimited source lock."""
    digest = hashlib.sha256()
    if engine == "threejs":
        # Match the adapter's directory-first traversal (not one globally sorted list).
        def walk(directory):
            for p in sorted(directory.iterdir()):
                if p.is_dir():
                    walk(p)
                elif p.suffix == ".js":
                    digest.update(p.relative_to(root).as_posix().encode())
                    digest.update(p.read_bytes())
        walk(root / "src")
        digest.update((root / "package-lock.json").read_bytes())
    elif engine == "defold":
        for folder in ("game", "main", "render", "world", "weapons", "soldiers"):
            for p in sorted((root / folder).rglob("*")):
                if p.is_file():
                    digest.update(p.relative_to(root).as_posix().encode())
                    digest.update(p.read_bytes())
        digest.update((root / "game.project").read_bytes())
    else:
        raise ValueError(f"No capture verifier for {engine}")
    return digest.hexdigest()


def validate_reference_camera(shot):
    """Verify actual camera pose, not just echoed level-space request fields."""
    camera = shot["camera"]
    matrix = shot.get("level_to_world_matrix", [])
    position, rotation = camera.get("position", []), camera.get("quaternion", [])
    if len(matrix) != 16 or len(position) != 3 or len(rotation) != 4:
        raise ValueError("Missing actual camera transform")
    if not all(math.isfinite(x) for x in [*matrix, *position, *rotation]):
        raise ValueError("Nonfinite actual camera transform")

    def world(vector):
        return [sum(matrix[j * 4 + i] * vector[j] for j in range(3)) + matrix[12 + i] for i in range(3)]

    eye, target = world(camera["level_position"]), world(camera["level_target"])
    direction = [target[i] - eye[i] for i in range(3)]
    length = math.sqrt(sum(v * v for v in direction))
    if length < 1e-9 or any(abs(a - b) > 1e-6 for a, b in zip(position, eye)):
        raise ValueError("Actual camera position differs from request")
    x, y, z, w = rotation
    forward = [-2 * (x*z + w*y), -2 * (y*z - w*x), -(1 - 2 * (x*x + y*y))]
    if any(abs(a - b / length) > 1e-6 for a, b in zip(forward, direction)):
        raise ValueError("Actual camera aim differs from request")


def capture_receipt(path, roots, catalog, allow_partial=False):
    report = json.loads(path.read_text())
    engine = report["engine"]
    failed = {name: s.get("reason", "Failed capture") for name, s in report["shots"].items() if s["status"] == "failed"}
    if (report.get("error") or failed) and not allow_partial:
        raise ValueError(f"Failed capture: {path}")
    if report.get("source_sha256") != legacy_fingerprint(engine, roots[engine]):
        raise ValueError(f"Stale capture source: {path}")
    version = report.get("catalog_version", report.get("catalog", {}).get("version"))
    if version != catalog["version"]:
        raise ValueError(f"Stale capture catalogue: {path}")
    shots = {s["id"]: s for s in catalog["shots"]}
    captured, repeated, pending, states, defaults = [], [], {}, {}, {}
    for name, shot in report["shots"].items():
        if name not in shots:
            raise ValueError(f"Unknown captured shot: {name}")
        if shot["status"] != "captured":
            if shot["status"] == "failed" and allow_partial:
                continue
            if shot["status"] not in ("pending", "unsupported"):
                raise ValueError(f"Unknown capture status: {shot['status']}")
            pending[name] = shot.get("reason", shot["status"])
            continue
        for item in [shot, *shot.get("repeats", [])]:
            image = (path.parent / item["image"]).resolve()
            if not image.is_relative_to(path.parent.resolve()) or sha(image.read_bytes()) != item["sha256"]:
                raise ValueError(f"Changed or invalid capture image: {name}")
        captured.append(name)
        if engine == "threejs":
            camera = shot.get("camera", {})
            expected = shots[name]
            hour = expected.get("requested_hour", {"daylight": 16.5, "sunset": 19.2, "night": 1.5}[expected.get("lighting", "daylight")])
            weapon = expected.get("weapon_id", "rifle") if expected.get("weapon") else None
            if (camera.get("level_position") != expected["position"] or camera.get("level_target") != expected["target"]
                    or camera.get("vertical_fov") != expected["fov"] or not math.isclose(shot.get("hour", -1), hour, abs_tol=1e-9)
                    or shot.get("weapon_id") != weapon or not shot.get("deterministic")
                    or not shot.get("quality") or not shot.get("exposure")):
                raise ValueError(f"Missing or mismatched capture state: {name}")
            validate_reference_camera(shot)
            if not defaults:
                defaults = {k: shot[k] for k in ("quality", "gpu", "settings", "level_to_world_matrix", "display_exposure") if k in shot}
            states[name] = {k: shot[k] for k in ("camera", "hour", "sun_direction", "weather", "exposure", "weapon_id", "frame") if k in shot}
            if shot.get("repeats") and all(r.get("identical") is True for r in shot["repeats"]):
                repeated.append(name)
        else:
            if shot.get("repeat_identical") is True:
                repeated.append(name)
            capture = shot.get("capture", {})
            lighting = capture.get("lighting", {})
            states[name] = {"camera_radians": capture.get("camera"), "hour": lighting.get("rig", {}).get("hour"),
                            "sun_direction": lighting.get("rig", {}).get("sun_direction"), "exposure": lighting.get("exposure")}
            if not defaults:
                defaults = {k: shot.get("renderer", {}).get(k) for k in ("settings", "pipeline", "material_quality")}
    missing = sorted(set(shots) - set(report["shots"]))
    if not captured:
        raise ValueError(f"No captured images: {path}")
    return {"engine": engine, "manifest": str(path.resolve().relative_to(ROOT)) if path.resolve().is_relative_to(ROOT) else str(path),
            "manifest_sha256": sha(path.read_bytes()), "created_utc": report.get("created_utc"),
            "capture_source_sha256": report["source_sha256"], "adapter_sha256": report.get("adapter_sha256"),
            "catalog_version": version, "captured": captured, "reported_repeat_identical": repeated,
            "pending": pending, "not_run": missing,
            "run_error": report.get("error"), "failed": failed,
            "first_capture_settings": defaults, "applied_states": states,
            "all_catalog_shots_captured_and_repeated": not report.get("error") and not failed and len(captured) == len(shots) == len(repeated),
            "qualification": "Image checksums and current source/camera metadata validated; parity, motion, audio and sustained performance are not inferred."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--threejs", type=Path, required=True)
    parser.add_argument("--kaigen", type=Path, required=True)
    parser.add_argument("--capture", type=Path, action="append", default=[])
    parser.add_argument("--partial-capture", type=Path, action="append", default=[],
                        help="Explicitly retain validated successful shots from a failed run, including its failure record")
    parser.add_argument("--output", type=Path, default=ROOT / "parity/reference-lock.json")
    parser.add_argument("--check", action="store_true", help="Check existing lock for source/contract/catalogue drift")
    parser.add_argument("--update", action="store_true", help="Explicitly replace an existing lock")
    args = parser.parse_args()
    roots = {"defold": ROOT, "threejs": args.threejs.resolve(), "kaigen": args.kaigen.resolve()}
    contract = json.loads((ROOT / "parity/contract.json").read_text())
    scenarios = validate_contract(contract, roots)
    catalog = json.loads(subprocess.check_output(["lua", "tools/export_parity.lua", "catalog"], cwd=ROOT))
    sources = {name: {**fingerprint(path, SCOPES[name]), "git_revision": revision(path),
               "revision_status": "Git commit plus working source hash" if (path / ".git").exists() else "Source archive; exact commit unavailable"}
               for name, path in roots.items()}
    stable = {"schema_version": 1, "contract_sha256": sha(canonical(contract)),
              "fingerprint_method": "Sorted relative UTF-8 path + NUL + decimal byte length + NUL + file bytes; SHA-256.",
              "sources": sources, "catalog": catalog}
    receipts = [capture_receipt(p, roots, catalog) for p in args.capture]
    receipts += [capture_receipt(p, roots, catalog, allow_partial=True) for p in args.partial_capture]
    if args.check:
        saved = json.loads(args.output.read_text())
        for key, value in stable.items():
            if saved[key] != value:
                raise ValueError(f"Baseline drift in {key}; review changes before --update")
        print(f"PASS lock: {scenarios} scenarios, {len(catalog['shots'])} cameras, three source snapshots; {len(receipts)} capture manifests checked")
    else:
        if args.output.exists() and not args.update:
            raise ValueError("Lock exists; use --check or explicitly --update")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({**stable, "created_utc": datetime.now(timezone.utc).isoformat(),
            "evidence": receipts, "parity_qualified": False}, indent=2) + "\n")
        print(f"WROTE {args.output}: {scenarios} scenarios, {len(catalog['shots'])} cameras, {len(receipts)} capture receipts")


if __name__ == "__main__":
    main()
