StructuredBuffer<float3> vertices;
StructuredBuffer<float3> vertex_normals;
StructuredBuffer<float2> vertex_uvs;
uniform float4x4 MVP;
uniform float4x4 model_matrix;
uniform float3x3 normal_matrix; // inverse transpose of the top-left 3x3 above
uniform float3 light_dir;
uniform float3 light_color;
uniform float3 camera_position;
uniform float3 Ks;
uniform float exponent;
Texture2D<float4> Kd_texture;
SamplerState Kd_sampler;

struct VertexOutput {
    float4 position : SV_Position;
    float3 world_position : TEXCOORD0;
    float3 world_normal : TEXCOORD1;
    float2 uv : TEXCOORD2;
};

[shader("vertex")]
VertexOutput vertex_main(uint vid : SV_VertexID) {
    VertexOutput output;
    float4 p = float4(vertices[vid], 1.0);

    output.position = mul(MVP, p);

    float3 new_world_normal = mul(normal_matrix, vertex_normals[vid]);
    output.world_normal = new_world_normal;

    float4 new_world_position = mul(model_matrix, p);
    float3 new_world_pos = float3(new_world_position.x, new_world_position.y, new_world_position.z);
    output.world_position = new_world_pos;

    float2 new_uv = vertex_uvs[vid];
    output.uv = new_uv;

    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    
    float3 world_normal = input.world_normal;
    float4 position = input.position;
    float2 uv = input.uv;
    float3 world_position = input.world_position;

    // Get the interpolated world-space normal and normalize it.
    // Get the diffuse material color from the texture.
    // Calculate ambient, diffuse, and specular lighting.
    // Add those contributions to produce the final pixel color.

    // normalize the world space normal
    float3 n = normalize(world_normal);
    float3 v = normalize(camera_position - world_position);
    float3 l = normalize(light_dir);

    float3 Kd = Kd_texture.Sample(Kd_sampler, uv).rgb;

    // calculate ambient
    float3 Ca = 0.2 * Kd;

    // calculate diffuse
    float3 Cd = Kd * light_color * max(0,dot(n, l));

    // calculate specular

    // find reflection vector
    float3 r = 2 * dot(n,l) * n - l;
    float3 Cs = float3(0);

    if (dot(n,l) > 0){
        Cs = Ks * light_color * pow(max(0, dot(r, v)), exponent);
    }

    float4 color = float4(Ca + Cd + Cs, 1.0);

    return color;
}
