#!/usr/bin/env python3
"""Generate the detailed native Roblox replica of the Blender asset kit.

The result is placed directly in Workspace by the release Rojo projects. Every
visual component remains an independent Part/WedgePart, so no uploaded MeshId is
required to open, move, recolor or resize the design in Roblox Studio.
"""

from __future__ import annotations

import json
from pathlib import Path

from brightblock_assets import ASSETS, DETAIL_REVISION, MIN_POLYGONS, PALETTE, component_count


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src" / "world" / "PannaBrightBlockKit.model.json"
REPORT = ROOT / "assets" / "blender" / "polygon-report.json"
GALLERY_ORIGIN = (0.0, 0.65, 225.0)


def roblox_color(material: str) -> list[float]:
    red, green, blue, _alpha = PALETTE[material]
    return [red, green, blue]


def roblox_size(size: tuple[float, float, float]) -> list[float]:
    x, y, z = size
    return [x, z, y]


def roblox_position(location: tuple[float, float, float]) -> list[float]:
    x, y, z = location
    origin_x, origin_y, origin_z = GALLERY_ORIGIN
    return [x + origin_x, z + origin_y, y + origin_z]


def part(asset_name: str, index: int, specification: dict) -> dict:
    position = roblox_position(specification["location"])
    role = specification["role"]
    return {
        "Name": f"{asset_name}_Piece_{index:02d}_{role}",
        "ClassName": "WedgePart" if specification["kind"] == "wedge" else "Part",
        "Properties": {
            "Anchored": True,
            "CanCollide": role
            in {
                "foundation",
                "display_floor",
                "marker_base",
                "trophy_base",
                "base",
                "pedestal",
                "first_step",
                "second_step",
                "third_step",
            },
            "CanQuery": True,
            "CanTouch": False,
            "CastShadow": False,
            "Locked": False,
            "Color": roblox_color(specification["material"]),
            "Material": "SmoothPlastic",
            "Size": roblox_size(specification["size"]),
            "Position": position,
            "CFrame": [*position, 1, 0, 0, 0, 1, 0, 0, 0, 1],
            "TopSurface": "Smooth",
            "BottomSurface": "Smooth",
            "Attributes": {
                "EditablePiece": {"Bool": True},
                "BlenderObject": {"String": asset_name},
                "ComponentRole": {"String": role},
                "ComponentShape": {"String": specification["kind"]},
                "DetailRevision": {"String": DETAIL_REVISION},
            },
        },
    }


def polygon_counts() -> dict[str, int]:
    if not REPORT.is_file():
        return {}
    report = json.loads(REPORT.read_text(encoding="utf-8"))
    return {item["name"]: item["polygons"] for item in report.get("objects", [])}


def model(asset: dict, polygons: dict[str, int]) -> dict:
    name = asset["name"]
    children = [part(name, index, item) for index, item in enumerate(asset["components"], start=1)]
    return {
        "Name": name,
        "ClassName": "Model",
        "Properties": {
            "Attributes": {
                "EditablePieces": {"Bool": True},
                "ShapeFamily": {"String": asset["shape_family"]},
                "BlenderSource": {"String": "assets/blender/Panna_BrightBlock_Kit.blend"},
                "IndividualFBX": {"String": f"assets/blender/individual_fbx/{name}.fbx"},
                "BlenderPolygons": {"Float64": polygons.get(name, MIN_POLYGONS)},
                "ComponentCount": {"Float64": len(children)},
                "DetailRevision": {"String": DETAIL_REVISION},
            }
        },
        "Children": children,
    }


def main() -> None:
    polygons = polygon_counts()
    assets = [model(asset, polygons) for asset in ASSETS]
    root = {
        "ClassName": "Model",
        "Properties": {
            "Attributes": {
                "EditablePieces": {"Bool": True},
                "WorkspaceIntegrated": {"Bool": True},
                "MeshObjectCount": {"Float64": len(assets)},
                "NativeComponentCount": {"Float64": component_count()},
                "BlenderMinimumPolygons": {"Float64": MIN_POLYGONS},
                "DetailRevision": {"String": DETAIL_REVISION},
                "PrimaryShapes": {"String": "Cubes,Rectangles,Triangles"},
                "GalleryOrigin": {"Vector3": list(GALLERY_ORIGIN)},
            }
        },
        "Children": assets,
    }
    OUTPUT.write_text(json.dumps(root, separators=(",", ":")), encoding="utf-8")
    print(
        "PANNA_ROBLOX_KIT_OK "
        f"models={len(assets)} parts={component_count()} detail_revision={DETAIL_REVISION}"
    )


if __name__ == "__main__":
    main()
