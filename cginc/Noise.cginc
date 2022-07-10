float bayer2(float2 a) {
    a = floor(a);

    return frac(dot(a, float2(0.5, a.y * 0.75)));
}

float bayer4(const float2 a)   { return bayer2 (0.5   * a) * 0.25     + bayer2(a); }
float bayer8(const float2 a)   { return bayer4 (0.5   * a) * 0.25     + bayer2(a); }
float bayer16(const float2 a)  { return bayer4 (0.25  * a) * 0.0625   + bayer4(a); }
float bayer32(const float2 a)  { return bayer8 (0.25  * a) * 0.0625   + bayer4(a); }
float bayer64(const float2 a)  { return bayer8 (0.125 * a) * 0.015625 + bayer8(a); }
float bayer128(const float2 a) { return bayer16(0.125 * a) * 0.015625 + bayer8(a); }

float3 cubeSmooth(float3 x) {
    return x * x * (3.0 - 2.0 * x);
}

float Calculate3DNoise(float3 position){
    float3 p = floor(position);
    float3 b = cubeSmooth(position - p);

    float2 uv = (17.0 * float2(p.z, -p.z) + p.xy) + b.xy;
    float2 rg = tex2D(_NoiseTex, (uv + 0.5) / _NoiseTex_TexelSize.zw).xy;

    return lerp(rg.x, rg.y, b.z);
}