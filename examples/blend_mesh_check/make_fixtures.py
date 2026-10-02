"""Builds meshes.blend and the reference Blender itself computes for it: loop triangles and corner normals.

Run with Blender 5.2:
    blender -b --factory-startup --python make_fixtures.py
Dump the reference of another file (its mesh objects, as saved, or the ones named) instead:
    blender -b --factory-startup <file.blend> --python make_fixtures.py -- --reference=<file.json> [--object=<name>]
"""
import bpy
import bmesh
import json
import math
import os
import random
import sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")


def polygon_object(name, points, rotation=None):
    mesh = bpy.data.meshes.new(name)
    vertices = [Vector((x, y, 0.0)) for x, y in points]
    if rotation is not None:
        vertices = [rotation @ v for v in vertices]
    mesh.from_pydata([v[:] for v in vertices], [], [list(range(len(points)))])
    mesh.update()
    return link(name, mesh)


def faces_object(name, vertices, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    return link(name, mesh)


def link(name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bmesh_object(name, build):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(mesh)
    bm.free()
    return link(name, mesh)


def star(points, outer, inner):
    out = []
    for i in range(points * 2):
        angle = math.pi * i / points
        radius = outer if i % 2 == 0 else inner
        out.append((radius * math.cos(angle), radius * math.sin(angle)))
    return out


def comb(teeth):
    out = [(0.0, 0.0), (teeth * 2.0, 0.0)]
    for t in range(teeth - 1, 0, -1):
        x = t * 2.0
        out += [(x + 2.0, 3.0), (x + 1.0, 3.0), (x + 1.0, 1.0), (x, 1.0)]
    # The last tooth's top edge keeps a collinear point.
    out += [(2.0, 3.0), (1.0, 3.0), (0.0, 3.0)]
    return out


def build_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(7)
    polygon_object("L", [(0, 0), (3, 0), (3, 1), (1, 1), (1, 3), (0, 3)])
    polygon_object("U", [(0, 0), (3, 0), (3, 3), (2, 3), (2, 1), (1, 1), (1, 3), (0, 3)])
    tilt = (Matrix.Rotation(0.6, 3, 'X') @ Matrix.Rotation(-0.4, 3, 'Y'))
    polygon_object("Star", star(7, 2.0, 0.8), tilt)
    polygon_object("Collinear", [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2), (2, 2), (1.5, 1), (1, 2), (0, 2), (0, 1)])
    polygon_object("Comb", comb(4))
    polygon_object("Spiral", [(0, 0), (4, 0), (4, 4), (1, 4), (1, 2), (2, 2), (2, 3), (3, 3), (3, 1), (0, 1)],
                   Matrix.Rotation(2.0, 3, 'Z') @ Matrix.Rotation(1.2, 3, 'X'))
    faces_object("Quads",
                 [(0, 0, 0), (2, 1, 0), (0, 2, 0), (0.5, 1, 0), (3, 0, 0), (4, 0, 0.5), (4, 1, 0), (3, 1, 0.5),
                  (5, 0, 0), (6, 0, 0), (5.5, 1, 0)],
                 [[0, 1, 2, 3], [3, 0, 1, 2], [4, 5, 6, 7], [8, 9, 10]])

    def sphere(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=1.0)
        for face in bm.faces:
            face.smooth = True
    smooth = bmesh_object("Smooth", sphere)
    smooth.location = (0, 0, 0)

    def sharp_sphere(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=7, radius=1.0)
        for face in bm.faces:
            face.smooth = True
        for i, edge in enumerate(bm.edges):
            if i % 5 == 0:
                edge.smooth = False
        for i, face in enumerate(bm.faces):
            if i % 9 == 0:
                face.smooth = False
    bmesh_object("SharpEdges", sharp_sphere)

    def rounded_cube(bm):
        bmesh.ops.create_cube(bm, size=2.0)
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
        for face in bm.faces:
            face.smooth = True
    custom = bmesh_object("Custom", rounded_cube)
    set_random_custom_normals(custom.data)

    def bevelled(bm):
        bmesh.ops.create_cube(bm, size=2.0)
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=0.2, segments=2, affect='EDGES')
        for face in bm.faces:
            face.smooth = True
    source = bmesh_object("WeightedSource", bevelled)
    modifier = source.modifiers.new("Weighted", 'WEIGHTED_NORMAL')
    modifier.keep_sharp = True
    graph = bpy.context.evaluated_depsgraph_get()
    weighted_mesh = bpy.data.meshes.new_from_object(source.evaluated_get(graph))
    weighted_mesh.name = "Weighted"
    bpy.data.objects.remove(source)
    link("Weighted", weighted_mesh)

    free = bmesh_object("Free", rounded_cube)
    corner_count = len(free.data.loops)
    attribute = free.data.attributes.new("custom_normal", 'FLOAT_VECTOR', 'CORNER')
    values = []
    for i in range(corner_count):
        values += [random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(0.2, 2.0)]
    attribute.data.foreach_set("vector", values)

    scaled = bmesh_object("Scaled", rounded_cube)
    set_random_custom_normals(scaled.data)
    scaled.location = (1.0, -2.0, 0.5)
    scaled.rotation_euler = (0.3, -0.7, 1.1)
    scaled.scale = (2.0, 0.5, 1.25)

    bpy.context.view_layer.update()
    target = os.path.join(FIXTURES, "meshes.blend")
    if os.path.exists(target):
        os.remove(target)
    bpy.ops.wm.save_as_mainfile(filepath=target, compress=True)
    dump(os.path.join(FIXTURES, "reference.json"), [o.name for o in bpy.data.objects if o.type == 'MESH'])


def set_random_custom_normals(mesh):
    mesh.update()
    normals = []
    for corner in mesh.loops:
        normals.append(Vector((random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4))))
    for polygon in mesh.polygons:
        for corner in polygon.loop_indices:
            normals[corner] = (normals[corner] + polygon.normal).normalized()
    mesh.normals_split_custom_set(normals)
    mesh.update()


def rounded(vector):
    return [round(value, 6) for value in vector]


def dump(path, names):
    meshes = []
    for name in sorted(names):
        obj = bpy.data.objects[name]
        mesh = obj.data
        world = obj.matrix_world
        normal_matrix = world.inverted_safe().transposed().to_3x3()
        corners = []
        normals = []
        mesh_normals = mesh.corner_normals
        for triangle in mesh.loop_triangles:
            for corner in triangle.loops:
                vertex = mesh.loops[corner].vertex_index
                corners += rounded(world @ mesh.vertices[vertex].co)
                normals += rounded((normal_matrix @ mesh_normals[corner].vector).normalized())
        meshes.append({"name": name, "domain": mesh.normals_domain, "corners": corners, "normals": normals})
    with open(path, "w") as out:
        json.dump({"meshes": meshes}, out)
    print("wrote", path, len(meshes), "meshes")


if "--" in sys.argv:
    arguments = sys.argv[sys.argv.index("--") + 1:]
    reference = [a.split("=", 1)[1] for a in arguments if a.startswith("--reference=")]
    chosen = [a.split("=", 1)[1] for a in arguments if a.startswith("--object=")]
    dump(reference[0], chosen or [o.name for o in bpy.data.objects if o.type == 'MESH'])
else:
    build_scene()
