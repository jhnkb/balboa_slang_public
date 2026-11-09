import json
import numpy as np
import buffer
import math
import os
import slangpy as spy
import trimesh

SPHERE = 0  # Must match Slang's ShapeType in hw3_common.slang
TRIANGLE_MESH = 1

def parse_triangle_mesh(filename):
    if filename.lower().endswith('.ply'):
        mesh = trimesh.load_mesh(filename, process=False)

        vertices = np.asarray(mesh.vertices, dtype=np.float32)
        faces = np.asarray(mesh.faces, dtype=np.uint32)
        vertex_normals = np.asarray(
            mesh.vertex_normals, dtype=np.float32)

    else:
        with open(filename) as f:
            mesh = json.load(f)

        vertices = np.array(mesh['vertices'], dtype=np.float32)
        faces = np.array(mesh['faces'], dtype=np.uint32)

        if 'vertex_normals' in mesh:
            vertex_normals = np.array(
                mesh['vertex_normals'], dtype=np.float32)
        else:
            # Generate smooth vertex normals.
            tri_mesh = trimesh.Trimesh(
                vertices=vertices,
                faces=faces,
                process=False)
            vertex_normals = np.asarray(
                tri_mesh.vertex_normals, dtype=np.float32)

    return vertices, faces, vertex_normals

def compose_transformations(transformations):
    """
        Given a list of transformations, compose them into a matrix.
    """
    F = np.eye(4, dtype=np.float32)

    for transform in transformations:
        # HW 2.3 TODO: your code here

        if "scale" in transform:
            scale_val = transform["scale"]

            scale_x = scale_val[0]
            scale_y = scale_val[1]
            scale_z = scale_val[2]

            S = np.array([[scale_x, 0, 0, 0],
                         [0, scale_y, 0, 0],
                         [0, 0, scale_z, 0],
                         [0, 0, 0, 1]], dtype=np.float32)

            F = S @ F
        elif "translate" in transform:
            t_vals = transform["translate"]

            t_x = t_vals[0]
            t_y = t_vals[1]
            t_z = t_vals[2]

            T = np.array([[1, 0, 0, t_x],
                         [0, 1, 0, t_y],
                         [0, 0, 1, t_z],
                         [0, 0, 0, 1]], dtype=np.float32)

            F = T @ F
        elif "rotate_x" in transform:
            rotation_vals = transform["rotate_x"]

            degree = rotation_vals[0]
            radian = math.radians(degree)

            sin = math.sin(radian)
            cos = math.cos(radian)

            R = np.array([[1, 0, 0, 0],
                         [0, cos, -sin, 0],
                         [0, sin, cos, 0],
                         [0, 0, 0, 1]], dtype=np.float32)
            F = R @ F
        elif "rotate_y" in transform:
            rotation_vals = transform["rotate_y"]

            degree = rotation_vals[0]
            radian = math.radians(degree)

            sin = math.sin(radian)
            cos = math.cos(radian)

            R = np.array([[cos, 0, sin, 0],
                         [0, 1, 0, 0],
                         [-sin, 0, cos, 0],
                         [0, 0, 0, 1]], dtype=np.float32)
            F = R @ F
        elif "rotate_z" in transform:
            rotation_vals = transform["rotate_z"]

            degree = rotation_vals[0]
            radian = math.radians(degree)

            sin = math.sin(radian)
            cos = math.cos(radian)

            R = np.array([[cos, -sin, 0, 0],
                         [sin, cos, 0, 0],
                         [0, 0, 1, 0],
                         [0, 0, 0, 1]], dtype=np.float32)
            F = R @ F   
        elif "lookat" in transform:
            position = transform["lookat"]["position"]
            target =transform["lookat"]["target"]
            up =transform["lookat"]["up"]

            p = np.array(position, dtype=float)
            t = np.array(target, dtype=float)
            u = np.array(up, dtype=float)

            d = t - p
            #normalize distance
            d = d / np.linalg.norm(d)

            r = np.cross(d, u)
            r = r / np.linalg.norm(r)

            u_p = np.cross(r,d)

            L = np.array([[r[0], u_p[0], -d[0], p[0]],
                          [r[1], u_p[1], -d[1], p[1]],
                          [r[2], u_p[2], -d[2], p[2]],
                          [0, 0, 0, 1]], dtype=np.float32)

            F = L @ F
    return F

