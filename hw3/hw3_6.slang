import hw3_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform Camera camera,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Sphere> spheres,
                  StructuredBuffer<TriangleMesh> meshes,
                  StructuredBuffer<float3> vertices,
                  StructuredBuffer<float3> vertex_normals,
                  StructuredBuffer<uint3> triangles,
                  StructuredBuffer<BVHNode> bvh_nodes,
                  StructuredBuffer<PointLight> lights,
                  uniform int num_lights,
                  uniform int max_depth,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // CAMERA SPACE     ->.    WORLD SPACE.      ->.    OBJ SPACE
    //             cam_to_world             world_to_obj


    image[tid] = float4(background, 1.0);

    float a = float(width)/float(height);

    //find center of current pixel
    float2 p_center = float2(tid.x + 0.5, tid.y + 0.5);

    //convert pixel center to image plane coord
    //get the image width using formula given from hw
    float img_width = 2 * tan(radians(camera.fov_x)/2.0);

    // get the half width and half height, 
    float half_width = img_width/2;
    float half_height = half_width/a;

    float new_x = -half_width + (2.0 * half_width * p_center.x)/width;
    float new_y = half_height - (2.0 * half_height * p_center.y)/height;
    float3 p_image = float3(new_x, new_y, -1.0);

    float3 ray_o = float3(0.0);
    float3 ray_d = normalize(p_image - ray_o);

    // first transform the camera rays to world space using cam_to_world. 
    ray_o = xform_pt(camera.cam_to_world, ray_o);
    ray_d = xform_vec(camera.cam_to_world, ray_d);


    // color keeps track of the total color from all bounces
    // throughput keeps track of how much reflection color we keep
    float3 color = float3(0.0);
    float3 throughput = float3(1.0);
    
    // repeat for max_depth number of rays
    // first ray is from camera, the rest are reflections
    for (int b = 0; b < max_depth; b++){

        // reset these because each new ray can hit a different SHAPE

        // how far along the ray the closest intersection happened
        float smallest_t = 1e30;
        // which SHAPE was hit
        int smallest_t_index = -1;
        // which triangle was hit, if the shape was a mesh
        int closest_tri_index = -1;
        // the barycentric coordinates used to interpolate its vertex normals
        float3 closest_b = float3(0.0);

        // total lighting from point lights for the current sphere
        // reset also so that we dont reuse the previous sphere's lighting
        float3 contribution = float3(0.0);

        // go through all the SHAPES and find closest intersection
        // find closest intersection from CURRENT ray origin
        for (int i = 0; i < num_shapes; i++){
            Shape shape = shapes[i];

            if (shape.type == ShapeType::Sphere){
                Sphere sphere = spheres[shape.index];

                float3 x_c = float3(sphere.center);
                float r = float(sphere.radius);

                // Next transform the rays to the object space using world_to_obj.
                float3 obj_ray_o = xform_pt(shape.world_to_obj, ray_o);
                float3 obj_ray_d = xform_vec(shape.world_to_obj, ray_d);
                float3 v = obj_ray_o - x_c;

                //derive A, B, and C (look at notes)
                float A = obj_ray_d.x * obj_ray_d.x + obj_ray_d.y * obj_ray_d.y + obj_ray_d.z * obj_ray_d.z;
                float B = 2.0 * (v.x * obj_ray_d.x + v.y * obj_ray_d.y + v.z * obj_ray_d.z);
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
            else if (shape.type == ShapeType::TriangleMesh){
                TriangleMesh mesh = meshes[shape.index];
                uint first_tri = mesh.triangle_begin;
                uint last_tri = mesh.triangle_end;

                // Next transform the rays to the object space using world_to_obj.
                float3 obj_ray_o = xform_pt(shape.world_to_obj, ray_o);
                float3 obj_ray_d = xform_vec(shape.world_to_obj, ray_d);

                //loop through the triangles
                for (uint j = first_tri; j < last_tri; j++){
                    // get the three vertex indexes
                    uint3 tri_indexes = triangles[j] + mesh.vertex_offset;

                    //get the actual vertex positions
                    float3 p0 = float3(vertices[tri_indexes[0]]);
                    float3 p1 = float3(vertices[tri_indexes[1]]);
                    float3 p2 = float3(vertices[tri_indexes[2]]);

                    // test ray-triangle intersection using intersect_tri
                    float3 b;
                    float t;

                    bool roots_exist = intersect_tri(p0, p1, p2, obj_ray_o, obj_ray_d, EPSILON, smallest_t, b, t);

                    if (roots_exist){
                        smallest_t = t;
                        smallest_t_index = i;
                        closest_tri_index = j;
                        closest_b = b;
                    }
                }
            }
        }   

            // if ray doesnt hit anything, use BG color
            // throughput matters here because this could be reflected ray
            if (smallest_t_index == -1){
                color += throughput * background;
                break;
            }

            //now we know the closest SHAPE for the current ray
            Shape shape = shapes[smallest_t_index];
            float3 x_c;
            float r;

            float3 obj_ray_o = xform_pt(shape.world_to_obj, ray_o);
            float3 obj_ray_d = xform_vec(shape.world_to_obj, ray_d);

            // Next transform the object space intersection 
            // points using obj_to_world and normals using the inverse transpose

            //intersection in obj space
            float3 obj_p_intersect = obj_ray_o + smallest_t * obj_ray_d;

            //intersection in world space
            float3 p_intersect = xform_pt(shape.obj_to_world, obj_p_intersect);

            float3 obj_n;

            if (shape.type == ShapeType::Sphere) {
                Sphere sphere = spheres[shape.index];

                x_c = float3(sphere.center);
                r = float(sphere.radius);

                // normal in object space
                obj_n = (obj_p_intersect - x_c) / r;
            }
            else if (shape.type == ShapeType::TriangleMesh){
                TriangleMesh mesh = meshes[shape.index];

                uint3 triangle = mesh.vertex_offset + triangles[closest_tri_index];

                // now get normals from vertex_normals
                float3 n0 = vertex_normals[triangle[0]];
                float3 n1 = vertex_normals[triangle[1]];
                float3 n2 = vertex_normals[triangle[2]];

                // interpolate normal
                obj_n = closest_b[0] * n0 + closest_b[1] * n1 + closest_b[2] * n2;
            }
            

            //normal in world space
            float3 n = xform_vec(transpose(shape.world_to_obj), obj_n);
            n = normalize(n);

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

                    if (other_shape.type == ShapeType::Sphere){
                        Sphere other_sphere = spheres[other_shape.index];

                        float3 x_c = float3(other_sphere.center);
                        // float3 shadow_o = p_intersect;
                        float3 obj_shadow_o = xform_pt(other_shape.world_to_obj, p_intersect);
                        float3 obj_shadow_d = xform_vec(other_shape.world_to_obj, shadow_d);
                        float r = float(other_sphere.radius);
                        float3 v = obj_shadow_o - x_c;

                        //derive A, B, and C (look at notes)
                        //replace ray_d with shadow_d 
                        float A = obj_shadow_d.x * obj_shadow_d.x + obj_shadow_d.y * obj_shadow_d.y + obj_shadow_d.z * obj_shadow_d.z;
                        float B = 2.0 * (v.x * obj_shadow_d.x + v.y * obj_shadow_d.y + v.z * obj_shadow_d.z);
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
                    else if (other_shape.type == ShapeType::TriangleMesh){
                        TriangleMesh mesh = meshes[other_shape.index];
                        uint first_tri = mesh.triangle_begin;
                        uint last_tri = mesh.triangle_end;

                        // Next transform the rays to the object space using world_to_obj.
                        float3 obj_shadow_o = xform_pt(other_shape.world_to_obj, p_intersect);
                        float3 obj_shadow_d = xform_vec(other_shape.world_to_obj, shadow_d);

                        //loop through the triangles
                        for (uint j = first_tri; j < last_tri; j++){
                            // get the three vertex indexes
                            uint3 tri_indexes = triangles[j] + mesh.vertex_offset;

                            //get the actual vertex positions
                            float3 p0 = float3(vertices[tri_indexes[0]]);
                            float3 p1 = float3(vertices[tri_indexes[1]]);
                            float3 p2 = float3(vertices[tri_indexes[2]]);

                            // test ray-triangle intersection using intersect_tri
                            float3 b;
                            float t;

                            bool roots_exist = intersect_tri(p0, p1, p2, obj_shadow_o, obj_shadow_d, EPSILON, t_max, b, t);

                            if (roots_exist){
                                if ((t > t_min && t < t_max)){
                                    blocking = true;
                                    break;
                                }
                            }
                        }
                    }
                    // exit the shade loop if something is already blocking the current light
                    if (blocking){
                        break;
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
