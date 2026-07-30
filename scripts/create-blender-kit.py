#!/usr/bin/env python3
"""Create the editable, detailed Panna bright-block asset kit in Blender.

Run with:
    blender --background --python scripts/create-blender-kit.py -- <output-directory>

Every mesh object is independent, uses only rectangular blocks or triangular
wedges as its base language, and is baked to at least 3,000 triangle polygons.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT_DIRECTORY = Path(__file__).resolve().parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from brightblock_assets import ASSETS, DETAIL_REVISION, MIN_POLYGONS, PALETTE



def output_directory() -> Path:
    args = sys.argv
    if "--" not in args or args.index("--") == len(args) - 1:
        raise SystemExit("output directory is required after --")
    destination = Path(args[args.index("--") + 1]).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "individual_fbx").mkdir(exist_ok=True)
    return destination


def cleanup_generated_files(destination: Path) -> None:
    for filename in (
        "Panna_BrightBlock_Kit.blend",
        "Panna_BrightBlock_Kit.blend1",
        "Panna_BrightBlock_Kit_AllObjects.fbx",
        "Panna_BrightBlock_Kit_AllObjects.obj",
        "Panna_BrightBlock_Kit_AllObjects.mtl",
        "Panna_BrightBlock_Kit_Preview.png",
        "polygon-report.json",
    ):
        path = destination / filename
        if path.exists():
            path.unlink()
    for path in (destination / "individual_fbx").glob("*.fbx"):
        path.unlink()


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def make_material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    material = bpy.data.materials.new(name=f"MAT_{name.upper()}")
    material.diffuse_color = color
    material.metallic = 0.0
    material.roughness = 0.72
    return material


def add_cube_component(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def add_wedge_component(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
) -> bpy.types.Object:
    x, y, z = (dimension * 0.5 for dimension in size)
    vertices = [
        (-x, -y, -z),
        (x, -y, -z),
        (-x, -y, z),
        (x, -y, z),
        (-x, y, -z),
        (-x, y, z),
    ]
    faces = [
        (0, 1, 3, 2),
        (0, 4, 5, 2),
        (0, 1, 4),
        (2, 5, 3),
        (1, 3, 5, 4),
    ]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    return obj


def add_component(name: str, specification: dict) -> bpy.types.Object:
    if specification["kind"] == "cube":
        return add_cube_component(name, specification["size"], specification["location"])
    if specification["kind"] == "wedge":
        return add_wedge_component(name, specification["size"], specification["location"])
    raise ValueError(f"unknown component kind: {specification['kind']}")


def combine_components(name: str, components: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for component in components:
        component.select_set(True)
    bpy.context.view_layer.objects.active = components[0]
    if len(components) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    return obj


def densify(obj: bpy.types.Object) -> int:
    subdivision = obj.modifiers.new(name="PolygonBudget_3000", type="SUBSURF")
    subdivision.subdivision_type = "SIMPLE"
    subdivision.levels = 3
    subdivision.render_levels = 3
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=subdivision.name)

    triangulate = obj.modifiers.new(name="Roblox_Triangulate", type="TRIANGULATE")
    triangulate.keep_custom_normals = True
    bpy.ops.object.modifier_apply(modifier=triangulate.name)

    polygon_count = len(obj.data.polygons)
    while polygon_count < MIN_POLYGONS:
        subdivision = obj.modifiers.new(name="PolygonBudget_Safety", type="SUBSURF")
        subdivision.subdivision_type = "SIMPLE"
        subdivision.levels = 1
        subdivision.render_levels = 1
        bpy.ops.object.modifier_apply(modifier=subdivision.name)
        triangulate = obj.modifiers.new(name="Roblox_Triangulate_Safety", type="TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=triangulate.name)
        polygon_count = len(obj.data.polygons)
    if polygon_count < MIN_POLYGONS:
        raise RuntimeError(f"{obj.name} has only {polygon_count} polygons")
    return polygon_count


def finish_object(
    obj: bpy.types.Object,
    shape_family: str,
    component_count: int,
) -> bpy.types.Object:
    obj["shape_family"] = shape_family
    obj["roblox_separate_object"] = True
    obj["editable_source"] = True
    obj["detail_revision"] = DETAIL_REVISION
    obj["component_count"] = component_count
    obj["minimum_polygon_contract"] = MIN_POLYGONS
    obj["polygon_count"] = densify(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def create_asset(asset: dict, materials: dict[str, bpy.types.Material]) -> bpy.types.Object:
    pieces: list[bpy.types.Object] = []
    for index, specification in enumerate(asset["components"], start=1):
        piece = add_component(
            f"{asset['name']}_{specification['role']}_{index:02d}",
            specification,
        )
        piece.data.materials.append(materials[specification["material"]])
        pieces.append(piece)
    return finish_object(
        combine_components(asset["name"], pieces),
        asset["shape_family"],
        len(pieces),
    )


def add_camera_and_lights() -> None:
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (26, -34, 28)
    camera.rotation_euler = ((Vector((1, 2, 2.4)) - camera.location).to_track_quat("-Z", "Y")).to_euler()
    camera.data.lens = 54
    bpy.context.scene.camera = camera

    for name, location, energy, size in (
        ("KeyLight", (4, -8, 24), 2900, 9),
        ("FillLight", (-18, -2, 12), 1900, 7),
        ("RimLight", (15, 18, 18), 1500, 6),
    ):
        light_data = bpy.data.lights.new(name, type="AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        light.rotation_euler = (0, 0, 0)
        bpy.context.collection.objects.link(light)


def export_individual_fbx(destination: Path, objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        original_matrix = obj.matrix_world.copy()
        obj.location = (0, 0, 0)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.fbx(
            filepath=str(destination / "individual_fbx" / f"{obj.name}.fbx"),
            use_selection=True,
            apply_unit_scale=True,
            bake_space_transform=True,
            object_types={"MESH"},
            add_leaf_bones=False,
        )
        obj.matrix_world = original_matrix


def main() -> None:
    destination = output_directory()
    cleanup_generated_files(destination)
    reset_scene()
    materials = {name: make_material(name, color) for name, color in PALETTE.items()}
    objects = [create_asset(asset, materials) for asset in ASSETS]

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(destination / "Panna_BrightBlock_Kit_Preview.png")
    scene.render.film_transparent = False
    scene.world.color = (0.075, 0.10, 0.16)
    scene.view_settings.exposure = 0.72
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["panna_asset_contract"] = "separate_detailed_meshes_minimum_3000_triangles"
    scene["panna_detail_revision"] = DETAIL_REVISION
    add_camera_and_lights()

    blend_path = destination / "Panna_BrightBlock_Kit.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(
        filepath=str(destination / "Panna_BrightBlock_Kit_AllObjects.fbx"),
        use_selection=True,
        apply_unit_scale=True,
        bake_space_transform=True,
        object_types={"MESH"},
        add_leaf_bones=False,
    )
    bpy.ops.wm.obj_export(
        filepath=str(destination / "Panna_BrightBlock_Kit_AllObjects.obj"),
        export_selected_objects=True,
        export_materials=True,
        apply_modifiers=True,
    )
    export_individual_fbx(destination, objects)
    bpy.ops.render.render(write_still=True)

    report = {
        "minimum_polygons": MIN_POLYGONS,
        "mesh_object_count": len(objects),
        "all_mesh_objects_are_separate": True,
        "detail_revision": DETAIL_REVISION,
        "shape_families": ["cube_rectangle_triangle"],
        "roblox_native_replica": "src/world/PannaBrightBlockKit.model.json",
        "objects": [
            {
                "name": obj.name,
                "polygons": len(obj.data.polygons),
                "vertices": len(obj.data.vertices),
                "shape_family": obj["shape_family"],
                "component_count": obj["component_count"],
                "individual_fbx": f"individual_fbx/{obj.name}.fbx",
            }
            for obj in objects
        ],
    }
    (destination / "polygon-report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(
        "PANNA_BLENDER_KIT_OK "
        f"objects={len(objects)} min_polygons={min(len(obj.data.polygons) for obj in objects)}"
    )


if __name__ == "__main__":
    main()
