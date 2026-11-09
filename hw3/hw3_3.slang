import hw3_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Sphere> spheres,
                  StructuredBuffer<PointLight> lights,
                  uniform int num_lights,
                  uniform int max_depth,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(background, 1.0);

    float a = float(width)/float(height);

    //find center of current pixel
    float2 p_center = float2(tid.x + 0.5, tid.y + 0.5);

    //convert pixel center to image plane coord
    float new_x = -a + ((2 * a) * p_center.x)/width;
    float new_y = 1 - (2 * p_center.y)/height;
    float3 p_image = float3(new_x, new_y, -1.0);

    float3 ray_o = float3(0.0);
    float3 ray_d = normalize(p_image - ray_o);

    // color keeps track of the total color from all bounces
    // throughput keeps track of how much reflection color we keep
    float3 color = float3(0.0);
    float3 throughput = float3(1.0);
    
    // repeat for max_depth number of rays
    // first ray is from camera, the rest are reflections
    for (int b = 0; b < max_depth; b++){

        //reset these because each new ray can hit a different sphere
        float smallest_t = 1e30;
        int smallest_t_index = -1;

        // total lighting from point lights for the current sphere
        // reset also so that we dont reuse the previous sphere's lighting
        float3 contribution = float3(0.0);

        // go through all the spheres
        // find closest intersection from CURRENT ray origin
        for (int i = 0; i < num_shapes; i++){
            Shape shape = shapes[i];
            Sphere sphere = spheres[shape.index];

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

            // find the smallest valid + t
            // EPSILON avoids hitting the same surface again after reflection
            // same surface == origin "jumping point"
            if (roots_exist){
                if (t_results.x > EPSILON && t_results.y > EPSILON){
                    t_intersect = min(t_results.x, t_results.y);
                }
                else if (t_results.x > EPSILON){
                    t_intersect = t_results.x;
                }
                else if (t_results.y > EPSILON){
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

                //this is now the shape index, not sphere
                smallest_t_index = i;
            }
        }   
            // if ray doesnt hit anything, use BG color
            // throughput matters here because this could be reflected ray
            if (smallest_t_index == -1){
                color += throughput * background;
                break;
            }

            //now we know the closest sphere for the current ray
            Shape shape = shapes[smallest_t_index];
            Sphere sphere = spheres[shape.index];

            float3 x_c = float3(sphere.center);
            float r = float(sphere.radius);

            // find where the ray hits the sphere
            // then calculate the surface normal
            float3 p_intersect = ray_o + smallest_t * ray_d;
            float3 n = (p_intersect - x_c) / r;

            // Kd is diffuse color, Kr is reflection color
            float3 Kd = shape.Kd;
            float3 Kr = shape.Kr;

            //loop through the lights
            for (int i = 0; i < num_lights; i++){
                PointLight light = lights[i];
                float3 light_pos = light.position;
                float3 I = light.intensity;
                
                // destination - origin
                // direction from intersection to light
                float3 shadow_ray = light_pos - p_intersect;

                // this is the l in the formula and ray_d from above
                // THIS IS A DIRECTION TOO
                float3 shadow_d = normalize(shadow_ray);

                // establish the limits of how far or close 
                // when checking the t values
                // avoids self intersecting from origin
                float t_min = EPSILON;
                float t_max = length(shadow_ray);
                
                bool blocking = false;

                // check whether any sphere blocks the light
                for (int y = 0; y < num_shapes; y++){
                    Shape other_shape = shapes[y];
                    Sphere other_sphere = spheres[other_shape.index];

                    float3 x_c = float3(other_sphere.center);
                    float3 shadow_o = p_intersect;
                    float r = float(other_sphere.radius);
                    float3 v = shadow_o - x_c;

                    //derive A, B, and C (look at notes)
                    //replace ray_d with shadow_d 
                    float A = shadow_d.x * shadow_d.x + shadow_d.y * shadow_d.y + shadow_d.z * shadow_d.z;
                    float B = 2.0 * (v.x * shadow_d.x + v.y * shadow_d.y + v.z * shadow_d.z);
                    float C = v.x * v.x + v.y * v.y + v.z * v.z - r * r;

                    float2 t_results;
                    bool roots_exist = solve_quadratic(A, B, C, t_results);

                    if (roots_exist){
                        if ((t_results.x > t_min && t_results.x < t_max) 
                            || (t_results.y > t_min && t_results.y < t_max)){
                                blocking = true;
                                break;
                            } 
                    }
                }

                // if nothing is blocking between light and sphere surface
                // calculate contribution
                if (blocking == false){
                    float d = length(shadow_ray);
                    float d_squared = d * d;

                    float diffuse = max(0.0, dot(n,shadow_d));

                    float3 C_diffuse = Kd * (I/d_squared) * diffuse;

                    contribution += C_diffuse;
                }
            }   
                // add current sphere's lighting to the total color
                // throughput is from the PREVIOUS reflection
                color += throughput * contribution;

                // multiply by the current sphere's Kr
                // how much of the next reflection is kept
                throughput *= Kr;

                // calculate reflect ray direction
                ray_d = reflect(ray_d, n);

                // next ray origin is where the intersection is!
                ray_o = p_intersect;
    }   
        // write final color after all bounces
        image[tid] = float4(color, 1.0);
}
