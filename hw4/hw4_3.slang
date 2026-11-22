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

int convert_to_tid (int x, int y, int grid_size_x){
    int index = y * grid_size_x + x;
    return index;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid : SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         uniform int2 grid_size,
                         uniform float2 spacing) {
    if (tid >= grid_size.x * grid_size.y) {
        return;
    }

    if (inv_masses[tid] == 0) {
        positions_out[tid] = positions_in[tid];
        return;
    }

    int row_num = grid_size.y;
    int col_num = grid_size.x;

    int num_particles = row_num * col_num;

    int x = tid % grid_size.x;
    int y = tid / grid_size.x;

    float3 total_corrections = float3(0);
    int total_neighbors = 0;

    // GATHER NEIGHBORS

    // structural neighbors
    int2 str1 = int2(x+1, y);
    int2 str2 = int2(x-1, y); 
    int2 str3 = int2(x, y-1);
    int2 str4 = int2(x, y+1);
    int2 structural_neighbors[4] = {str1, str2, str3, str4};

    for (int i = 0; i < structural_neighbors.getCount(); i++){
        int2 neighbor = structural_neighbors[i];
        
        if (neighbor.x >= 0 && neighbor.x < grid_size.x &&
            neighbor.y >= 0 && neighbor.y < grid_size.y) {
            total_neighbors += 1;
            int neighbor_index = convert_to_tid(neighbor.x, neighbor.y, grid_size.x);

            float l_ij;

            if (neighbor.x != x) {
                l_ij = spacing.x;
            } else {
                l_ij = spacing.y;
            }
            
            float w_i = inv_masses[tid];
            float w_j = inv_masses[neighbor_index];

            float3 d = positions_in[neighbor_index] - positions_in[tid];

            float3 correction = calculate_correction(l_ij, w_i, w_j, d);

            total_corrections += correction;  
        }
    }

    // shearing neighbors
    int2 she1 = int2(x+1, y+1);
    int2 she2 = int2(x+1, y-1);
    int2 she3 = int2(x-1, y-1);
    int2 she4 = int2(x-1, y+1);
    int2 shearing_neighbors[4] = {she1, she2, she3, she4};

    for (int i = 0; i < shearing_neighbors.getCount(); i++){
        int2 neighbor = shearing_neighbors[i];
        
        if (neighbor.x >= 0 && neighbor.x < grid_size.x &&
            neighbor.y >= 0 && neighbor.y < grid_size.y) {
            total_neighbors += 1;
            int neighbor_index = convert_to_tid(neighbor.x, neighbor.y, grid_size.x);

            float l_ij = length(spacing);
            
            float w_i = inv_masses[tid];
            float w_j = inv_masses[neighbor_index];

            float3 d = positions_in[neighbor_index] - positions_in[tid];

            float3 correction = calculate_correction(l_ij, w_i, w_j, d);

            total_corrections += correction;  
        }
    }
    

    // bending neighbors
    int2 ben1 = int2(x+2, y);
    int2 ben2 = int2(x-2, y);
    int2 ben3 = int2(x, y+2);
    int2 ben4 = int2(x, y-2);
    int2 bending_neighbors[4] = {ben1, ben2, ben3, ben4};

    for (int i = 0; i < bending_neighbors.getCount(); i++){
        int2 neighbor = bending_neighbors[i];
        
        if (neighbor.x >= 0 && neighbor.x < grid_size.x &&
            neighbor.y >= 0 && neighbor.y < grid_size.y) {
            total_neighbors += 1;
            int neighbor_index = convert_to_tid(neighbor.x, neighbor.y, grid_size.x);

            float l_ij;

            if (neighbor.x != x) {
                l_ij = 2 * spacing.x;
            } else {
                l_ij = 2 * spacing.y;
            }
            
            float w_i = inv_masses[tid];
            float w_j = inv_masses[neighbor_index];

            float3 d = positions_in[neighbor_index] - positions_in[tid];

            float3 correction = calculate_correction(l_ij, w_i, w_j, d);

            total_corrections += correction;  
        }
    }
    if (total_neighbors != 0){
        float3 avg_corrections = total_corrections / total_neighbors;

        float3 new_position = positions_in[tid] + avg_corrections;

        positions_out[tid] = new_position;
    }
}
