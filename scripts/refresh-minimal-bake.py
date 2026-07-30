#!/usr/bin/env python3
"""Refresh the checked-in Roblox JSON model for the bright block-art release.

This deliberately keeps gameplay markers, prompts, goals, balls and room contracts
untouched while removing purely decorative repetition from the existing Studio bake.
The canonical geometry remains WorldBuilder.lua; this script makes the Edit Mode
snapshot immediately useful on machines that do not have Roblox Studio CLI.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = ROOT / "src" / "world" / "PannaDistrict.model.json"

COLORS = {
    (0.258824, 0.274510, 0.282353): (43 / 255, 48 / 255, 58 / 255),
    (0.168627, 0.188235, 0.180392): (20 / 255, 24 / 255, 32 / 255),
    (0.211765, 0.364706, 0.541176): (45 / 255, 134 / 255, 1.0),
    (0.521569, 0.537255, 0.517647): (210 / 255, 216 / 255, 224 / 255),
    (0.286275, 0.466667, 0.501961): (0.0, 214 / 255, 242 / 255),
    (0.262745, 0.305882, 0.286275): (44 / 255, 54 / 255, 68 / 255),
    (0.231373, 0.454902, 0.262745): (59 / 255, 196 / 255, 106 / 255),
    (0.694118, 0.435294, 0.215686): (1.0, 145 / 255, 58 / 255),
    (0.568627, 0.282353, 0.305882): (1.0, 61 / 255, 129 / 255),
    (0.356863, 0.317647, 0.423529): (139 / 255, 92 / 255, 246 / 255),
    (0.921569, 0.968627, 1.0): (250 / 255, 252 / 255, 1.0),
    (0.788235, 0.662745, 0.298039): (1.0, 221 / 255, 57 / 255),
}

COURT_COLORS = [
    (61 / 255, 170 / 255, 91 / 255),
    (68 / 255, 181 / 255, 99 / 255),
    (55 / 255, 161 / 255, 85 / 255),
    (64 / 255, 175 / 255, 94 / 255),
    (72 / 255, 186 / 255, 103 / 255),
    (52 / 255, 157 / 255, 82 / 255),
]


def close_color(left: list[float], right: tuple[float, float, float]) -> bool:
    return len(left) == 3 and all(abs(a - b) < 0.002 for a, b in zip(left, right))


def remap_color(node: dict) -> None:
    value = node.get("Properties", {}).get("Color")
    if not isinstance(value, list):
        return
    for old, new in COLORS.items():
        if close_color(value, old):
            node["Properties"]["Color"] = list(new)
            return


def trim_children(node: dict) -> None:
    name = node.get("Name", "")
    children = node.get("Children", [])

    if name == "CenterCircle":
        children = [
            child
            for child in children
            if int(child.get("Name", "Segment_00").rsplit("_", 1)[-1]) % 2 == 1
        ]
    elif name == "PitchFinish":
        children = [
            child for child in children if child.get("Name") in {"MowingStripe_02", "MowingStripe_06"}
        ]
    elif name == "Fence":
        children = [
            child
            for child in children
            if "Post" not in child.get("Name", "") and "BoundaryRail" not in child.get("Name", "")
        ]
        rebuilt: list[dict] = []
        for child in children:
            child_name = child.get("Name", "")
            if "Board" in child_name or "InvisibleWall" in child_name:
                rebuilt.append(child)
                continue

            props = child.setdefault("Properties", {})
            size = list(props.get("Size", [1, 16, 1]))
            position = list(props.get("Position", [0, 8, 0]))
            cframe = list(props.get("CFrame", position + [1, 0, 0, 0, 1, 0, 0, 0, 1]))
            is_end = child_name.startswith("EndPanel")
            board_name = child_name.replace("Panel", "Board")
            wall_name = child_name.replace("Panel", "InvisibleWall")

            board = copy.deepcopy(child)
            board["Name"] = board_name
            board_props = board.setdefault("Properties", {})
            board_props["Size"] = [size[0], 3.2, size[2]]
            board_props["Position"] = [position[0], 1.6, position[2]]
            board_props["CFrame"] = [position[0], 1.6, position[2], *cframe[3:]]
            board_props["Transparency"] = 0
            board_props["CastShadow"] = False
            board_props["Material"] = "SmoothPlastic"
            if is_end:
                board_props["Color"] = list(COLORS[(0.211765, 0.364706, 0.541176)] if position[2] < 0 else COLORS[(0.694118, 0.435294, 0.215686)])
            else:
                board_props["Color"] = list(COLORS[(0.286275, 0.466667, 0.501961)] if position[0] < 0 else COLORS[(0.568627, 0.282353, 0.305882)])

            wall = copy.deepcopy(child)
            wall["Name"] = wall_name
            wall_props = wall.setdefault("Properties", {})
            wall_props["Size"] = [size[0], 12.8, size[2]]
            wall_props["Position"] = [position[0], 9.6, position[2]]
            wall_props["CFrame"] = [position[0], 9.6, position[2], *cframe[3:]]
            wall_props["Transparency"] = 1
            wall_props["CastShadow"] = False
            wall_props["Material"] = "SmoothPlastic"
            rebuilt.extend((board, wall))
        children = rebuilt
    elif name == "SpectatorStand":
        children = [
            child
            for child in children
            if child.get("Name") in {"StandBase", "Bench_1", "Bench_2"}
        ]
    elif name.endswith("Theme"):
        children = children[:2]
        for index, child in enumerate(children, start=1):
            child["Name"] = "IdentityBlock" if index == 1 else "IdentityTriangle"
            child["ClassName"] = "Part" if index == 1 else "WedgePart"
            props = child.setdefault("Properties", {})
            if index == 1:
                props["Shape"] = "Block"
            else:
                props.pop("Shape", None)
            props["Material"] = "SmoothPlastic"
            props["Transparency"] = 0
            props["CanCollide"] = index == 1
    elif name == "Floodlights":
        prefixes: list[str] = []
        kept: list[dict] = []
        for child in children:
            child_name = child.get("Name", "")
            prefix = child_name.removesuffix("Lamp").removesuffix("Post")
            if prefix not in prefixes and len(prefixes) < 1:
                prefixes.append(prefix)
            if prefix in prefixes:
                child["Name"] = "CourtLampLamp" if child_name.endswith("Lamp") else "CourtLampPost"
                kept.append(child)
        children = kept
    elif name == "LaneMarkers":
        children = [
            child
            for child in children
            if int(child.get("Name", "Marker_00").rsplit("_", 1)[-1]) % 3 == 0
        ]
    elif name == "RoomCrosswalks":
        children = [
            child
            for child in children
            if int(child.get("Name", "_0").rsplit("_", 1)[-1]) in {2, 4, 6}
        ]
    elif name == "DistrictLighting":
        children = children[:8]
    elif name == "DistrictSkyline":
        children = [
            child
            for child in children
            if "RoofRail" not in child.get("Name", "")
            and not any(f"_{index:02d}_" in child.get("Name", "") for index in range(3, 10))
        ]

    node["Children"] = children


def walk(node: dict, arena_index: int | None = None) -> None:
    name = node.get("Name", "")
    if name.startswith("Arena_") and name.removeprefix("Arena_").isdigit():
        arena_index = int(name.removeprefix("Arena_"))
        attrs = node.setdefault("Properties", {}).setdefault("Attributes", {})
        attrs["PitchStyle"] = {"String": "BrightBlockFootballV1"}
        attrs["EditablePieces"] = {"Bool": True}

    props = node.setdefault("Properties", {})
    attrs = props.get("Attributes", {})
    if name in {"DistrictEnvironment", "Fence", "SpectatorStand"} or name.endswith("Theme"):
        attrs["EditablePieces"] = {"Bool": True}
        props["Attributes"] = attrs

    if name == "DistrictEnvironment":
        attrs["DistrictStyle"] = {"String": "BrightBlockDistrict"}
        attrs["FieldStyle"] = {"String": "BrightBlockFootballV1"}

    if name in {"Ball", "TrainingBall"}:
        attrs["MechanicsVersion"] = {"String": "StreetControlV3"}
        props["Attributes"] = attrs

    if name == "Court" and arena_index and 1 <= arena_index <= len(COURT_COLORS):
        props["Color"] = list(COURT_COLORS[arena_index - 1])
    elif name == "DistrictGround":
        props["Color"] = [143 / 255, 181 / 255, 148 / 255]
    else:
        remap_color(node)

    if node.get("ClassName") == "PointLight":
        props["Enabled"] = False

    trim_children(node)
    for child in node.get("Children", []):
        walk(child, arena_index)


def count_classes(node: dict) -> dict[str, int]:
    counts: dict[str, int] = {}
    stack = [node]
    while stack:
        item = stack.pop()
        class_name = item.get("ClassName", "Unknown")
        counts[class_name] = counts.get(class_name, 0) + 1
        stack.extend(item.get("Children", []))
    return counts


def main() -> None:
    root = json.loads(MODEL_PATH.read_text(encoding="utf-8"))
    before = count_classes(root)
    attrs = root.setdefault("Properties", {}).setdefault("Attributes", {})
    attrs["LayoutVersion"] = {"String": "0.3.0-alpha"}
    attrs["FieldStyle"] = {"String": "BrightBlockFootballV1"}
    attrs["EditablePieces"] = {"Bool": True}
    attrs["MechanicsVersion"] = {"String": "StreetControlV3"}
    attrs["VFXVersion"] = {"String": "StreetReadabilityV1"}
    walk(root)
    after = count_classes(root)

    required = {"Arenas", "DistrictEnvironment", "Lobby"}
    child_names = {child.get("Name") for child in root.get("Children", [])}
    missing = required - child_names
    if missing:
        raise RuntimeError(f"refusing to write bake missing required roots: {sorted(missing)}")
    if after.get("Part", 0) > 650:
        raise RuntimeError("minimal bake exceeded the 650-Part budget")

    MODEL_PATH.write_text(
        json.dumps(root, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(
        "PANNA_MINIMAL_BAKE_OK "
        f"parts={before.get('Part', 0)}->{after.get('Part', 0)} "
        f"wedge_parts={after.get('WedgePart', 0)}"
    )


if __name__ == "__main__":
    main()
