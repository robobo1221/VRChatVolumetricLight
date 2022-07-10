#define scatteringCoefficient float3(0.25, 0.25, 0.25)
#define absorptionCoefficient float3(0.0, 0.0, 0.0)
#define extinctionCoefficient (scatteringCoefficient + absorptionCoefficient)

#define multiScatterTerms 8
#define multiScatterCoeffA 0.5
#define multiScatterCoeffB 0.5
#define multiScatterCoeffC 0.5