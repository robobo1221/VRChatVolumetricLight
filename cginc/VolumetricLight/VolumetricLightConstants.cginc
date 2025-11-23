#define scatteringCoefficient 0.05
#define absorptionCoefficient 0.0
#define extinctionCoefficient (scatteringCoefficient + absorptionCoefficient)

#define multiScatterTerms 8
#define multiScatterCoeffA 0.5
#define multiScatterCoeffB 0.5
#define multiScatterCoeffC 0.5

#define scale 0.075

#define minHeight (1000.0 * scale)
#define maxHeight (2000.0 * scale)
#define thickness (maxHeight - minHeight)

#define slopeThicknessBottom (0.2 * thickness)
#define slopeThicknessTop (0.5 * thickness)

#define earthRadius (6371000.0 * scale)

#define fogHeightFalloffRayleigh (0.00025 / scale)
#define fogHeightFalloffMie (0.01 / scale)

#define fogCoeffRayleigh (half3( 7.8, 15.5, 33.1 ) * 2.0e-6)
#define fogCoeffMie (half3(1.0, 1.0, 1.0) * 3.0e-4)