def interpolate_transformation(transform_keyframes, t):
    # HW 2.4: implement this
    # Find the two keyframes surrounding t and linearly
    # interpolate the corresponding transformation parameters.
    #
    # Return a list of transformations in the same format
    # as the "transform" field in the scene JSON.

    # this is to check if there exists keyframes,
    # if it does not then return an empty list.
    if transform_keyframes == []:
        return []

    interp_transforms = []

    t_leftneighbor = float("-inf")
    t_rightneighbor = float("inf")

    leftneighbor = None
    rightneighbor = None

    for keyframe in transform_keyframes:
        t_keyframe = keyframe["time"]

        if t_keyframe <= t and t_leftneighbor < t_keyframe:
            t_leftneighbor = t_keyframe
            leftneighbor = keyframe
        if t_keyframe >= t and t_rightneighbor > t_keyframe:
            t_rightneighbor = t_keyframe
            rightneighbor = keyframe

    if t_leftneighbor == t_rightneighbor:
        return rightneighbor["transform"]

    if leftneighbor is None:
        return rightneighbor["transform"]

    if rightneighbor is None:
        return leftneighbor["transform"]

    t_0 = t_leftneighbor
    t_1 = t_rightneighbor
    w = (t-t_0)/(t_1-t_0)

    #gets a list of dictionaries
    left_transform = leftneighbor["transform"]
    right_transform = rightneighbor["transform"]

    #go through the list of dictionaries one by one at the same time
    for left_item, right_item in zip(left_transform, right_transform):
        new_transform = dict()

        ##### SCALING #####
        if "scale" in left_item and "scale" in right_item:
            
            left_scale_vals = np.array(left_item["scale"])
            right_scale_vals = np.array(right_item["scale"])

            new_scale = (1-w)*left_scale_vals + w*right_scale_vals
            new_scale = new_scale.tolist()

            new_transform["scale"] = new_scale

        ##### TRANSLATRION #####
        elif "translate" in left_item and "translate" in right_item:

            left_translate_vals = np.array(left_item["translate"])
            right_translate_vals = np.array(right_item["translate"])

            new_translate = (1-w)*left_translate_vals + w*right_translate_vals
            new_translate = new_translate.tolist()

            new_transform["translate"] = new_translate

        ##### ROTATEX ######
        elif "rotate_x" in left_item and "rotate_x" in right_item:
            left_rotate_val_degree = left_item["rotate_x"][0]
            right_rotate_val_degree = right_item["rotate_x"][0]

            rotations = []
            new_rotate = (1-w)*left_rotate_val_degree + w*right_rotate_val_degree
            rotations.append(new_rotate)

            new_transform["rotate_x"] = rotations

        ##### ROTATEY ######
        elif "rotate_y" in left_item and "rotate_y" in right_item:
            left_rotate_val_degree = left_item["rotate_y"][0]
            right_rotate_val_degree = right_item["rotate_y"][0]

            rotations = []
            new_rotate = (1-w)*left_rotate_val_degree + w*right_rotate_val_degree
            rotations.append(new_rotate)

            new_transform["rotate_y"] = rotations      

        ##### ROTATEZ ######
        elif "rotate_z" in left_item and "rotate_z" in right_item:
            left_rotate_val_degree = left_item["rotate_z"][0]
            right_rotate_val_degree = right_item["rotate_z"][0]

            rotations = []
            new_rotate = (1-w)*left_rotate_val_degree + w*right_rotate_val_degree
            rotations.append(new_rotate)

            new_transform["rotate_z"] = rotations

        ##### LOOKAT #####
        elif "lookat" in left_item and "lookat" in right_item:
            left_position = np.array(left_item["lookat"]["position"])
            left_target = np.array(left_item["lookat"]["target"])
            left_up = np.array(left_item["lookat"]["up"])

            right_position = np.array(right_item["lookat"]["position"])
            right_target = np.array(right_item["lookat"]["target"])
            right_up = np.array(right_item["lookat"]["up"])

            new_position = (1-w)*left_position + w*right_position
            new_target = (1-w)*left_target + w*right_target
            new_up = (1-w)*left_up + w*right_up

            new_position = list(new_position)
            new_target = list(new_target)
            new_up = list(new_up)

            new_transform["lookat"] = {
                "position": new_position,
                "target": new_target,
                "up": new_up
            }

        if new_transform:
            interp_transforms.append(new_transform)

    return interp_transforms

def get_transformation(obj, t):
    transforms = obj.get('transform', [])
    if 'transform_keyframes' in obj:
        transforms = interpolate_transformation(
            obj['transform_keyframes'], t)
    return compose_transformations(transforms)

def build_bvh(vertices, faces, triangle_offset, bvh_nodes):
    # A recursive BVH builder that split the longest axis
    # using the median of the centroids. The leaf nodes
    # have maximum of 4 triangles.

    assert(len(faces) > 0)
    # Needs a copy because we will sort them during the recursion
    faces = faces.copy()
    centers = vertices[faces].mean(axis=1)

    def build(begin, end):
        node_id = len(bvh_nodes)
        # Important: append a node first
        # before the recursion, so that the order
        # is "preorder" 
        bvh_nodes.append(None)

        # Bounding box of all triangles in this node
        points = vertices[faces[begin:end]].reshape(-1, 3)
        bbox_min = points.min(axis=0)
        bbox_max = points.max(axis=0)

        # Stop recursion if the node has fewer than 4 triangles
        is_leaf = end - begin <= 4
        if not is_leaf:
            # Find the longest axis
            c = centers[begin:end]
            axis = np.argmax(c.max(axis=0) - c.min(axis=0))

            # Sort triangles by their centroids
            order = np.argsort(c[:, axis])
            faces[begin:end] = faces[begin:end][order]
            centers[begin:end] = c[order]

            # Split
            mid = (begin + end) // 2
            build(begin, mid)
            build(mid, end)

        bvh_nodes[node_id] = {
            'bbox_min': bbox_min,
            'bbox_max': bbox_max,
            'next_index': len(bvh_nodes),
            'triangle_begin': triangle_offset + begin,
            'triangle_end': triangle_offset + end,
            'is_leaf': is_leaf
        }

        return node_id

    root = build(0, len(faces))
    return root, faces

