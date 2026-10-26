[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float2 sp0, // vertex at screen space
                  uniform float2 sp1,
                  uniform float2 sp2,
                  uniform float inv_depth0, // inverse depth in camera space
                  uniform float inv_depth1,
                  uniform float inv_depth2,
                  uniform int2 aabb_min,
                  uniform float3 c0, // vertex color
                  uniform float3 c1,
                  uniform float3 c2,
                  uniform float s,
                  uniform float a,
                  RWTexture2D<float4> color_image,
                  RWTexture2D<float> depth_image) {
    int2 ipixel = int2(tid) + int2(aabb_min);
    uint width, height;
    color_image.GetDimensions(width, height);
    if (ipixel.x < 0 || ipixel.y < 0 || ipixel.x >= width || ipixel.y >= height) {
        return;
    }

    // TODO: HW 2.1

    //color_image[ipixel] = float4(float3(0.0), 1.0);

    // pixel center
    float2 p_center = float2(ipixel.x + 0.5, ipixel.y + 0.5);
    float2 p = ipixel;

    // Is point inside current triangle? 
    // calculate edges
    float2 e01 = sp1 - sp0;
    float2 e12 = sp2 - sp1;
    float2 e20 = sp0 - sp2;

    // calculate normals of edges
    float2 n01 = float2(e01.y, -e01.x);
    float2 n12 = float2(e12.y, -e12.x);
    float2 n20 = float2(e20.y, -e20.x);

    //compute E_ij(p) = dot((p - v_i), n_ij)
    float E01 = dot((p_center - sp0), n01);
    float E12 = dot((p_center - sp1), n12);
    float E20 = dot((p_center - sp2), n20);


    //check if pixel is inside the triangle
    if ((E01 >= 0 && E12 >= 0 && E20 >= 0) || 
    (E01 <= 0 && E12 <= 0 && E20 <= 0)){

        // convert screen space --> projected camera space
        // p --> projp
        float projp_x = (p_center.x * (2.0 * s * a) / width) - (s * a);
        float projp_y = s - ((p_center.y * 2.0 * s) / height);
        float3 projp = float3(projp_x, projp_y, -1.0);

        // sp0 --> proj0
        float proj0_x = (sp0.x * (2.0 * s * a) / width) - (s * a);
        float proj0_y = s - ((sp0.y * 2.0 * s) / height);
        float3 proj0 = float3(proj0_x, proj0_y, -1.0);

        //sp1 --> proj1
        float proj1_x = (sp1.x * (2.0 * s * a) / width) - (s * a);
        float proj1_y = s - ((sp1.y * 2.0 * s) / height);
        float3 proj1 = float3(proj1_x, proj1_y, -1.0);

        //sp2 --> proj2
        float proj2_x = (sp2.x * (2.0 * s * a) / width) - (s * a);
        float proj2_y = s - ((sp2.y * 2.0 * s) / height);
        float3 proj2 = float3(proj2_x, proj2_y, -1.0);

        // apply equation 6 from HW here, and compute the 
        // projected barycentric coordinates b_pr_0, b_pr_1, b_pr_2
        float total_area = length(cross(proj1 - proj0, proj2 - proj0)) / 2.0;
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

        if (p_z < depth_image[ipixel]){
            depth_image[ipixel] = p_z;
            
            float3 c = b0 * c0 + b1 * c1 + b2 * c2;

            color_image[ipixel] = float4(c, 1.0);
        }
    } 
    


}
