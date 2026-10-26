[shader("compute")]
[numthreads(64, 1, 1)]
void clear_buffers(uint tid : SV_DispatchThreadID,
                   uniform uint num_pixels,
                   RWStructuredBuffer<uint> depth_buffer,
                   RWStructuredBuffer<uint> triangle_id_buffer) {
    if (tid >= num_pixels)
        return;

    depth_buffer[tid] = 0xffffffff;
    triangle_id_buffer[tid] = 0xffffffff;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void transform_vertices(
    uint tid : SV_DispatchThreadID,
    uniform uint num_vertices,
    uniform uint vertex_offset,
    uniform float4x4 MVP,
    StructuredBuffer<float3> vertices,
    RWStructuredBuffer<float3> projected_vertices)
{
    if (tid >= num_vertices)
        return;

    uint i = vertex_offset + tid;
    float4 p = mul(MVP, float4(vertices[i], 1.0));
    projected_vertices[i] = p.xyz / p.w;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void rasterize_depth(
        uint tid : SV_DispatchThreadID,
        uniform uint num_triangles,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        // A projected vertex store the screen space coordinates
        // in xy, and the inverse depth in z.
        StructuredBuffer<float3> projected_vertices,
        RWStructuredBuffer<uint> depth_buffer) {
    // HW 2.5 TODO

    if (tid >= num_triangles) {
        return;
    }
    
    // get the three vertex INDICES, 
    // tells us which vertices make up the triangle
    uint3 face = faces[tid];

    float3 p0 = projected_vertices[face.x];
    float3 p1 = projected_vertices[face.y];
    float3 p2 = projected_vertices[face.z];

    float inv_depth0 = p0.z;
    float inv_depth1 = p1.z;
    float inv_depth2 = p2.z;

    float x_min = min(p0.x, min(p1.x, p2.x));
    float y_min = min(p0.y, min(p1.y, p2.y));

    float x_max = max(p0.x, max(p1.x, p2.x));
    float y_max = max(p0.y, max(p1.y, p2.y));

    int pixel_x_min = int(floor(x_min));
    int pixel_y_min = int(floor(y_min));

    int pixel_x_max = int(ceil(x_max));
    int pixel_y_max = int(ceil(y_max));

    if (pixel_x_min < 0){
        pixel_x_min = 0;
    }
    if (pixel_y_min < 0){
        pixel_y_min = 0;
    }
    if (pixel_x_max >= width){
        pixel_x_max = width -1;
    }
    if (pixel_y_max >= height){
        pixel_y_max = height -1;
    }

    // Is point inside current triangle? 
    // calculate edges
    float2 e01 = float2(p1.x,p1.y) - float2(p0.x,p0.y);
    float2 e12 = float2(p2.x,p2.y) - float2(p1.x,p1.y);
    float2 e20 = float2(p0.x,p0.y) - float2(p2.x,p2.y);

    // calculate normals of edges
    float2 n01 = float2(e01.y, -e01.x);
    float2 n12 = float2(e12.y, -e12.x);
    float2 n20 = float2(e20.y, -e20.x);

    // for x, t in screen AABB:
    for(int y = pixel_y_min; y <= pixel_y_max; y++){
        for(int x = pixel_x_min; x <= pixel_x_max; x++){

            // find pixel center
            float2 p_center = float2(x + 0.5, y + 0.5);
            float2 p = float2(x, y);

            //compute E_ij(p) = dot((p - v_i), n_ij)
            float E01 = dot((p_center - float2(p0.x, p0.y)), n01);
            float E12 = dot((p_center - float2(p1.x, p1.y)), n12);
            float E20 = dot((p_center - float2(p2.x, p2.y)), n20);

            // if pixel_center hits face:
            if ((E01 >= 0 && E12 >= 0 && E20 >= 0) || 
            (E01 <= 0 && E12 <= 0 && E20 <= 0)) {

                // convert screen space --> projected camera space
                // p --> projp
                float projp_x = (p_center.x * (2.0 * s * a) / width) - (s * a);
                float projp_y = s - ((p_center.y * 2.0 * s) / height);
                float3 projp = float3(projp_x, projp_y, -1.0);

                // sp0 --> proj0
                float proj0_x = (p0.x * (2.0 * s * a) / width) - (s * a);
                float proj0_y = s - ((p0.y * 2.0 * s) / height);
                float3 proj0 = float3(proj0_x, proj0_y, -1.0);
                
                //sp1 --> proj1
                float proj1_x = (p1.x * (2.0 * s * a) / width) - (s * a);
                float proj1_y = s - ((p1.y * 2.0 * s) / height);
                float3 proj1 = float3(proj1_x, proj1_y, -1.0);

                //sp2 --> proj2
                float proj2_x = (p2.x * (2.0 * s * a) / width) - (s * a);
                float proj2_y = s - ((p2.y * 2.0 * s) / height);
                float3 proj2 = float3(proj2_x, proj2_y, -1.0);       
                
                // apply equation 6 from HW here, and compute the 
                // projected barycentric coordinates b_pr_0, b_pr_1, b_pr_2
                float total_area = length(cross(proj1 - proj0, proj2 - proj0)) / 2.0;

                if (total_area <= 0) {
                    continue;
                }

                float area_0 = length(cross(proj1 - projp, proj2 - projp)) / 2.0;
                float area_1 = length(cross(proj0 - projp, proj2 - projp)) / 2.0;
                float area_2 = length(cross(proj0 - projp, proj1 - projp)) / 2.0;

                float b_pr_0 = area_0/total_area;
                float b_pr_1 = area_1/total_area;
                float b_pr_2 = area_2/total_area;

                // using the proj. barycentric coords and the depths at the three vertices
                // --> original barycentric coords using eq (15)
                float interpolate_depth = b_pr_0 * inv_depth0 + b_pr_1 * inv_depth1 + b_pr_2 * inv_depth2;

                float b0 = (b_pr_0 * inv_depth0) / interpolate_depth;
                float b1 = (b_pr_1 * inv_depth1) / interpolate_depth;
                float b2 = (b_pr_2 * inv_depth2) / interpolate_depth;

                float p_z = b0 * (1.0 / inv_depth0) + b1 * (1.0 / inv_depth1) + b2 * (1.0 / inv_depth2);

                uint depth_bits = asuint(p_z);

                uint index = y * width + x;
                InterlockedMin(depth_buffer[index], depth_bits);

            }
        }
    }
}


[shader("compute")]
[numthreads(64, 1, 1)]
void rasterize_id(
        uint tid : SV_DispatchThreadID,
        uniform uint num_triangles,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        StructuredBuffer<float3> projected_vertices,
        RWStructuredBuffer<uint> depth_buffer,
        RWStructuredBuffer<uint> triangle_id_buffer) {
    // get the three vertex INDICES, 
    // tells us which vertices make up the triangle
    
    if (tid >= num_triangles) {
        return;
    }

    uint3 face = faces[tid];

    float3 p0 = projected_vertices[face.x];
    float3 p1 = projected_vertices[face.y];
    float3 p2 = projected_vertices[face.z];

    float inv_depth0 = p0.z;
    float inv_depth1 = p1.z;
    float inv_depth2 = p2.z;

    float x_min = min(p0.x, min(p1.x, p2.x));
    float y_min = min(p0.y, min(p1.y, p2.y));

    float x_max = max(p0.x, max(p1.x, p2.x));
    float y_max = max(p0.y, max(p1.y, p2.y));

    int pixel_x_min = int(floor(x_min));
    int pixel_y_min = int(floor(y_min));

    int pixel_x_max = int(ceil(x_max));
    int pixel_y_max = int(ceil(y_max));

    if (pixel_x_min < 0){
        pixel_x_min = 0;
    }
    if (pixel_y_min < 0){
        pixel_y_min = 0;
    }
    if (pixel_x_max >= width){
        pixel_x_max = width -1;
    }
    if (pixel_y_max >= height){
        pixel_y_max = height -1;
    }

    // Is point inside current triangle? 
    // calculate edges
    float2 e01 = float2(p1.x,p1.y) - float2(p0.x,p0.y);
    float2 e12 = float2(p2.x,p2.y) - float2(p1.x,p1.y);
    float2 e20 = float2(p0.x,p0.y) - float2(p2.x,p2.y);

    // calculate normals of edges
    float2 n01 = float2(e01.y, -e01.x);
    float2 n12 = float2(e12.y, -e12.x);
    float2 n20 = float2(e20.y, -e20.x);

    // for x, t in screen AABB:
    for(int y = pixel_y_min; y <= pixel_y_max; y++){
        for(int x = pixel_x_min; x <= pixel_x_max; x++){

            // find pixel center
            float2 p_center = float2(x + 0.5, y + 0.5);
            float2 p = float2(x, y);

            //compute E_ij(p) = dot((p - v_i), n_ij)
            float E01 = dot((p_center - float2(p0.x, p0.y)), n01);
            float E12 = dot((p_center - float2(p1.x, p1.y)), n12);
            float E20 = dot((p_center - float2(p2.x, p2.y)), n20);

            // if pixel_center hits face:
            if ((E01 >= 0 && E12 >= 0 && E20 >= 0) || 
            (E01 <= 0 && E12 <= 0 && E20 <= 0)) {

                // convert screen space --> projected camera space
                // p --> projp
                float projp_x = (p_center.x * (2.0 * s * a) / width) - (s * a);
                float projp_y = s - ((p_center.y * 2.0 * s) / height);
                float3 projp = float3(projp_x, projp_y, -1.0);

                // sp0 --> proj0
                float proj0_x = (p0.x * (2.0 * s * a) / width) - (s * a);
                float proj0_y = s - ((p0.y * 2.0 * s) / height);
                float3 proj0 = float3(proj0_x, proj0_y, -1.0);
                
                //sp1 --> proj1
                float proj1_x = (p1.x * (2.0 * s * a) / width) - (s * a);
                float proj1_y = s - ((p1.y * 2.0 * s) / height);
                float3 proj1 = float3(proj1_x, proj1_y, -1.0);

                //sp2 --> proj2
                float proj2_x = (p2.x * (2.0 * s * a) / width) - (s * a);
                float proj2_y = s - ((p2.y * 2.0 * s) / height);
                float3 proj2 = float3(proj2_x, proj2_y, -1.0);       
                
                // apply equation 6 from HW here, and compute the 
                // projected barycentric coordinates b_pr_0, b_pr_1, b_pr_2
                float total_area = length(cross(proj1 - proj0, proj2 - proj0)) / 2.0;

                if (total_area <= 0) {
                    continue;
                }

                float area_0 = length(cross(proj1 - projp, proj2 - projp)) / 2.0;
                float area_1 = length(cross(proj0 - projp, proj2 - projp)) / 2.0;
                float area_2 = length(cross(proj0 - projp, proj1 - projp)) / 2.0;

                float b_pr_0 = area_0/total_area;
                float b_pr_1 = area_1/total_area;
                float b_pr_2 = area_2/total_area;

                // using the proj. barycentric coords and the depths at the three vertices
                // --> original barycentric coords using eq (15)
                float interpolate_depth = b_pr_0 * inv_depth0 + b_pr_1 * inv_depth1 + b_pr_2 * inv_depth2;

                float b0 = (b_pr_0 * inv_depth0) / interpolate_depth;
                float b1 = (b_pr_1 * inv_depth1) / interpolate_depth;
                float b2 = (b_pr_2 * inv_depth2) / interpolate_depth;

                float p_z = b0 * (1.0 / inv_depth0) + b1 * (1.0 / inv_depth1) + b2 * (1.0 / inv_depth2);

                uint depth_bits = asuint(p_z);

                uint index = y * width + x;

                // note: tid is essentially the triangle # 
                // if this triangle's depth matches the closest depth
                if (depth_bits == depth_buffer[index]){

                    // store the smallest triangle id for this pixel
                    InterlockedMin(triangle_id_buffer[index], tid);
                }
            }
        }
    }
}

[shader("compute")]
[numthreads(8, 8, 1)]
void shade(
        uint2 tid : SV_DispatchThreadID,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        StructuredBuffer<float3> vertex_colors,
        StructuredBuffer<float3> projected_vertices,
        StructuredBuffer<uint> triangle_id_buffer,
        RWTexture2D<float4> image) {
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // find the current pixel's center
    float2 p_center = float2(tid.x + 0.5, tid.y + 0.5);
    float2 p = float2(tid.x, tid.y);

    uint index = tid.y * width + tid.x;
    uint face_id = triangle_id_buffer[index];

    if (face_id != 0xFFFFFFFF){

        uint3 face = faces[face_id];

        float3 c0 = vertex_colors[face.x];
        float3 c1 = vertex_colors[face.y];
        float3 c2 = vertex_colors[face.z];

        float3 p0 = projected_vertices[face.x];
        float3 p1 = projected_vertices[face.y];
        float3 p2 = projected_vertices[face.z];

        float inv_depth0 = p0.z;
        float inv_depth1 = p1.z;
        float inv_depth2 = p2.z;

        float projp_x = (p_center.x * (2.0 * s * a) / width) - (s * a);
        float projp_y = s - ((p_center.y * 2.0 * s) / height);
        float3 projp = float3(projp_x, projp_y, -1.0);

        // sp0 --> proj0
        float proj0_x = (p0.x * (2.0 * s * a) / width) - (s * a);
        float proj0_y = s - ((p0.y * 2.0 * s) / height);
        float3 proj0 = float3(proj0_x, proj0_y, -1.0);
        
        //sp1 --> proj1
        float proj1_x = (p1.x * (2.0 * s * a) / width) - (s * a);
        float proj1_y = s - ((p1.y * 2.0 * s) / height);
        float3 proj1 = float3(proj1_x, proj1_y, -1.0);

        //sp2 --> proj2
        float proj2_x = (p2.x * (2.0 * s * a) / width) - (s * a);
        float proj2_y = s - ((p2.y * 2.0 * s) / height);
        float3 proj2 = float3(proj2_x, proj2_y, -1.0);       
        
        // apply equation 6 from HW here, and compute the 
        // projected barycentric coordinates b_pr_0, b_pr_1, b_pr_2
        float total_area = length(cross(proj1 - proj0, proj2 - proj0)) / 2.0;

        if (total_area <= 0) {
           return;
        }

        float area_0 = length(cross(proj1 - projp, proj2 - projp)) / 2.0;
        float area_1 = length(cross(proj0 - projp, proj2 - projp)) / 2.0;
        float area_2 = length(cross(proj0 - projp, proj1 - projp)) / 2.0;

        float b_pr_0 = area_0/total_area;
        float b_pr_1 = area_1/total_area;
        float b_pr_2 = area_2/total_area;

        // using the proj. barycentric coords and the depths at the three vertices
        // --> original barycentric coords using eq (15)
        float interpolate_depth = b_pr_0 * inv_depth0 + b_pr_1 * inv_depth1 + b_pr_2 * inv_depth2;

        float b0 = (b_pr_0 * inv_depth0) / interpolate_depth;
        float b1 = (b_pr_1 * inv_depth1) / interpolate_depth;
        float b2 = (b_pr_2 * inv_depth2) / interpolate_depth;

        float3 c = b0 * c0 + b1 * c1 + b2 * c2;

        image[tid] = float4(c,1.0);
    }   
}