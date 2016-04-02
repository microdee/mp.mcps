#include "../fxh/Defines.fxh"
#include "../fxh/pows.fxh"

#if !defined(PI)
#define PI 3.1415926535897932
#endif

struct Particle {
	#if defined(COMPOSITESTRUCT)
  		COMPOSITESTRUCT
 	#else
		float3 position;
		float3 velocity;
		float lifespan;
	#endif
};

//define TEXTURED

Texture2D texture2d;
StructuredBuffer<Particle> McpsBuffer;

cbuffer cbPerDraw : register( b0 )
{
    float4x4 tVP : VIEWPROJECTION;
    float4x4 ptVP : PREVIOUSVIEWPROJECTION;
};

cbuffer cbPerObj : register( b1 )
{
    float4 c <bool color=true;> = 1;
	float2 res : TARGETSIZE;
    float TailLength=.5;
    float radius = 5;
    float innerradius = 0;
    float Perspective = 1;
	bool RenderDead = false;
};

float3 qpos[4]:IMMUTABLE ={float3( -1, 1, 0 ),float3( 1, 1, 0 ),float3( -1, -1, 0 ),float3( 1, -1, 0 ),};
float2 quv[4]:IMMUTABLE ={float2(0,1), float2(1,1),float2(0,0),float2(1,0),};

SamplerState sL
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct VSIn
{
	uint iv : SV_VertexID;
};

struct VSOut
{
    float4 pos : SV_POSITION;
    float4 ppos : PREVPOS;
	float2 uv : TEXCOORD0;
	uint iv : VID;
};

VSOut VS(VSIn In)
{
    VSOut Out = (VSOut)0;
	float3 p = McpsBuffer[In.iv].position;
	float3 vel = McpsBuffer[In.iv].velocity;
    float3 pp = p-vel.xyz * mcpsTime.y;

    Out.pos = mul(float4(p, 1), tVP);
    Out.ppos = mul(float4(pp, 1), ptVP);

	Out.iv=In.iv;
    return Out;
}
[maxvertexcount(4)]
void GS(point VSOut In[1], inout TriangleStream<VSOut> GSOut)
{
    VSOut o;
	o.iv=In[0].iv;
	uint iv=In[0].iv;
	if((McpsBuffer[iv].lifespan >= 0.0f) || RenderDead)
	{
	    float3 p = In[0].pos.xyz / max(In[0].pos.w, 0.01);
	    float denom = max(In[0].pos.w, 0.01);
	    float3 pp = In[0].ppos.xyz / max(In[0].ppos.w, 0.01);
	
	    float2 svel = p.xy-pp.xy;
	    float angle = 0;
	    float2 ss = 1/res;
	    if(length(svel) > 0.0001)
	    {
	        float2 nsvel = normalize(svel / ss);
	        angle = atan2(-nsvel.y, nsvel.x);
	    }
	    float2x2 rotm = {1,0,0,1};
	    rotm[0][0] = cos(angle);
	    rotm[0][1] = -sin(angle);
	    rotm[1][0] = -rotm[0][1];
	    rotm[1][1] = rotm[0][0];
	
	    for(uint i=0; i<4; i++)
	    {
	    	float size = radius / lerp(1, denom, Perspective);
	        #if defined(KNOW_SIZE)
	            size *= McpsBuffer[iv].size;
	        #endif
	        float2 cpos = qpos[i].xy * size;
	        cpos.x += (min(length(svel), TailLength*4) * TailLength * qpos[i].x) / max(ss.x, ss.y);
	        cpos = mul(cpos, rotm);
	    	cpos *= ss;
	        cpos += p.xy;
	        o.pos = float4(cpos, p.z, 1);
	        o.uv = quv[i];
	        o.ppos = o.pos;
	    	if((p.z < 1) && (p.z > 0))
	    	{
	    		if(size > 0.2)
	        		GSOut.Append(o);
	    	}
	    }
	
		GSOut.RestartStrip();
	}
}

float4 PS_Tex(VSOut In): SV_Target
{
    clip(0.5 - length(In.uv.xy-.5));
    clip(length(In.uv.xy-.5) - innerradius);

    float4 col = c;

    #if defined(KNOW_COLOR)
       col *= McpsBuffer[In.iv].color;
    #endif
    #if defined(TEXTURED)
	   col *= texture2d.Sample( sL, In.uv);
    #endif

    return col;
}


technique10 tech
{
	pass P0
	{

		SetVertexShader( CompileShader( vs_4_0, VS() ) );
		SetGeometryShader( CompileShader( gs_4_0, GS() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_Tex() ) );
	}
}
