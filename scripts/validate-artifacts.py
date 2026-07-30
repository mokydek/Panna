#!/usr/bin/env python3
"""Validate the lightweight Roblox bake and Blender/Roblox asset contracts."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def descendants(node: dict):
    stack = [node]
    while stack:
        item = stack.pop()
        yield item
        stack.extend(item.get("Children", []))


def attribute(node: dict, name: str):
    value = node.get("Properties", {}).get("Attributes", {}).get(name, {})
    return next(iter(value.values()), None)


def validate_district() -> tuple[int, int]:
    path = ROOT / "src" / "world" / "PannaDistrict.model.json"
    root = json.loads(path.read_text(encoding="utf-8"))
    assert attribute(root, "LayoutVersion") == "0.3.0-alpha"
    assert attribute(root, "FieldStyle") == "BrightBlockFootballV1"
    assert attribute(root, "MechanicsVersion") == "StreetControlV3"
    assert attribute(root, "VFXVersion") == "StreetReadabilityV1"
    assert attribute(root, "EditablePieces") is True

    all_nodes = list(descendants(root))
    counts = Counter(node.get("ClassName") for node in all_nodes)
    assert counts["Part"] <= 650, counts
    assert counts["WedgePart"] >= 6, counts
    assert all(
        node.get("Properties", {}).get("Material") != "Neon"
        for node in all_nodes
        if node.get("ClassName") in {"Part", "WedgePart", "SpawnLocation"}
    )
    balls = [
        node
        for node in all_nodes
        if node.get("Name") == "Ball" or node.get("Name") == "TrainingBall"
    ]
    assert len(balls) == 7
    assert all(attribute(ball, "MechanicsVersion") == "StreetControlV3" for ball in balls)
    assert all(
        node.get("Properties", {}).get("Enabled") is False
        for node in all_nodes
        if node.get("ClassName") == "PointLight"
    )

    arenas = next(child for child in root["Children"] if child.get("Name") == "Arenas")
    arena_models = [child for child in arenas["Children"] if child.get("ClassName") == "Model"]
    assert len(arena_models) == 6
    required = {"Court", "Ball", "Bounds", "HomeGoal", "AwayGoal", "EntryZone", "ExitZone"}
    for arena in arena_models:
        names = {child.get("Name") for child in arena.get("Children", [])}
        assert required <= names, (arena.get("Name"), required - names)
    return counts["Part"], counts["WedgePart"]


def validate_roblox_kit() -> tuple[int, int]:
    path = ROOT / "src" / "world" / "PannaBrightBlockKit.model.json"
    root = json.loads(path.read_text(encoding="utf-8"))
    assets = root.get("Children", [])
    assert len(assets) == 12
    parts = [
        node
        for asset in assets
        for node in asset.get("Children", [])
        if node.get("ClassName") in {"Part", "WedgePart"}
    ]
    assert attribute(root, "WorkspaceIntegrated") is True
    assert attribute(root, "DetailRevision") == "DetailedBlocksV2"
    assert attribute(root, "BlenderMinimumPolygons") >= 3_000
    assert len(parts) == attribute(root, "NativeComponentCount") == 120
    assert all(attribute(asset, "EditablePieces") is True for asset in assets)
    assert all(attribute(part, "EditablePiece") is True for part in parts)
    assert all(attribute(asset, "BlenderPolygons") >= 3_000 for asset in assets)
    assert all(attribute(asset, "DetailRevision") == "DetailedBlocksV2" for asset in assets)
    assert {node.get("ClassName") for node in parts} == {"Part", "WedgePart"}
    return len(assets), len(parts)


def validate_blender_kit() -> tuple[int, int]:
    folder = ROOT / "assets" / "blender"
    report = json.loads((folder / "polygon-report.json").read_text(encoding="utf-8"))
    objects = report["objects"]
    assert report["all_mesh_objects_are_separate"] is True
    assert len(objects) == report["mesh_object_count"] == 12
    assert len({item["name"] for item in objects}) == len(objects)
    minimum = min(item["polygons"] for item in objects)
    assert report["detail_revision"] == "DetailedBlocksV2"
    assert minimum >= report["minimum_polygons"] >= 3_000
    assert all(item["component_count"] >= 6 for item in objects)
    for item in objects:
        individual = folder / item["individual_fbx"]
        assert individual.is_file() and individual.stat().st_size > 10_000
    for filename in (
        "Panna_BrightBlock_Kit.blend",
        "Panna_BrightBlock_Kit_AllObjects.fbx",
        "Panna_BrightBlock_Kit_AllObjects.obj",
        "Panna_BrightBlock_Kit_Preview.png",
    ):
        artifact = folder / filename
        assert artifact.is_file() and artifact.stat().st_size > 10_000
    return len(objects), minimum


def main() -> None:
    district_parts, district_wedges = validate_district()
    roblox_models, roblox_parts = validate_roblox_kit()
    blender_objects, minimum_polygons = validate_blender_kit()
    print(
        "PANNA_ARTIFACTS_OK "
        f"district_parts={district_parts} district_wedges={district_wedges} "
        f"roblox_models={roblox_models} roblox_parts={roblox_parts} "
        f"blender_objects={blender_objects} min_polygons={minimum_polygons}"
    )


if __name__ == "__main__":
    main()
