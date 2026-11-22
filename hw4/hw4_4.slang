float3 calculate_correction(float l_ij,
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
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         // The CSR matrix data structure
                         StructuredBuffer<uint> row_ptr,
                         StructuredBuffer<uint> neighbors,
                         // Rest lengthes of the neighbor edges
                         StructuredBuffer<float> neighbor_rest,
                         uniform uint num_particles) {
    if (tid >= num_particles) {
        return;
    }
    
    if (inv_masses[tid] == 0) {
        positions_out[tid] = positions_in[tid];
        return;
    }

    float3 total_corrections = float3(0);
    int total_neighbors = 0;

    int start_node = row_ptr[tid];
    int end_node = row_ptr[tid+1];

    for (int i = start_node; i < end_node; i++){
        total_neighbors += 1;
        int neighbor = neighbors[i];

        float l_ij = neighbor_rest[i];

        float w_i = inv_masses[tid];
        float w_j = inv_masses[neighbor];

        float3 d = positions_in[neighbor] - positions_in[tid];

        float3 correction = calculate_correction(l_ij, w_i, w_j, d);

        total_corrections += correction;
    }

    if (total_neighbors != 0){
        float3 avg_corrections = total_corrections / total_neighbors;

        float3 new_position = positions_in[tid] + avg_corrections;

        positions_out[tid] = new_position;
    }
}
