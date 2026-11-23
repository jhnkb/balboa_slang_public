struct BVHNode {
    float3 bbox_min;
    float3 bbox_max;

    // which BVH node we should skip
    // to if this node is totally not
    // intersecting the ray
    // if next_index < 0, then we don't
    // have the next node to skip to
    int next_index;

    uint triangle_begin;
    uint triangle_end;

    bool is_leaf;
};

float point_aabb_distance(float3 x, float3 bmin, float3 bmax) {
    return length(x - clamp(x, bmin, bmax));
}

struct ClosestPoint {
    float3 position;
    float3 bary;
};

// From https://iquilezles.org/articles/distfunctions/
ClosestPoint closest_point_triangle(
        float3 p, float3 a, float3 b, float3 c) {
    float3 ba = b - a, pa = p - a;
    float3 cb = c - b, pb = p - b;
    float3 ac = a - c, pc = p - c;
    float3 nor = cross(ba, ac);

    float t0 = clamp(dot(ba, pa) / dot(ba, ba), 0.0, 1.0);
    float t1 = clamp(dot(cb, pb) / dot(cb, cb), 0.0, 1.0);
    float t2 = clamp(dot(ac, pc) / dot(ac, ac), 0.0, 1.0);

    float3 q0 = a + ba * t0;
    float3 q1 = b + cb * t1;
    float3 q2 = c + ac * t2;

    if (sign(dot(cross(ba, nor), pa)) +
        sign(dot(cross(cb, nor), pb)) +
        sign(dot(cross(ac, nor), pc)) < 2.0) {

        float d0 = dot(p - q0, p - q0);
        float d1 = dot(p - q1, p - q1);
        float d2 = dot(p - q2, p - q2);

        if (d0 < d1 && d0 < d2)
            return {q0, float3(1.0 - t0, t0, 0.0)};
        if (d1 < d2)
            return {q1, float3(0.0, 1.0 - t1, t1)};
        return {q2, float3(t2, 0.0, 1.0 - t2)};
    }

    float inv_nor2 = 1.0 / dot(nor, nor);
    float3 q = p - nor * (dot(nor, pa) * inv_nor2);

    float wb = dot(cross(pa, ac), nor) * inv_nor2;
    float wc = dot(cross(pa, ba), nor) * inv_nor2;
    return {q, float3(1.0 - wb - wc, wb, wc)};
}

float sphere_sdf(float3 point, float3 center, float radius) {
    return length(point - center) - radius;
}

float plane_sdf(float3 point, float4 plane) {
    return dot(plane.xyz, point) - plane.w;
}


