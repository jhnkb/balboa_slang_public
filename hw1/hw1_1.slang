[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float2 center,
                  uniform float radius,
                  uniform float3 color,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(0.5, 0.5, 0.5, 1.0);

    // get new center because canvas right now is flipped vertically
    // only up and down changes, left to right stay the same
    float2 newCenter = float2(center.x, height - center.y);

    // Get coordinate of pixel's center
    float2 pixCenter = float2(tid.x + 0.5, tid.y + 0.5);
    
    // find the distance of center of pixel from the center of circle
    float pixCenter_dist_from_center = distance(pixCenter, newCenter);

    // check if center of pixel "touches" circle
    if (pixCenter_dist_from_center <= radius){
        image[tid] = float4(color, 1.0);
    }
}
