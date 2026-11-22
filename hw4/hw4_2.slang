[shader("compute")]
[numthreads(64, 1, 1)]
void predict(uint tid : SV_DispatchThreadID,
             // Updated position
             RWStructuredBuffer<float3> positions,
             // Store the position before update
             RWStructuredBuffer<float3> old_positions,
             RWStructuredBuffer<float3> velocities,
             StructuredBuffer<float> inv_masses,
             uniform uint num_particles,
             // time step size
             uniform float dt) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.2. Your code below.

    if (inv_masses[tid] == 0){
        return;
    }

    // gravity
    float3 a = float3(0.0, -9.8, 0.0);

    // apply gravity to the velocity
    float3 v = velocities[tid];
    float3 new_v = v + a * dt;

    // and update the position (do NOT apply collision here yet like in 4.1)
    float3 x = positions[tid];

    // The old_positions argument should store the positions before update
    old_positions[tid] = x;
    float3 new_x = x + dt * new_v;

    // and the positions and velocities buffers store the 
    // updated position and velocity respectively
    positions[tid] = new_x;
    velocities[tid] = new_v;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid : SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         StructuredBuffer<float> rest_lengths,
                         uniform uint num_particles) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.2. Your code below.

    if (inv_masses[tid] == 0){
        positions_out[tid] = positions_in[tid];
        return;
    }

    // for each particle, we look at its neighbors (it either has
    // one of two neighbors)
    
    //first particle: one neighbor to the right
    if (tid == 0){
        // get particle neighbor
        int neighbor = 1;
        float l_ij = rest_lengths[tid];

        float w_i = inv_masses[tid];
        float w_j = inv_masses[neighbor];

        float w_total = w_i / (w_i + w_j);

        float3 d = positions_in[neighbor] - positions_in[tid];
        float norm_d = length(d);

        float stretched = norm_d - l_ij;

        float3 correction = w_total * stretched * (d/norm_d);

        float3 new_position = positions_in[tid] + correction;

        positions_out[tid] = new_position;

    } // last particle: one neighbor to the left
    else if (tid == (num_particles-1)){
        // get particle neighbor
        int neighbor = tid - 1;
        float l_ij = rest_lengths[tid-1];

        float w_i = inv_masses[tid];
        float w_j = inv_masses[neighbor];

        float w_total = w_i / (w_i + w_j);

        float3 d = positions_in[neighbor] - positions_in[tid];
        float norm_d = length(d);

        float stretched = norm_d - l_ij;

        float3 correction = w_total * stretched * (d/norm_d);

        float3 new_position = positions_in[tid] + correction;

        positions_out[tid] = new_position;
    }
    else {
        // get particle neighbor(s)
        int left_n = tid-1;
        int right_n = tid+1;
        float l_ij;
        //float l_left = rest_lengths[tid-1];
        //float l_right = rest_lengths[tid];

        // do the left neighbor first
        l_ij = rest_lengths[tid-1];

        float w_i = inv_masses[tid];
        float w_j = inv_masses[left_n];

        float w_total = w_i / (w_i + w_j);

        float3 d = positions_in[left_n] - positions_in[tid];
        float norm_d = length(d);

        float stretched = norm_d - l_ij;

        float3 correction = w_total * stretched * (d/norm_d);

        float3 left_position = positions_in[tid] + correction;

        // now do the right neighbor
        l_ij = rest_lengths[tid];

        w_i = inv_masses[tid];
        w_j = inv_masses[right_n];

        w_total = w_i / (w_i + w_j);

        d = positions_in[right_n] - positions_in[tid];
        norm_d = length(d);

        stretched = norm_d - l_ij;

        correction = w_total * stretched * (d/norm_d);

        float3 right_position = positions_in[tid] + correction;

        // average new positions
        float3 avg_positions = (left_position + right_position) / 2;

        positions_out[tid] = avg_positions;
 
    }
}

[shader("compute")]
[numthreads(64, 1, 1)]
void update_velocity(uint tid : SV_DispatchThreadID,
                     RWStructuredBuffer<float3> positions,
                     StructuredBuffer<float3> old_positions,
                     RWStructuredBuffer<float3> velocities,
                     StructuredBuffer<float> inv_masses,
                     uniform uint num_particles,
                     // time step size
                     uniform float dt) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.2. Your code below.

    //  clip the position against the floor at y = −0.97 and reconstruct the velocity using
    //  the clipped positions

    float3 position = positions[tid];

    if (position.y < -0.97){
        position.y = -0.97;
        positions[tid] = position;;
    }

    // Note that the old_positions buffer stores the position at 
    // the beginning of the timestep and should be the one you use 
    // to reconstruct the velocity
    float3 new_velocity = (position - old_positions[tid]) / dt;

    velocities[tid] = new_velocity;

}
