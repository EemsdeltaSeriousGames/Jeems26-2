
Shader "Bytesized/Toon URP"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _MainTex("Main Texture", 2D) = "white" {}

        [HDR] _AmbientColor("Ambient Color", Color) = (0.2,0.2,0.2,1)
        [HDR] _SpecularColor("Specular Color", Color) = (0.9,0.9,0.9,1)

        _Glossiness("Glossiness", Range(1,128)) = 32

        [HDR] _RimColor("Rim Color", Color) = (1,1,1,1)
        _RimBlend("Rim Blend", Range(0,1)) = 0.5
        _RimThreshold("Rim Threshold", Range(0.01,1)) = 0.1

        _Smoothness("Smoothness", Range(0,0.5)) = 0.05
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ToonForward"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _MainTex_ST;

                float4 _AmbientColor;
                float4 _SpecularColor;

                float _Glossiness;
                float _Smoothness;

                float4 _RimColor;
                float _RimBlend;
                float _RimThreshold;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
                float3 viewDirWS : TEXCOORD2;
                float3 positionWS : TEXCOORD3;
                float4 shadowCoord : TEXCOORD4;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                VertexPositionInputs positionInputs =
                    GetVertexPositionInputs(IN.positionOS.xyz);

                VertexNormalInputs normalInputs =
                    GetVertexNormalInputs(IN.normalOS);

                OUT.positionCS = positionInputs.positionCS;
                OUT.positionWS = positionInputs.positionWS;
                OUT.normalWS = normalInputs.normalWS;

                OUT.viewDirWS =
                    GetWorldSpaceViewDir(positionInputs.positionWS);

                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);

                OUT.shadowCoord = GetShadowCoord(positionInputs);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 normal = normalize(IN.normalWS);
                float3 viewDir = normalize(IN.viewDirWS);

                // Main directional light
                Light mainLight = GetMainLight(IN.shadowCoord);

                float3 lightDir = normalize(mainLight.direction);

                // Toon lighting
                float NdotL = dot(normal, lightDir);

                // Smooth transition between lit and unlit surfaces
                float lightIntensity = smoothstep(
                    -_Smoothness,
                    _Smoothness,
                    NdotL
                );

                // Apply shadows
                lightIntensity *= mainLight.shadowAttenuation;

                // Main light colour
                float3 light =
                    lightIntensity * mainLight.color * 0.75;

                // Specular lighting
                float3 halfVector =
                    normalize(lightDir + viewDir);

                float NdotH =
                    saturate(dot(normal, halfVector));

                float specularIntensity =
                    pow(NdotH, max(_Glossiness, 1.0))
                    * lightIntensity;

                float specularIntensitySmooth =
                    smoothstep(0.005, 0.01, specularIntensity);

                float3 specular =
                    specularIntensitySmooth * _SpecularColor.rgb;

                // Rim lighting
                float rimDot =
                    1.0 - saturate(dot(viewDir, normal));

                float rawRimIntensity =
                    rimDot * pow(
                        saturate(NdotL),
                        max(_RimThreshold, 0.01)
                    );

                float rimIntensity =
                    smoothstep(
                        _RimBlend - 0.01,
                        _RimBlend + 0.01,
                        rawRimIntensity
                    );

                float3 rim =
                    rimIntensity * _RimColor.rgb;

                // Main texture
                float4 tex = SAMPLE_TEXTURE2D(
                    _MainTex,
                    sampler_MainTex,
                    IN.uv
                );

                // Separate ambient and direct lighting
                float3 ambient = _AmbientColor.rgb;

                float3 directLighting =
                    (light + specular + rim)
                    * mainLight.distanceAttenuation;

                // Final colour
                float3 finalColor =
                    (directLighting + ambient)
                    * _Color.rgb
                    * tex.rgb;

                return float4(
                    finalColor,
                    tex.a * _Color.a
                );
            }

            ENDHLSL
        }

        // Shadow casting
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }

    FallBack Off
}
