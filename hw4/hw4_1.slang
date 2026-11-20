[shader("compute")]
[numthreads(64, 1, 1)]
void compute_main(uint tid : SV_DispatchThreadID,
                  RWStructuredBuffer<float3> positions,
                  RWStructuredBuffer<float3> velocities,
                  uniform uint num_particles,
                  // time step size
                  uniform float dt) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.1. Your code below.

    float3 a = float3(0.0, -9.8, 0.0);

    float3 v = velocities[tid];
    float3 new_v = v + a * dt;
    float3 x = positions[tid];
    float3 new_x = x + dt * new_v;

    if (new_x.y < -0.97){
        new_x.y = -0.97;
        new_v.y = -new_v.y;
    }
    
    velocities[tid] = new_v;
    positions[tid] = new_x;

}
