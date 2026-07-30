#!/usr/bin/env python3
"""Shared detailed BrightBlock asset manifest for Blender and Roblox exports."""

from __future__ import annotations


MIN_POLYGONS = 3_000
DETAIL_REVISION = "DetailedBlocksV2"

PALETTE = {
    "cyan": (0.0, 0.714, 0.808, 1.0),
    "cyan_dark": (0.0, 0.376, 0.471, 1.0),
    "pink": (1.0, 0.130, 0.333, 1.0),
    "pink_dark": (0.573, 0.047, 0.216, 1.0),
    "orange": (1.0, 0.431, 0.094, 1.0),
    "yellow": (1.0, 0.716, 0.041, 1.0),
    "green": (0.124, 0.553, 0.259, 1.0),
    "green_dark": (0.035, 0.286, 0.118, 1.0),
    "blue": (0.031, 0.376, 1.0, 1.0),
    "blue_dark": (0.020, 0.129, 0.420, 1.0),
    "purple": (0.373, 0.153, 0.878, 1.0),
    "white": (0.955, 0.972, 1.0, 1.0),
    "dark": (0.041, 0.055, 0.086, 1.0),
    "concrete": (0.631, 0.682, 0.753, 1.0),
}


def component(
    kind: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    material: str,
    role: str,
) -> dict:
    return {
        "kind": kind,
        "size": size,
        "location": location,
        "material": material,
        "role": role,
    }


C = component


