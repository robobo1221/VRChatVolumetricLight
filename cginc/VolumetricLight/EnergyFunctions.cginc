half phaseG(half NoV, half g) {
    half g2 = g * g;

    return (1.0 - g2) * (0.25 * rPI * pow(1.0 + g2 - 2.0 * g * NoV, -1.5));
}

half dualLobePhase(half NoV) {
    half phase1 = phaseG(NoV, 0.8);
    half phase2 = phaseG(NoV, -0.5);

    return (phase1 + phase2) * 0.5;
}

half dualLobePhase(half NoV, half g1, half g2) {
    half phase1 = phaseG(NoV, _ForwardG);
    half phase2 = phaseG(NoV, -_BackwardG);

    return lerp(phase2, phase1, _GMix);
}