// Шаблон для додавання в кінець кожного MilkDrop шейдера
// Замінити останній return на цей код:

// Зберегти фінальний колір
float3 finalColor = color * intensity;

// MilkDrop-style feedback loop (motion blur)
float2 center = float2(0.5, 0.5);
float2 delta = in.uv - center;

float fbZoom = uniforms.feedbackZoom;
float fbRot = uniforms.feedbackRotation;

float cs = cos(fbRot);
float sn = sin(fbRot);
float2 feedbackUV = center + float2(
    (delta.x * cs - delta.y * sn) * fbZoom,
    (delta.x * sn + delta.y * cs) * fbZoom
);

float4 feedback = feedbackTexture.sample(s, feedbackUV);
float3 blended = feedback.rgb * uniforms.feedbackDecay + finalColor * (1.0 - uniforms.feedbackDecay);

return float4(blended, 1.0);