[shader("compute")]
[numthreads(64, 1, 1)]
void detect_collision(uint tid : SV_DispatchThreadID,
                      StructuredBuffer<float3> positions,
                      StructuredBuffer<float> inv_masses,
                      StructuredBuffer<float4> planes,
                      StructuredBuffer<float4> spheres,
                      StructuredBuffer<float3> mesh_vertices,
                      StructuredBuffer<float3> mesh_vertex_normals,
                      StructuredBuffer<uint3> mesh_triangles,
                      StructuredBuffer<BVHNode> bvh_nodes,
                      RWStructuredBuffer<float4> contact_planes,
                      uniform uint num_particles,
                      uniform uint num_planes,
                      uniform uint num_spheres,
                      uniform uint num_bvh_nodes,
                      uniform float collision_distance,
                      uniform float contact_margin) {
    if (tid >= num_particles) {
        return;
    }

    if (inv_masses[tid] == 0.0) {
        contact_planes[tid] = float4(0.0);
        return;
    }

    float smallest_sdf = 1e30;
    float4 closest_contact_plane = float4(0.0);
    float3 position = positions[tid];

    //loop through planes first
    for (int i = 0; i < num_planes; i++){
        float4 plane = planes[i];

        float sdf = plane_sdf(position, plane);

        if (sdf < smallest_sdf){
            smallest_sdf = sdf;
            closest_contact_plane = plane;
        }
    }

    //loop through the spheres next
    for (int i = 0; i < num_spheres; i++){
        float4 sphere = spheres[i];
        float3 sphere_center = float3(sphere.x, sphere.y, sphere.z);
        float sphere_radius = sphere.w;

        float3 n = normalize(position - sphere_center);
        float d = dot(n, sphere_center) + sphere_radius;

        float4 tangent_plane = float4(n.x, n.y, n.z, d);
        
        float sdf = sphere_sdf(position, sphere_center, sphere_radius);

        if (sdf < smallest_sdf){
            smallest_sdf = sdf;
            closest_contact_plane = tangent_plane;
        }
    }

    // now handle meshes
    float minimal_distance = contact_margin + collision_distance;
    ClosestPoint closest;
    int triangle_index = -1;
    
    int bvh_index = 0;
    while (bvh_index >= 0 && bvh_index < int(num_bvh_nodes)) {
        BVHNode currNode = bvh_nodes[bvh_index];

        // float point_aabb_distance(float3 x, float3 bmin, float3 bmax)
        float particle_bvh_distance = point_aabb_distance(position,
                                                         currNode.bbox_min,
                                                         currNode.bbox_max);
        
        if (particle_bvh_distance > minimal_distance){
            bvh_index = currNode.next_index;
        } else {
            if (currNode.is_leaf){
                // we compute the distance to all triangles inside that leaf node, and 
                // update our minimal distance

                int first_tri = currNode.triangle_begin;
                int last_tri = currNode.triangle_end;
                
                // loop through the triangles
                for (int i = first_tri; i < last_tri; i++){
                    uint3 tri_indexes = mesh_triangles[i];

                    // get the actual vertex positions
                    float3 p0 = float3(mesh_vertices[tri_indexes[0]]);
                    float3 p1 = float3(mesh_vertices[tri_indexes[1]]);
                    float3 p2 = float3(mesh_vertices[tri_indexes[2]]);

                    // ClosestPoint closest_point_triangle(float3 p, float3 a, float3 b, float3 c)
                    // struct ClosestPoint {
                        //float3 position;
                        //float3 bary;
                    // };
                    ClosestPoint curr_closest = closest_point_triangle(position, p0, p1, p2);

                    //calculate distance from particle to closest point in tri
                    float distance = length(position - curr_closest.position);

                    //update our minimal distance
                    if (distance < minimal_distance){
                        minimal_distance = distance;
                        closest = curr_closest;
                        triangle_index=i;
                    }
                }
            }
            bvh_index++;
        }
    }

    if (triangle_index >= 0) {
        uint3 tri_indexes = mesh_triangles[triangle_index];

        float3 p0 = mesh_vertices[tri_indexes.x];
        float3 p1 = mesh_vertices[tri_indexes.y];
        float3 p2 = mesh_vertices[tri_indexes.z];

        float3 n0 = mesh_vertex_normals[tri_indexes.x];
        float3 n1 = mesh_vertex_normals[tri_indexes.y];
        float3 n2 = mesh_vertex_normals[tri_indexes.z];

        float b0 = closest.bary.x;
        float b1 = closest.bary.y;
        float b2 = closest.bary.z;

        // face normal
        float3 ng = normalize(cross(p1 - p0, p2 - p0));

        // phong normal
        float3 ns = normalize(b0 * n0 + b1 * n1 + b2 * n2);

        if (dot(ng, ns) < 0.0){
            ng = -ng;
        }

        float d = dot(ng, closest.position);
        //use ng as the normal of our contact plane
        float sdf = plane_sdf(position, float4(ng, d));

        if (sdf < smallest_sdf){
            smallest_sdf = sdf;
            closest_contact_plane = float4(ng,d);
        }
    }

    if (smallest_sdf < contact_margin + collision_distance) {
        closest_contact_plane.w += collision_distance;
        contact_planes[tid] = closest_contact_plane;
    } else {
        contact_planes[tid] = float4(0.0);
    }
}
