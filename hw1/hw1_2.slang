import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  StructuredBuffer<float2> polyline,
                  uniform int num_polyline,
                  uniform bool is_closed,
                  uniform bool use_fill_color,
                  uniform float3 fill_color,
                  uniform bool use_stroke_color,
                  uniform float3 stroke_color,
                  uniform float stroke_width,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(0.5, 0.5, 0.5, 1.0);
    // TODO: your code here

    float2 q = float2(tid.x + 0.5, tid.y + 0.5);
    int winding_count = 0;

    float2 p0;
    float2 p1;
    bool part_of_stroke = false;
    float l;
    float2 q_prime;
    float t;
    float s;

    for (int i = 0; i <= num_polyline-1; i++)
    {   

        // CHECK IF POLY LINE SHAPE IS CLOSED
        if (is_closed)
        {
            if (i == num_polyline - 1)
            {
                p0 = polyline[i];
                p1 = polyline[0];

                //"converting" points to homework coordinate system
                p0 = float2(p0.x, height-p0.y);
                p1 = float2(p1.x, height-p1.y);

            } else {
                p0 = polyline[i];
                p1 = polyline[i+1];

                //convert here again
                p0 = float2(p0.x, height-p0.y);
                p1 = float2(p1.x, height-p1.y);

                }

            float segment_length = length(p1 - p0);

            // do not divide by zero for points that are the same
            if (segment_length == 0){
                continue;
            }

            // SOLVE FOR l & q' FROM THE FORMULAS IN CLASS
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

            //if horizontal segment, do not do anything
            if (p1.y - p0.y == 0){
                continue;
            }

            // SOLVE FOR s & t FROM THE FORMULAS IN CLASS
            t = (q.y - p0.y)/(p1.y - p0.y);
            s = p0.x + (t*(p1.x - p0.x)) - q.x;
            
            // NOW CHECKING IF THE RAY INTERCEPTS THE CURRENT LINE SEGMENT
            if (s >= 0 && t <= 1 && t >= 0)
            {
                if (p0.y <= q.y  && q.y < p1.y){
                    winding_count += 1;
                } else if (p1.y <= q.y && q.y < p0.y){
                    winding_count -= 1;
                } 
            }

//**************************************************//

        // IF NOT CLOSED THEN PROCEED WITH NOT CLOSING
        } else {

            if (i == num_polyline-1){
                break;
            }

            p0 = polyline[i];
            p1 = polyline[i+1];

            //convert here again
            p0 = float2(p0.x, height-p0.y);
            p1 = float2(p1.x, height-p1.y);

            float segment_length = length(p1-p0);
            
            if (segment_length == 0){
                continue;
            }

            // SOLVE FOR l & q' FROM THE FORMULAS IN CLASS
            l = dot((p1-p0), (q-p0)) / segment_length;
            q_prime = p0 + (l * ((p1-p0) / segment_length));
            
            // NOW CHECK IF q IS INSIDE STROKE
            if (l > 0 && l < segment_length && length(q-q_prime) < (stroke_width/2)){
                part_of_stroke = true;
            }

            if (i > 0){
                float currPix_dist_from_p0 = distance(q, p0);

                if (currPix_dist_from_p0 <= stroke_width/2){
                    part_of_stroke = true;
                }
            }
        }
    }

    // CHECK IF USER WANTS TO FILL 
    if (use_fill_color){
        if (winding_count != 0){
            image[tid] = float4(fill_color, 1.0);
        }
    }

    if(part_of_stroke){
        // CHECK IF USER WANTS TO FILL STROKE WITH THEIR COLOR
        if (use_stroke_color){
            image[tid] = float4(stroke_color, 1.0);
        }
    }
}
