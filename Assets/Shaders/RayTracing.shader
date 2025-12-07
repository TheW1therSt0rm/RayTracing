Shader "RayTracing"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float3 viewParams;
            float4x4 CamLocalToWorldMatrix;

            struct Ray {
                float3 origin;
                float3 dir;
            };

            float4 frag (v2f i) : SV_Target
            {
                float3 viewPointLocal = float3(i.uv - 0.5, 1) * viewParams;
                float3 viewPoint = mul(CamLocalToWorldMatrix, float4(viewPointLocal, 1)).xyz;

                Ray ray;
                ray.origin = _WorldSpaceCameraPos;
                ray.dir = normalize(viewPoint - ray.origin);
                return float4(ray.dir, 0);
            }
            ENDCG
        }
    }
}
