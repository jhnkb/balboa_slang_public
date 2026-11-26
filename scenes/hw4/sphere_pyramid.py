import numpy as np

from scenes.hw4.geometry import (
    make_cloth_grid,
    make_cloth_constraints
)

def make_scene():

    # snowman balls
    # body
    # midsection
    # head
    spheres = np.array([
        # Bottom row
        [-1.0, 0.5, 0.0, 0.5],
        [ 0.0, 0.5, 0.0, 0.5],
        [ 1.0, 0.5, 0.0, 0.5],

        # Middle row
        [-0.5, 1.366, 0.0, 0.5],
        [ 0.5, 1.366, 0.0, 0.5],

        # Top
        [ 0.0, 2.232, 0.0, 0.5],
    ], dtype=np.float32)

    # the blanket
    nx, ny = 60, 60
    sx, sy = 4.0, 4.0

    positions, triangles, dx, dy = make_cloth_grid(
        nx, ny, sx, sy
    )

    # blanket above snowman
    positions[:, 1] = 3.2

    # spring constraints
    edges, rest_lengths = make_cloth_constraints(
        nx, ny, dx, dy
    )

    # initital velocity
    velocities = np.zeros_like(positions)

    # 
    return {
        'positions': positions,
        'velocities': velocities,
        'inv_masses': np.ones(len(positions), dtype=np.float32),
        'constraint_edges': np.array(edges, dtype=np.uint32),
        'rest_lengths': np.array(rest_lengths, dtype=np.float32),
        'triangles': triangles,
        'cloth_grid_size': (nx, ny),
        'spacing': (dx, dy),

        'planes': np.array([
            [0, 1, 0, 0.0],
        ], dtype=np.float32),
        'spheres': spheres,

        'collision_distance': 0.02,
        'contact_margin': 0.05,
        'static_friction': 0.45,
        'kinetic_friction': 0.30,

        'substeps': 8,
        'iterations': 20,

        'cam_pos': (0.0, 2.0, -6.0),
        'cam_target': (0.0, 1.4, 0.0),
        'cam_up': (0.0, 1.0, 0.0),
    }