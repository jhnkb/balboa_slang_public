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
                      // Plane stores (a, b, c, d) where ax+by+cz=d
                      // a, b, c are normalized to a unit 3D vector
                      StructuredBuffer<float4> planes,
                      // Sphere stores center (xyz) + radius (w)
                      StructuredBuffer<float4> spheres,
                      // Contact plane: dot(n, x) = d, with unit normal n
                      // Set to (0, 0, 0, 0) if there is no contact
                      RWStructuredBuffer<float4> contact_planes,
                      uniform uint num_particles,
                      uniform uint num_planes,
                      uniform uint num_spheres,
                      // How much should we shift the generated 
                      // contact plane in the normal direction
                      // (similar to how we shifted the floor by 0.03
                      //  earlier)
                      uniform float collision_distance,
                      // When the signed distance function
                      // evaluates to a value below 
                      // contact_margin + collision_distance
                      // (even when it's positive), we count the
                      // particle to be inside the collider and
                      // a collision event has happened.
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

    // When the signed distance function
    // evaluates to a value below 
    // contact_margin + collision_distance
    // (even when it's positive), we count the
    // particle to be inside the collider and
    // a collision event has happened.

    if (smallest_sdf < contact_margin + collision_distance) {
        closest_contact_plane.w += collision_distance;
        contact_planes[tid] = closest_contact_plane;
    } else {
        contact_planes[tid] = float4(0.0);
    }
}

float3 calculate_distance_correction(float l_ij,
                            float w_i,
                            float w_j,
                            float3 d
                            ) {

    float w_total = w_i / (w_i + w_j);
    float norm_d = length(d);
    float stretched = norm_d - l_ij;
    float3 correction = w_total * stretched * (d/norm_d);

    return correction;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid : SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         StructuredBuffer<float3> old_positions,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         StructuredBuffer<uint> row_ptr,
                         StructuredBuffer<uint> neighbors,
                         StructuredBuffer<float> neighbor_rest,
                         // Contact plane: dot(n, x) = d, with unit normal n
                         StructuredBuffer<float4> contact_planes,
                         uniform uint num_particles,
                         uniform float static_friction,
                         uniform float kinetic_friction) {
    if (tid >= num_particles) {
        return;
    }

    if (inv_masses[tid] == 0) {
    positions_out[tid] = positions_in[tid];
    return;
    }

    // FIRST do the distance correction 
    // like 4.4

    float3 total_corrections = float3(0.0);
    int total_neighbors = 0;
    float3 curr_position = positions_in[tid];

    int start_node = row_ptr[tid];
    int end_node = row_ptr[tid+1];

    for (int i = start_node; i < end_node; i++){
        total_neighbors += 1;
        int neighbor = neighbors[i];

        float l_ij = neighbor_rest[i];

        float w_i = inv_masses[tid];
        float w_j = inv_masses[neighbor];

        float3 d = positions_in[neighbor] - positions_in[tid];

        float3 correction = calculate_distance_correction(l_ij, w_i, w_j, d);

        total_corrections += correction;
    }

    if (total_neighbors != 0){
        float3 avg_corrections = total_corrections / total_neighbors;

        curr_position += avg_corrections;
    }   

    // SECONDLY, do normal corrections
    float4 contact_plane = contact_planes[tid];
    float3 normal = float3(contact_plane.xyz);
    float penetration_depth = 0;
    // see if a collision happened for this particle
    if (contact_plane.x != 0.0 || contact_plane.y != 0.0 || contact_plane.z != 0.0) {
        float sdf = plane_sdf(curr_position, contact_plane);
        if (sdf < 0){
            penetration_depth = -sdf;
        }

        //SEND IT BACK!!!
        curr_position += penetration_depth * normal;

        // LASTLY, do tangential corrections

        // direction and distance of sideways movement
        float3 tangent = (curr_position - old_positions[tid]) - (dot(curr_position-old_positions[tid], normal) * normal);
        // how fat the particle moved sideways
        float tangent_length = length(tangent);
        // just the dir of sideways movement (len of 1)
        float3 tangent_dir = tangent/tangent_length;

        // static friction
        if (tangent_length <= static_friction * penetration_depth){
            // move back to the old position in the tangent direction completely
            curr_position -= tangent;
        } 
        // kinetic friction 
        else {
            // move back to the old position in the tangent dir
            // by the amount of kinetic_friction * penetration depth
            float3 correction = tangent_dir * (kinetic_friction * penetration_depth);
            curr_position -= correction;
        }
    }
    positions_out[tid] = curr_position;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void update_velocity(uint tid : SV_DispatchThreadID,
                     RWStructuredBuffer<float3> positions,
                     StructuredBuffer<float3> old_positions,
                     RWStructuredBuffer<float3> velocities,
                     StructuredBuffer<float> inv_masses,
                     uniform uint num_particles,
                     uniform float dt) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.5. Your code below.
    float3 position = positions[tid];

    // Note that the old_positions buffer stores the position at 
    // the beginning of the timestep and should be the one you use 
    // to reconstruct the velocity
    float3 new_velocity = (position - old_positions[tid]) / dt;

    velocities[tid] = new_velocity;
}
