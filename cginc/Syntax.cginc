#define PI 3.14159265359
#define rPI 0.31830988618

#define TAU 6.28318530718
#define rTAU 0.15915494309

float4 offsetCoord(float4 uv, float2 offset) {
    return float4(uv.x + offset.x * uv.w, uv.y + offset.y * uv.w, uv.z, uv.w);
}