def upload_scene(filename, module, slang_device, use_bvh = False):
    with open(filename) as f:
        scene = json.load(f)

    background = scene.get('background', (0.5, 0.5, 0.5))

    camera = {'cam_to_world': np.eye(4, dtype=np.float32),
              'fov_x': 90.0}

    if 'camera' in scene:
        camera['cam_to_world'] = \
            get_transformation(scene['camera'], 0.0)
        camera['fov_x'] = scene['camera'].get('fov_x', 90.0)

    # Triangle meshes loading + BVH building
    mesh_descs = []
    vertices_list = []
    normals_list = []
    triangles_list = []
    bvh_nodes = []

    vertex_offset = 0
    triangle_offset = 0

    scene_dir = os.path.dirname(filename)

    for mesh_data in scene.get('meshes', []):
        mesh_filename = os.path.join(
            scene_dir, mesh_data['filename'])
        vertices, faces, vertex_normals = \
            parse_triangle_mesh(mesh_filename)

        # Construct the BVH and reorder triangles
        # The returned faces is a copy of our
        # original faces.
        if use_bvh:
            bvh_root_index, faces = build_bvh(
                vertices, faces, triangle_offset, bvh_nodes)
        else:
            bvh_root_index = 0

        mesh_descs.append({
            'vertex_offset': vertex_offset,
            'triangle_begin': triangle_offset,
            'triangle_end': triangle_offset + len(faces),
            'bvh_root_index': bvh_root_index
        })

        vertices_list.append(vertices)
        normals_list.append(vertex_normals)
        triangles_list.append(faces)

        vertex_offset += len(vertices)
        triangle_offset += len(faces)

    # Merge into global arrays
    if len(mesh_descs) > 0:
        vertices = np.concatenate(vertices_list).astype(np.float32)
        normals = np.concatenate(normals_list).astype(np.float32)
        triangles = np.concatenate(triangles_list).astype(np.uint32)
    else:
        # Use dummy entries if the scene has no meshes
        vertices = np.zeros((1, 3), dtype=np.float32)
        normals = np.zeros((1, 3), dtype=np.float32)
        triangles = np.zeros((1, 3), dtype=np.uint32)

    # Parse object instances.
    spheres = []
    shapes = []

    for obj in scene['objects']:
        if obj['type'] == 'sphere':
            shape_type = SPHERE
            shape_index = len(spheres)
            spheres.append({
                'center': obj['center'],
                'radius': obj['radius']
            })
        elif obj['type'] == 'mesh':
            shape_type = TRIANGLE_MESH
            shape_index = obj['index']
        else:
            raise ValueError(f"Unknown shape type: {obj['type']}")

        obj_to_world = get_transformation(obj, 0.0)
        world_to_obj = np.linalg.inv(obj_to_world)

        shapes.append({
            'type': shape_type,
            'index': shape_index,
            'Kd': obj['Kd'],
            'Kr': obj['Kr'],
            'world_to_obj': world_to_obj,
            'obj_to_world': obj_to_world
        })

    lights = scene['lights']

    max_depth = scene.get('max_depth', 20)

    bindings = {
        'background': spy.float3(background),
        'camera': camera,
        'shapes': buffer.create_structured_buffer(
            slang_device, module.Shape, shapes),
        'num_shapes': len(shapes),
        'spheres': buffer.create_structured_buffer(
            slang_device, module.Sphere, spheres),
        'meshes': buffer.create_structured_buffer(
            slang_device, module.TriangleMesh, mesh_descs),
        'vertices': buffer.structured_typed_buffer_from_numpy(
            slang_device, vertices, 'float3'),
        'vertex_normals': buffer.structured_typed_buffer_from_numpy(
            slang_device, normals, 'float3'),
        'triangles': buffer.structured_typed_buffer_from_numpy(
            slang_device, triangles, 'uint3'),
        'bvh_nodes': buffer.create_structured_buffer(
            slang_device, module.BVHNode, bvh_nodes),
        'lights': buffer.create_structured_buffer(
            slang_device, module.PointLight, lights),
        'num_lights': len(lights),
        'max_depth': max_depth
    }

    return bindings, scene, shapes
