float phaseG(float NoV, float g) {
    float g2 = g * g;

    return (1.0 - g2) * (0.25 * rPI * pow(1.0 + g2 - 2.0 * g * NoV, -1.5));
}

float dualLobePhase(float NoV) {
    float phase1 = phaseG(NoV, 0.8);
    float phase2 = phaseG(NoV, -0.5);

    return (phase1 + phase2) * 0.5;
}

float dualLobePhase(float NoV, float g1, float g2) {
    float phase1 = phaseG(NoV, _ForwardG);
    float phase2 = phaseG(NoV, -_BackwardG);

    return lerp(phase2, phase1, _GMix);
}