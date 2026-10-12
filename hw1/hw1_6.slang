import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int samples_per_axis,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> /*quadratic_beziers*/, // ignore for now
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(background, 1.0);

    // Get coordinate of current pixel's center
    // this is our screen point 
    float2 pixCenter_temp = float2(tid.x + 0.5, tid.y + 0.5); // slang coordinates
    float2 pixCenter = float2(pixCenter_temp.x, height - pixCenter_temp.y); //convert to hw coordinates

    float4 total_color = float4(0.0);

    // find the corner coordinate 
    float to_add = 1/ float(samples_per_axis);

    for (int sx = 0; sx < samples_per_axis; sx++){
        float sub_coord_x = tid.x + (sx * to_add);
        for (int sy = 0; sy < samples_per_axis; sy++){
            float sub_coord_y = tid.y + (sy * to_add);

            // find center of this sub pixel
            float2 subPix_center = float2(sub_coord_x + (to_add * 0.5), sub_coord_y + (to_add * 0.5)); //slang coord
            subPix_center = float2(subPix_center.x, height - subPix_center.y); // hw coord

            //assign the sub pixel's color to background
            float4 sample_color = float4(background,1.0);

            //go through all the shapes
            for (int i = num_shapes-1; i >= 0; i--){

                Shape shape = shapes[i];

                // if shape is a circle
                if (shape.type == ShapeType.Circle){
                    Circle circle = circles[shape.index];

                    float3x3 transform = shape.world_to_obj; // grab inversed tranformation matrix
                    
                    //homework coordinate
                    float3 pixCenter_matrix = float3 (subPix_center.x, subPix_center.y, 1); // convert current point to 3x1 matrix
                    float3 obj_space_pt_mtx = mul(transform, pixCenter_matrix); // screen point ---> object point
                    float2 obj_space_pt = float2(obj_space_pt_mtx.x, obj_space_pt_mtx.y); // grab the x and y values
                    
                    //homework coordinate
                    float2 new_center = circle.center;

                    // find the distance of center of pixel from the center of circle
                    float pixCenter_dist_from_center = distance(obj_space_pt, new_center);

                    // ********* //

                    // now check if this object point is in the circle
                    // check if center of SUBpixel "touches" circle
                    if (pixCenter_dist_from_center <= circle.radius){
                        if (shape.use_fill){
                        sample_color = shape.fill_rgba;
                        //OLD image[tid] = shape.fill_rgba;
                        } 
                    }

                    if (shape.use_stroke){

                        float outer_radius = circle.radius + (shape.stroke_width/2);
                        float inner_radius = circle.radius - (shape.stroke_width/2);
                        
                        // check if current pixel center distance are in between the two regions
                        if (inner_radius <= pixCenter_dist_from_center && pixCenter_dist_from_center <= outer_radius){
                            sample_color = shape.stroke_rgba;
                            
                            //OLD image[tid] = shape.stroke_rgba;
                        }
                    }
                    
                } //if shape is polyline
                else if (shape.type == ShapeType.Polyline){
                    Polyline polyline = polylines[shape.index];
                    
                    float3x3 transform = shape.world_to_obj; // grab inversed tranformation matrix

                    //homework coordinate
                    float3 pixCenter_matrix = float3 (subPix_center.x, subPix_center.y, 1); // convert current point to 3x1 matrix
                    float3 obj_space_pt_mtx = mul(transform, pixCenter_matrix); // screen point ---> object point
                    float2 q = float2(obj_space_pt_mtx.x, obj_space_pt_mtx.y); // grab the x and y values
                    
                    int begin = polyline.pts_begin;
                    int end = polyline.pts_end;

                    int winding_count = 0;
                    float2 p0;
                    float2 p1;
                    bool part_of_stroke = false;
                    float l;
                    float2 q_prime;
                    float t;
                    float s;
                    float stroke_width = 0;

                    if (shape.use_stroke){
                        stroke_width = shape.stroke_width;
                    }

                    for (int i = begin; i < end; i++){
                        
                        if (polyline.closed){
                            if (i == end - 1)
                            {
                                p0 = points[i];
                                p1 = points[begin];

                            
                            } else {
                                p0 = points[i];
                                p1 = points[i+1];
                            }

                            float segment_length = length(p1-p0);

                            //do not divide by zero for points that the same 
                            if (segment_length == 0){
                                continue;
                            }

                            //solve for l and q prime from the formulas in class
                            l = dot((p1-p0), (q-p0)) / segment_length;
                            q_prime = p0 + (l * ((p1-p0) / segment_length));

                            //check if part of stroke
                            if (l > 0 && l < segment_length && length(q-q_prime) < (stroke_width/2)){
                            part_of_stroke = true;
                            }

                            //get distance of center of pixel from the vertex
                            //for rounding
                            float currPix_dist_from_p0 = distance(q, p0);

                            if (currPix_dist_from_p0 <= stroke_width/2){
                                part_of_stroke = true;
                            }

                            //if horizontal segment, dont do anything
                            if (p1.y - p0.y == 0){
                                continue;
                            }

                            //solve for s and t from the formulas in class
                            t = (q.y - p0.y)/(p1.y - p0.y);
                            s = p0.x + (t*(p1.x - p0.x)) - q.x;

                            //now check if the ray intercepts the current line segment
                            if (s >= 0 && t <= 1 && t >= 0){
                                if (p0.y <= q.y && q.y < p1.y){
                                    winding_count += 1;
                                } else if (p1.y <= q.y && q.y < p0.y){
                                    winding_count -= 1;
                                }
                            }
                        } else {
                            if (i == end - 1){
                                break;
                            }

                            p0 = points[i];
                            p1 = points[i+1];

                            float segment_length = length(p1-p0);

                            if (segment_length == 0){
                                continue;
                            }

                            //solve for l and q prime from the formulas in class
                            l = dot((p1-p0), (q-p0)) / segment_length;
                            q_prime = p0 + (l * ((p1-p0) / segment_length));

                            //check if part of stroke
                            if (l > 0 && l < segment_length && length(q-q_prime) < (stroke_width/2)){
                                part_of_stroke = true;
                            }

                            if (i > begin) {
                                float currPix_dist_from_p0 = distance(q, p0);

                                if (currPix_dist_from_p0 <= stroke_width/2){
                                    part_of_stroke = true;
                                }
                            }
                        }
                    }
                    
                    //check if user wants to fill
                    if (shape.use_fill){
                        if (winding_count != 0){
                            sample_color = shape.fill_rgba;
                           //OLD image[tid] = shape.fill_rgba;
                        }
                    }

                    if (part_of_stroke){
                        if (shape.use_stroke){
                            sample_color = shape.stroke_rgba;
                            //OLD image[tid] = shape.stroke_rgba;
                        }
                    }  
                }
            }
            total_color += sample_color;
        }
    }

    float num_samples = float(samples_per_axis*samples_per_axis);
    float4 avg_color = float4(total_color / num_samples);
    image[tid] = avg_color;
}
