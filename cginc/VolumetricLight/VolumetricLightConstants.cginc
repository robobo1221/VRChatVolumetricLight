#define scatteringCoefficient 0.05
#define absorptionCoefficient 0.0
#define extinctionCoefficient (scatteringCoefficient + absorptionCoefficient)

#define multiScatterTerms 8
#define multiScatterCoeffA 0.5
#define multiScatterCoeffB 0.5
#define multiScatterCoeffC 0.5

#define scale 0.01

#define minHeight (1000.0 * scale)
#define maxHeight (2000.0 * scale)
#define thickness (maxHeight - minHeight)

#define slopeThicknessBottom (0.2 * thickness)
#define slopeThicknessTop (0.5 * thickness)

#define earthRadius (6371000.0 * scale)