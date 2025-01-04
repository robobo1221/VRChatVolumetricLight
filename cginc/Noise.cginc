half bayer2(half2 a) {
    a = floor(a);

    return frac(dot(a, half2(0.5, a.y * 0.75)));
}

half bayer4(const half2 a)   { return bayer2 (0.5   * a) * 0.25     + bayer2(a); }
half bayer8(const half2 a)   { return bayer4 (0.5   * a) * 0.25     + bayer2(a); }
half bayer16(const half2 a)  { return bayer4 (0.25  * a) * 0.0625   + bayer4(a); }
half bayer32(const half2 a)  { return bayer8 (0.25  * a) * 0.0625   + bayer4(a); }
half bayer64(const half2 a)  { return bayer8 (0.125 * a) * 0.015625 + bayer8(a); }
half bayer128(const half2 a) { return bayer16(0.125 * a) * 0.015625 + bayer8(a); }

half3 cubeSmooth(half3 x) {
    return x * x * (3.0 - 2.0 * x);
}

half Calculate3DNoise(half3 position){
    half3 p = floor(position);
    half3 b = cubeSmooth(position - p);

    half2 uv = (17.0 * half2(p.z, -p.z) + p.xy) + b.xy;
    half2 rg = tex2D(_NoiseTex, (uv + 0.5) / _NoiseTex_TexelSize.zw).xy;

    return lerp(rg.x, rg.y, b.z);
}