using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

public class LightProbeBaker : MonoBehaviour {

    #if UNITY_EDITOR
    public Material volumetricMaterial;
    public int textureSize = 64;
    public float texturePadding = 0.1f;
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

        // Add padding to the bounds
        combinedBounds.Expand(texturePadding * combinedBounds.size);

        Debug.Log("Combined Light Probe Bounds: " + combinedBounds.ToString());

        // Calculate the root position
        lightProbeRoot = combinedBounds.min;

        // Generate a new HDR 3D texture based on the combined bounds
        Texture3D lightProbeTexture = GenerateLightProbeTexture(combinedBounds);

        // Save the generated texture to a folder
        string folderPath = "Assets/RoboGeneratedLightprops"; // Change this to your desired folder path
        System.IO.Directory.CreateDirectory(folderPath);

        string texturePath = folderPath + "/lightPropVolume.asset";
        AssetDatabase.CreateAsset(lightProbeTexture, texturePath);

        // Load the saved texture from the asset database
        Texture3D savedTexture = AssetDatabase.LoadAssetAtPath<Texture3D>(texturePath);

        // Assign the generated texture to the material
        volumetricMaterial.SetTexture("_LightProbeTexture", savedTexture); 

        // Update shader properties
        UpdateShaderProperties(combinedBounds.size);
    }

    Texture3D GenerateLightProbeTexture(Bounds bounds) {
        Texture3D lightProbeTexture = new Texture3D(textureSize, textureSize, textureSize, TextureFormat.RGBAFloat, true);

        // Set the filter mode and wrap mode as needed
        lightProbeTexture.filterMode = FilterMode.Trilinear;
        lightProbeTexture.wrapMode = TextureWrapMode.Clamp;

        // Iterate through all voxels in the 3D texture
        for (int x = 0; x < textureSize; x++) {
            for (int y = 0; y < textureSize; y++) {
                for (int z = 0; z < textureSize; z++) {
                    Vector3 samplePosition = new Vector3(
                        bounds.min.x + x / (float)(textureSize - 1) * bounds.size.x,
                        bounds.min.y + y / (float)(textureSize - 1) * bounds.size.y,
                        bounds.min.z + z / (float)(textureSize - 1) * bounds.size.z
                    );

                    // Sample HDR value from light probes
                    SphericalHarmonicsL2 probe;
                    LightProbes.GetInterpolatedProbe(samplePosition, null, out probe);

                    // Calculate the mean color
                    Color color = new Color(probe[0, 0], probe[1, 0], probe[2, 0]);

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
    #endif
}