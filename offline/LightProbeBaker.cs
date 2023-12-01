using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

public class LightProbeBaker : MonoBehaviour {
    public Material volumetricMaterial;
    private Vector3 lightProbeRoot; // Store the root position of the light probe data

    [MenuItem("Tools/Bake Light Probes")]
    static void BakeLightProbesMenu() {
        LightProbeBaker lightProbeBaker = FindObjectOfType<LightProbeBaker>();
        if (lightProbeBaker != null) {
            lightProbeBaker.BakeLightProbes();
        }
        else {
            Debug.LogError("LightProbeBaker component not found in the scene.");
        }
    }

    void BakeLightProbes() {
        // Get all light probes in the scene
        LightProbeGroup[] lightProbeGroups = FindObjectsOfType<LightProbeGroup>();

        if (lightProbeGroups.Length == 0) {
            Debug.LogWarning("No light probe groups found in the scene.");
            return;
        }

        Bounds combinedBounds = new Bounds(Vector3.zero, Vector3.zero);

        // Iterate through all light probes and find the combined bounds
        foreach (var group in lightProbeGroups) {
            foreach (var localPosition  in group.probePositions) {
                Vector3 worldPosition = group.transform.TransformPoint(localPosition);
                combinedBounds.Encapsulate(worldPosition);
            }
        }

        Debug.Log("Combined Light Probe Bounds: " + combinedBounds.ToString());

        // Calculate the root position
        lightProbeRoot = combinedBounds.min;

        // Generate a new HDR 3D texture based on the combined bounds
        Texture3D lightProbeTexture = GenerateLightProbeTexture(combinedBounds);

        // Assign the generated texture to the material
        volumetricMaterial.SetTexture("_LightProbeTexture", lightProbeTexture);

        // Update shader properties
        UpdateShaderProperties(combinedBounds.size);
    }

    Texture3D GenerateLightProbeTexture(Bounds bounds) {
        int textureSize = 64; // Adjust the size as needed
        Texture3D lightProbeTexture = new Texture3D(textureSize, textureSize, textureSize, TextureFormat.RGBA32, true);

        // Set the filter mode and wrap mode as needed
        lightProbeTexture.filterMode = FilterMode.Trilinear;
        lightProbeTexture.wrapMode = TextureWrapMode.Clamp;

        // Iterate through all voxels in the 3D texture
        for (int x = 0; x < textureSize; x++) {
            for (int y = 0; y < textureSize; y++) {
                for (int z = 0; z < textureSize; z++) {
                    Vector3 samplePosition = new Vector3(
                        bounds.min.x + x / (float)(textureSize) * bounds.size.x,
                        bounds.min.y + y / (float)(textureSize) * bounds.size.y,
                        bounds.min.z + z / (float)(textureSize) * bounds.size.z
                    );

                    // Sample HDR value from light probes
                    SphericalHarmonicsL2 probe;
                    LightProbes.GetInterpolatedProbe(samplePosition, null, out probe);

                    // Convert the spherical harmonics data to HDR color

                    int numDirections = 64;
                    Vector3[] directions = new Vector3[numDirections];
                    Color[] results = new Color[numDirections];

                    // Generate random directions
                    for (int i = 0; i < numDirections; i++) {
                        directions[i] = UnityEngine.Random.onUnitSphere;
                    }

                    // Evaluate colors for each direction
                    probe.Evaluate(directions, results);

                    // Calculate the mean color
                    Color color = Color.black;
                    for (int i = 0; i < numDirections; i++) {
                        color += results[i];
                    }
                    color = color / numDirections;

                    // Assign the color to the voxel in the 3D texture
                    lightProbeTexture.SetPixel(x, y, z, color);
                }
            }
        }

        // Apply changes and return the texture
        lightProbeTexture.Apply();
        return lightProbeTexture;
    }

    void UpdateShaderProperties(Vector3 boundsSize) {
        if (volumetricMaterial == null) {
            Debug.LogError("No material assigned.");
            return;
        }

        // Set shader properties
        volumetricMaterial.SetVector("_LightProbeBounds", boundsSize);
        volumetricMaterial.SetVector("_LightProbeRoot", lightProbeRoot);
    }
}