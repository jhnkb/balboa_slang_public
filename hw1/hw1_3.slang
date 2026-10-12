import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int /*samples_per_axis*/, // ignore for now
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
    // TODO: your code here

    // Get coordinate of current pixel's center
    //this is also the value of our q
    float2 pixCenter = float2(tid.x + 0.5, tid.y + 0.5);

    //go through all the shapes
    for (int i = num_shapes-1; i >= 0; i--){

        Shape shape = shapes[i];

        // if shape is a circle
        if (shape.type == ShapeType.Circle){
            Circle circle = circles[shape.index];

            float2 circle_center = circle.center;
            //converted
            float2 new_center = float2(circle_center.x, height - circle_center.y);

            // find the distance of center of pixel from the center of circle
            float pixCenter_dist_from_center = distance(pixCenter, new_center);
            
            // check if center of pixel "touches" circle
            if (pixCenter_dist_from_center <= circle.radius){
                if (shape.use_fill){
                image[tid] = shape.fill_rgba;
                } 
            }

            if (shape.use_stroke){

                float outer_radius = circle.radius + (shape.stroke_width/2);
                float inner_radius = circle.radius - (shape.stroke_width/2);
                
                // check if current pixel center distance are in between the two regions
                if (inner_radius <= pixCenter_dist_from_center && pixCenter_dist_from_center <= outer_radius){
                    image[tid] = shape.stroke_rgba;
                }
            }
        } //if shape is polyline
        else if (shape.type == ShapeType.Polyline){
            Polyline polyline = polylines[shape.index];
            
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

                        //convert points to HW coordinate system
                        p0 = float2(p0.x, height - p0.y);
                        p1 = float2(p1.x, height - p1.y);
                    } else {
                        p0 = points[i];
                        p1 = points[i+1];

                        //convert points to HW coordinate system
                        p0 = float2(p0.x, height - p0.y);
                        p1 = float2(p1.x, height - p1.y);
                    }

                    float segment_length = length(p1-p0);

                    //do not divide by zero for points that the same 
                    if (segment_length == 0){
                        continue;
                    }

                    //solve for l and q prime from the formulas in class
                    l = dot((p1-p0), (pixCenter-p0)) / segment_length;
                    q_prime = p0 + (l * ((p1-p0) / segment_length));

                    //check if part of stroke
                    if (l > 0 && l < segment_length && length(pixCenter-q_prime) < (stroke_width/2)){
                    part_of_stroke = true;
                    }

                    //get distance of center of pixel from the vertex
                    //for rounding
                    float currPix_dist_from_p0 = distance(pixCenter, p0);

                    if (currPix_dist_from_p0 <= stroke_width/2){
                        part_of_stroke = true;
                    }

                    //if horizontal segment, dont do anything
                    if (p1.y - p0.y == 0){
                        continue;
                    }

                    //solve for s and t from the formulas in class
                    t = (pixCenter.y - p0.y)/(p1.y - p0.y);
                    s = p0.x + (t*(p1.x - p0.x)) - pixCenter.x;

                    //now check if the ray intercepts the current line segment
                    if (s >= 0 && t <= 1 && t >= 0){
                        if (p0.y <= pixCenter.y && pixCenter.y < p1.y){
                            winding_count += 1;
                        } else if (p1.y <= pixCenter.y && pixCenter.y < p0.y){
                            winding_count -= 1;
                        }
                    }
                } else {
                    if (i == end - 1){
                        break;
                    }

                    p0 = points[i];
                    p1 = points[i+1];

                    //convert here again
                    p0 = float2(p0.x, height-p0.y);
                    p1 = float2(p1.x, height-p1.y);

                    float segment_length = length(p1-p0);

                    if (segment_length == 0){
                        continue;
                    }

                    //solve for l and q prime from the formulas in class
                    l = dot((p1-p0), (pixCenter-p0)) / segment_length;
                    q_prime = p0 + (l * ((p1-p0) / segment_length));

                    //check if part of stroke
                    if (l > 0 && l < segment_length && length(pixCenter-q_prime) < (stroke_width/2)){
                        part_of_stroke = true;
                    }

                    if (i > begin) {
                        float currPix_dist_from_p0 = distance(pixCenter, p0);

                        if (currPix_dist_from_p0 <= stroke_width/2){
                            part_of_stroke = true;
                        }
                    }
                }
            }
            
            //check if user wants to fill
            if (shape.use_fill){
                if (winding_count != 0){
                    image[tid] = shape.fill_rgba;
                }
            }

            if (part_of_stroke){
                if (shape.use_stroke){
                    image[tid] = shape.stroke_rgba;
                }
            }
        }
    }
}