ASSETS = [
    {
        "name": "Court_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (10.8, 6.8, 0.38), (-10, 4, 0.0), "dark", "foundation"),
            C("cube", (10.2, 6.2, 0.20), (-10, 4, 0.29), "green_dark", "field_base"),
            C("cube", (9.5, 5.5, 0.12), (-10, 4, 0.45), "green", "field_inlay"),
            C("cube", (9.5, 0.12, 0.08), (-10, 1.25, 0.55), "white", "touch_line_south"),
            C("cube", (9.5, 0.12, 0.08), (-10, 6.75, 0.55), "white", "touch_line_north"),
            C("cube", (0.12, 5.5, 0.08), (-14.75, 4, 0.55), "white", "goal_line_west"),
            C("cube", (0.12, 5.5, 0.08), (-5.25, 4, 0.55), "white", "goal_line_east"),
            C("cube", (0.10, 5.5, 0.08), (-10, 4, 0.55), "yellow", "center_line"),
            C("wedge", (0.85, 0.85, 0.22), (-14.30, 1.68, 0.62), "cyan", "corner_marker"),
            C("wedge", (0.85, 0.85, 0.22), (-5.70, 6.32, 0.62), "pink", "corner_marker"),
        ],
    },
    {
        "name": "Goal_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (0.42, 0.42, 4.7), (-3.7, -2, 2.35), "white", "left_post"),
            C("cube", (0.42, 0.42, 4.7), (3.7, -2, 2.35), "white", "right_post"),
            C("cube", (7.82, 0.42, 0.42), (0, -2, 4.48), "white", "crossbar"),
            C("cube", (0.32, 1.8, 0.32), (-3.7, -1.1, 0.35), "blue", "left_depth_rail"),
            C("cube", (0.32, 1.8, 0.32), (3.7, -1.1, 0.35), "pink", "right_depth_rail"),
            C("cube", (7.72, 0.28, 0.28), (0, -0.2, 0.28), "concrete", "rear_floor_rail"),
            C("cube", (7.72, 0.24, 0.24), (0, -0.2, 4.38), "concrete", "rear_top_rail"),
            C("cube", (0.18, 1.7, 4.0), (-3.68, -1.08, 2.25), "cyan", "left_net_frame"),
            C("cube", (0.18, 1.7, 4.0), (3.68, -1.08, 2.25), "cyan", "right_net_frame"),
            C("cube", (0.16, 1.7, 4.0), (-1.85, -1.08, 2.25), "concrete", "net_band"),
            C("cube", (0.16, 1.7, 4.0), (0, -1.08, 2.25), "concrete", "net_band"),
            C("cube", (0.16, 1.7, 4.0), (1.85, -1.08, 2.25), "concrete", "net_band"),
            C("cube", (1.20, 1.0, 0.26), (-3.7, -1.45, 0.13), "yellow", "left_foot"),
            C("cube", (1.20, 1.0, 0.26), (3.7, -1.45, 0.13), "yellow", "right_foot"),
        ],
    },
    {
        "name": "Barrier_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (9.2, 0.62, 2.2), (10, 4, 1.25), "cyan", "main_panel"),
            C("cube", (9.6, 0.9, 0.28), (10, 4, 0.14), "dark", "base"),
            C("cube", (9.5, 0.78, 0.30), (10, 4, 2.48), "cyan_dark", "top_rail"),
            C("cube", (0.30, 0.82, 2.7), (6.0, 4, 1.35), "white", "rib"),
            C("cube", (0.30, 0.82, 2.7), (8.0, 4, 1.35), "white", "rib"),
            C("cube", (0.30, 0.82, 2.7), (10.0, 4, 1.35), "white", "rib"),
            C("cube", (0.30, 0.82, 2.7), (12.0, 4, 1.35), "white", "rib"),
            C("cube", (0.30, 0.82, 2.7), (14.0, 4, 1.35), "white", "rib"),
            C("wedge", (1.35, 0.35, 0.75), (8.0, 3.63, 1.35), "yellow", "chevron"),
            C("wedge", (1.35, 0.35, 0.75), (11.9, 3.63, 1.35), "pink", "chevron"),
        ],
    },
    {
        "name": "Bench_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (6.8, 0.52, 0.34), (-9, -5.45, 1.55), "pink", "seat_slat"),
            C("cube", (6.8, 0.52, 0.34), (-9, -4.90, 1.55), "pink", "seat_slat"),
            C("cube", (6.8, 0.30, 0.42), (-9, -4.48, 2.15), "pink_dark", "back_slat"),
            C("cube", (6.8, 0.30, 0.42), (-9, -4.48, 2.72), "pink", "back_slat"),
            C("cube", (6.8, 0.30, 0.42), (-9, -4.48, 3.29), "pink_dark", "back_slat"),
            C("cube", (0.46, 1.05, 1.5), (-11.7, -5.15, 0.76), "dark", "leg"),
            C("cube", (0.46, 1.05, 1.5), (-6.3, -5.15, 0.76), "dark", "leg"),
            C("cube", (0.36, 0.36, 2.6), (-11.7, -4.56, 2.15), "concrete", "back_support"),
            C("cube", (0.36, 0.36, 2.6), (-6.3, -4.56, 2.15), "concrete", "back_support"),
            C("wedge", (0.8, 1.7, 1.25), (-12.05, -5.05, 1.05), "yellow", "side_accent"),
            C("wedge", (0.8, 1.7, 1.25), (-5.95, -5.05, 1.05), "cyan", "side_accent"),
        ],
    },
    {
        "name": "QueueGate_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (0.68, 0.68, 5.9), (6.8, -4.5, 2.95), "purple", "left_post"),
            C("cube", (0.68, 0.68, 5.9), (12.2, -4.5, 2.95), "purple", "right_post"),
            C("cube", (6.1, 0.68, 0.62), (9.5, -4.5, 5.55), "purple", "top_beam"),
            C("cube", (4.9, 0.35, 1.35), (9.5, -4.15, 4.65), "dark", "header"),
            C("cube", (0.88, 0.88, 0.32), (6.8, -4.5, 0.16), "yellow", "left_foot"),
            C("cube", (0.88, 0.88, 0.32), (12.2, -4.5, 0.16), "yellow", "right_foot"),
            C("cube", (0.84, 0.76, 0.40), (6.8, -4.5, 1.45), "cyan", "left_band"),
            C("cube", (0.84, 0.76, 0.40), (12.2, -4.5, 1.45), "pink", "right_band"),
            C("cube", (0.84, 0.76, 0.40), (6.8, -4.5, 3.65), "pink", "left_band"),
            C("cube", (0.84, 0.76, 0.40), (12.2, -4.5, 3.65), "cyan", "right_band"),
            C("wedge", (1.55, 0.38, 0.95), (9.5, -3.94, 4.65), "yellow", "direction_icon"),
        ],
    },
    {
        "name": "Lamp_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (1.25, 1.25, 0.35), (-1, 4, 0.18), "dark", "base"),
            C("cube", (0.55, 0.55, 2.2), (-1, 4, 1.30), "concrete", "lower_post"),
            C("cube", (0.42, 0.42, 2.2), (-1, 4, 3.50), "yellow", "middle_post"),
            C("cube", (0.34, 0.34, 1.55), (-1, 4, 5.35), "dark", "upper_post"),
            C("cube", (4.1, 0.45, 0.36), (-1, 4, 6.25), "dark", "crossbar"),
            C("cube", (1.55, 1.05, 0.36), (-2.45, 4, 6.02), "yellow", "left_light"),
            C("cube", (1.55, 1.05, 0.36), (0.45, 4, 6.02), "yellow", "right_light"),
            C("cube", (0.22, 0.22, 1.0), (-2.45, 4, 5.52), "cyan", "left_support"),
            C("cube", (0.22, 0.22, 1.0), (0.45, 4, 5.52), "pink", "right_support"),
            C("wedge", (1.8, 1.25, 0.48), (-2.45, 4, 6.34), "cyan", "left_hood"),
            C("wedge", (1.8, 1.25, 0.48), (0.45, 4, 6.34), "pink", "right_hood"),
        ],
    },
    {
        "name": "Direction_Triangle",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("wedge", (5.6, 2.5, 3.5), (0, -4, 1.75), "yellow", "main_arrow"),
            C("wedge", (4.3, 2.68, 2.45), (0, -4, 1.95), "orange", "inset_arrow"),
            C("cube", (2.7, 2.1, 0.32), (-2.7, -4, 0.18), "dark", "tail_base"),
            C("cube", (2.1, 1.3, 0.22), (-2.7, -4, 0.46), "white", "tail_inlay"),
            C("wedge", (1.25, 2.75, 1.15), (-1.75, -4, 0.95), "cyan", "left_fin"),
            C("wedge", (1.25, 2.75, 1.15), (1.75, -4, 0.95), "pink", "right_fin"),
        ],
    },
    {
        "name": "ArenaMarker_Triangle",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (4.4, 2.7, 0.36), (15, -3.5, 0.18), "dark", "marker_base"),
            C("wedge", (3.8, 2.1, 5.5), (15, -3.5, 2.93), "blue", "main_marker"),
            C("wedge", (2.8, 2.28, 3.8), (15, -3.5, 3.10), "blue_dark", "inset_marker"),
            C("cube", (0.34, 2.5, 5.9), (13.25, -3.5, 3.0), "white", "edge_spine"),
            C("cube", (2.1, 0.34, 0.34), (14.1, -3.5, 5.75), "yellow", "top_flag"),
            C("cube", (2.1, 0.34, 0.34), (14.1, -3.5, 1.05), "cyan", "lower_flag"),
        ],
    },
    {
        "name": "Podium_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (3.5, 3.5, 1.0), (-1, 7, 0.5), "concrete", "second_step"),
            C("cube", (3.5, 3.5, 1.8), (2.5, 7, 0.9), "white", "first_step"),
            C("cube", (3.5, 3.5, 0.7), (6, 7, 0.35), "concrete", "third_step"),
            C("cube", (3.7, 3.7, 0.16), (-1, 7, 1.08), "cyan", "second_trim"),
            C("cube", (3.7, 3.7, 0.16), (2.5, 7, 1.88), "yellow", "first_trim"),
            C("cube", (3.7, 3.7, 0.16), (6, 7, 0.78), "pink", "third_trim"),
            C("cube", (1.2, 0.20, 0.22), (-1, 5.22, 0.62), "dark", "number_two_top"),
            C("cube", (1.2, 0.20, 0.22), (-1, 5.22, 0.25), "dark", "number_two_bottom"),
            C("cube", (0.20, 0.20, 0.72), (2.5, 5.22, 0.95), "dark", "number_one"),
            C("cube", (1.2, 0.20, 0.22), (6, 5.22, 0.44), "dark", "number_three"),
            C("wedge", (0.8, 0.8, 0.7), (2.5, 7, 2.3), "yellow", "winner_marker"),
        ],
    },
    {
        "name": "Sign_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (8.2, 0.62, 3.2), (-10, 10, 2.5), "dark", "sign_face"),
            C("cube", (8.8, 0.82, 0.30), (-10, 10, 4.22), "cyan", "top_frame"),
            C("cube", (8.8, 0.82, 0.30), (-10, 10, 0.78), "pink", "bottom_frame"),
            C("cube", (0.30, 0.82, 3.7), (-14.25, 10, 2.5), "cyan", "left_frame"),
            C("cube", (0.30, 0.82, 3.7), (-5.75, 10, 2.5), "pink", "right_frame"),
            C("cube", (0.42, 0.42, 2.3), (-12.4, 10, 0.0), "concrete", "left_post"),
            C("cube", (0.42, 0.42, 2.3), (-7.6, 10, 0.0), "concrete", "right_post"),
            C("cube", (5.4, 0.72, 0.42), (-10.6, 9.62, 2.85), "white", "title_bar"),
            C("cube", (3.8, 0.72, 0.28), (-11.4, 9.62, 1.85), "yellow", "detail_bar"),
            C("cube", (2.0, 0.72, 0.28), (-8.1, 9.62, 1.85), "cyan", "detail_bar"),
            C("wedge", (1.3, 0.95, 1.15), (-6.65, 9.55, 3.25), "yellow", "corner_badge"),
        ],
    },
    {
        "name": "Trophy_Triangle",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (5.2, 3.6, 0.42), (10, 9, 0.21), "dark", "trophy_base"),
            C("cube", (3.5, 2.4, 0.55), (10, 9, 0.69), "concrete", "pedestal"),
            C("wedge", (4.6, 2.9, 4.8), (10, 9, 3.05), "pink", "main_trophy"),
            C("wedge", (3.2, 3.05, 3.2), (10, 9, 3.20), "pink_dark", "trophy_inset"),
            C("cube", (0.38, 0.38, 2.4), (8.5, 9, 5.7), "yellow", "left_prong"),
            C("cube", (0.38, 0.38, 2.4), (11.5, 9, 5.7), "yellow", "right_prong"),
            C("cube", (3.4, 0.38, 0.38), (10, 9, 6.72), "yellow", "crown_bar"),
            C("cube", (1.2, 0.32, 1.7), (7.85, 9, 3.7), "cyan", "left_handle"),
            C("cube", (1.2, 0.32, 1.7), (12.15, 9, 3.7), "cyan", "right_handle"),
            C("wedge", (1.1, 2.7, 1.0), (10, 9, 6.9), "white", "crown_point"),
        ],
    },
    {
        "name": "Display_Base_Block",
        "shape_family": "cube_rectangle_triangle",
        "components": [
            C("cube", (34, 25, 0.38), (1, 2, -0.42), "white", "display_floor"),
            C("cube", (34.6, 0.42, 0.46), (1, -10.25, -0.18), "cyan", "south_border"),
            C("cube", (34.6, 0.42, 0.46), (1, 14.25, -0.18), "pink", "north_border"),
            C("cube", (0.42, 25, 0.46), (-16.25, 2, -0.18), "yellow", "west_border"),
            C("cube", (0.42, 25, 0.46), (18.25, 2, -0.18), "purple", "east_border"),
            C("cube", (9.0, 0.18, 0.08), (-9, -8, 0.02), "cyan", "floor_detail"),
            C("cube", (7.0, 0.18, 0.08), (11, 12, 0.02), "pink", "floor_detail"),
            C("wedge", (2.2, 2.2, 0.35), (-14.6, -8.6, 0.05), "yellow", "corner_detail"),
            C("wedge", (2.2, 2.2, 0.35), (16.6, 12.6, 0.05), "purple", "corner_detail"),
        ],
    },
]


def component_count() -> int:
    return sum(len(asset["components"]) for asset in ASSETS)
