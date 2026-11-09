import hw3_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  StructuredBuffer<Sphere> spheres,
                  uniform int num_spheres,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(background, 1.0);

    float a = float(width)/float(height);
    float2 p_center = float2(tid.x + 0.5, tid.y + 0.5);

    //convert pixel center to image plane coord
    float new_x = -a + ((2 * a) * p_center.x)/width;
    float new_y = 1 - (2 * p_center.y)/height;
    float3 p_image = float3(new_x, new_y, -1.0);

    float3 ray_o = float3(0.0);
    float3 ray_d = float3(p_image - ray_o);

    float smallest_t = 1e30;
    int smallest_t_index = -1;
    
    // go through all the spheres
    for (int i = 0; i < num_spheres; i++){
        Sphere sphere = spheres[i];

        float3 x_c = float3(sphere.center);
        float r = float(sphere.radius);
        float3 v = ray_o - x_c;

        //derive A, B, and C (look at notes)
        float A = ray_d.x * ray_d.x + ray_d.y * ray_d.y + ray_d.z * ray_d.z;
        float B = 2.0 * (v.x * ray_d.x + v.y * ray_d.y + v.z * ray_d.z);
        float C = v.x * v.x + v.y * v.y + v.z * v.z - r * r;

        float2 t_results;
        bool roots_exist = solve_quadratic(A, B, C, t_results);

        float t_intersect;

        if (roots_exist){
            if (t_results.x > 0 && t_results.y > 0){
                t_intersect = min(t_results.x, t_results.y);
            }
            else if (t_results.x > 0){
                t_intersect = t_results.x;
            }
            else if (t_results.y > 0){
                t_intersect = t_results.y;
            }
            else {
                continue;
            }
        } else {
            continue;
        }

        if (smallest_t > t_intersect){
            smallest_t = t_intersect;
            smallest_t_index = i;
        }
    }
    
    if (smallest_t_index != -1){
        float3 x_c = float3(spheres[smallest_t_index].center);
        float r = float(spheres[smallest_t_index].radius);
        float3 p_intersect = ray_o + smallest_t * ray_d;

        float3 n = (p_intersect - x_c)/r;

        float3 transformed_n = (n+1)/2;

        image[tid] = float4(transformed_n, 1.0);
    }
}
