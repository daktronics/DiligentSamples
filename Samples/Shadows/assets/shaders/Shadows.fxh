#ifndef _SHADOWS_FXH_
#define _SHADOWS_FXH_

// Must include BasicStructures.fxh

#ifndef SHADOW_FILTER_SIZE
#   define SHADOW_FILTER_SIZE 2
#endif

#ifndef FILTER_ACROSS_CASCADES
#   define FILTER_ACROSS_CASCADES 0
#endif

float GetDistanceToCascadeMargin(float3 f3PosInCascadeProjSpace, float4 f4MarginProjSpace)
{
    float4 f4DistToEdges;
    f4DistToEdges.xy = float2(1.0, 1.0) - f4MarginProjSpace.xy - abs(f3PosInCascadeProjSpace.xy);
    const float ZScale = 2.0 / (1.0 - NDC_MIN_Z);
    f4DistToEdges.z = (f3PosInCascadeProjSpace.z - (NDC_MIN_Z + f4MarginProjSpace.z)) * ZScale;
    f4DistToEdges.w = (1.0 - f4MarginProjSpace.w - f3PosInCascadeProjSpace.z) * ZScale;
    return min(min(f4DistToEdges.x, f4DistToEdges.y), min(f4DistToEdges.z, f4DistToEdges.w));
}

struct CascadeSamplingInfo
{
    int    iCascadeIdx;
    float2 f2UV;
    float  fDepth;
    float3 f3LightSpaceScale;
    float  fMinDistToMargin;
};

CascadeSamplingInfo GetCascadeSamplingInfo(ShadowMapAttribs ShadowAttribs,
                                           float3           f3PosInLightViewSpace,
                                           int              iCascadeIdx)
                                
{
    CascadeAttribs Cascade = ShadowAttribs.Cascades[iCascadeIdx];
    float3 f3CascadeLightSpaceScale = Cascade.f4LightSpaceScale.xyz;
    float3 f3PosInCascadeProjSpace  = f3PosInLightViewSpace * f3CascadeLightSpaceScale + Cascade.f4LightSpaceScaledBias.xyz;
    CascadeSamplingInfo SamplingInfo;
    SamplingInfo.iCascadeIdx       = iCascadeIdx;
    SamplingInfo.f2UV              = NormalizedDeviceXYToTexUV(f3PosInCascadeProjSpace.xy);
    SamplingInfo.fDepth            = NormalizedDeviceZToDepth(f3PosInCascadeProjSpace.z);
    SamplingInfo.f3LightSpaceScale = f3CascadeLightSpaceScale;
    SamplingInfo.fMinDistToMargin  = GetDistanceToCascadeMargin(f3PosInCascadeProjSpace, Cascade.f4MarginProjSpace);
    return SamplingInfo;
}

CascadeSamplingInfo FindCascade(ShadowMapAttribs ShadowAttribs,
                                float3           f3PosInLightViewSpace,
                                float            fCameraViewSpaceZ)
{
    CascadeSamplingInfo SamplingInfo;
    float3 f3PosInCascadeProjSpace  = float3(0.0, 0.0, 0.0);
    float3 f3CascadeLightSpaceScale = float3(0.0, 0.0, 0.0);
    int    iCascadeIdx = 0;
#if BEST_CASCADE_SEARCH
    while (iCascadeIdx < ShadowAttribs.iNumCascades)
    {
        // Find the smallest cascade which covers current point
        CascadeAttribs Cascade  = ShadowAttribs.Cascades[iCascadeIdx];
        SamplingInfo.f3LightSpaceScale = Cascade.f4LightSpaceScale.xyz;
        f3PosInCascadeProjSpace = f3PosInLightViewSpace * SamplingInfo.f3LightSpaceScale + Cascade.f4LightSpaceScaledBias.xyz;
        SamplingInfo.fMinDistToMargin = GetDistanceToCascadeMargin(f3PosInCascadeProjSpace, Cascade.f4MarginProjSpace);

        if (SamplingInfo.fMinDistToMargin > 0.0)
        {
            SamplingInfo.f2UV   = NormalizedDeviceXYToTexUV(f3PosInCascadeProjSpace.xy);
            SamplingInfo.fDepth = NormalizedDeviceZToDepth(f3PosInCascadeProjSpace.z);
            break;
        }
        else
            iCascadeIdx++;
    }
#else
    [unroll]
    for(int i=0; i< (ShadowAttribs.iNumCascades+3)/4; ++i)
    {
        float4 f4CascadeZEnd = ShadowAttribs.f4CascadeCamSpaceZEnd[i];
        float4 v = float4( f4CascadeZEnd.x < fCameraViewSpaceZ ? 1.0 : 0.0, 
                           f4CascadeZEnd.y < fCameraViewSpaceZ ? 1.0 : 0.0,
                           f4CascadeZEnd.z < fCameraViewSpaceZ ? 1.0 : 0.0,
                           f4CascadeZEnd.w < fCameraViewSpaceZ ? 1.0 : 0.0);
	    //float4 v = float4(ShadowAttribs.f4CascadeCamSpaceZEnd[i] < fCameraViewSpaceZ);
	    iCascadeIdx += int(dot(float4(1.0, 1.0, 1.0, 1.0), v));
    }

    if (iCascadeIdx < ShadowAttribs.iNumCascades)
    {
        //Cascade = min(Cascade, ShadowAttribs.iNumCascades - 1);
        SamplingInfo = GetCascadeSamplingInfo(ShadowAttribs, f3PosInLightViewSpace, iCascadeIdx);
    }
#endif
    SamplingInfo.iCascadeIdx = iCascadeIdx;
    return SamplingInfo;
}

float GetNextCascadeBlendAmount(ShadowMapAttribs    ShadowAttribs,
                                float               fCameraViewSpaceZ,
                                CascadeSamplingInfo SamplingInfo,
                                CascadeSamplingInfo NextCscdSamplingInfo)
{
    float fDistToTransitionEdge;
#if BEST_CASCADE_SEARCH
    fDistToTransitionEdge = SamplingInfo.fMinDistToMargin;
#else
    float4 f4CascadeStartEndZ = ShadowAttribs.Cascades[SamplingInfo.iCascadeIdx].f4StartEndZ;
    fDistToTransitionEdge = (f4CascadeStartEndZ.y - fCameraViewSpaceZ) / (f4CascadeStartEndZ.y - f4CascadeStartEndZ.x);
#endif

    return saturate(1.0 - fDistToTransitionEdge / ShadowAttribs.fCascadeTransitionRegion) * 
           saturate(NextCscdSamplingInfo.fMinDistToMargin / ShadowAttribs.fCascadeTransitionRegion); // Make sure that we don't sample outside of the next cascade
}

float2 ComputeReceiverPlaneDepthBias(float3 ShadowUVDepthDX,
                                     float3 ShadowUVDepthDY)
{    
    // Compute (dDepth/dU, dDepth/dV):
    //  
    //  | dDepth/dU |    | dX/dU    dX/dV |T  | dDepth/dX |     | dU/dX    dU/dY |-1T | dDepth/dX |
    //                 =                                     =                                      =
    //  | dDepth/dV |    | dY/dU    dY/dV |   | dDepth/dY |     | dV/dX    dV/dY |    | dDepth/dY |
    //
    //  | A B |-1   | D  -B |                      | A B |-1T   | D  -C |                                   
    //            =           / det                           =           / det                    
    //  | C D |     |-C   A |                      | C D |      |-B   A |
    //
    //  | dDepth/dU |           | dV/dY   -dV/dX |  | dDepth/dX |
    //                 = 1/det                                       
    //  | dDepth/dV |           |-dU/dY    dU/dX |  | dDepth/dY |

    float2 biasUV;
    //               dV/dY       V      dDepth/dX    D       dV/dX       V     dDepth/dY     D
    biasUV.x =   ShadowUVDepthDY.y * ShadowUVDepthDX.z - ShadowUVDepthDX.y * ShadowUVDepthDY.z;
    //               dU/dY       U      dDepth/dX    D       dU/dX       U     dDepth/dY     D
    biasUV.y = - ShadowUVDepthDY.x * ShadowUVDepthDX.z + ShadowUVDepthDX.x * ShadowUVDepthDY.z;

    float Det = (ShadowUVDepthDX.x * ShadowUVDepthDY.y) - (ShadowUVDepthDX.y * ShadowUVDepthDY.x);
	biasUV /= sign(Det) * max( abs(Det), 1e-10 );
    //biasUV = abs(Det) > 1e-7 ? biasUV / abs(Det) : 0;// sign(Det) * max( abs(Det), 1e-10 );
    return biasUV;
}

//-------------------------------------------------------------------------------------------------
// The method used in The Witness
//-------------------------------------------------------------------------------------------------
float FilterShadowMapFixedPCF(in Texture2DArray<float>  tex2DShadowMap,
                              in SamplerComparisonState tex2DShadowMap_sampler,
                              in float4                 shadowMapSize,
                              in CascadeSamplingInfo    SamplingInfo,
                              in float2                 receiverPlaneDepthBias)
{
    float lightDepth = SamplingInfo.fDepth;

    float2 uv = SamplingInfo.f2UV * shadowMapSize.xy;
    float2 base_uv = floor(uv + float2(0.5, 0.5));
    float s = (uv.x + 0.5 - base_uv.x);
    float t = (uv.y + 0.5 - base_uv.y);
    base_uv -= float2(0.5, 0.5);
    base_uv *= shadowMapSize.zw;

    float sum = 0;

    // It is essential to clamp biased depth to 0 to avoid shadow leaks at near cascade depth boundary.
    //        
    //            No clamping                 With clamping
    //                                      
    //              \ |                             ||    
    //       ==>     \|                             ||
    //                |                             ||         
    // Light ==>      |\                            |\         
    //                | \Receiver plane             | \ Receiver plane
    //       ==>      |  \                          |  \   
    //                0   ...   1                   0   ...   1
    //
    // Note that clamping at far depth boundary makes no difference as 1 < 1 produces 0 and so does 1+x < 1
    const float DepthClamp = 1e-8;
#define SAMPLE_SHADOW_MAP(u, v) tex2DShadowMap.SampleCmp(tex2DShadowMap_sampler, float3(base_uv.xy + float2(u,v) * shadowMapSize.zw, SamplingInfo.iCascadeIdx), max(lightDepth + dot(float2(u, v), receiverPlaneDepthBias), DepthClamp))

    #if SHADOW_FILTER_SIZE == 2

        return tex2DShadowMap.SampleCmp(tex2DShadowMap_sampler, float3(SamplingInfo.f2UV.xy, SamplingInfo.iCascadeIdx), max(lightDepth, DepthClamp));

    #elif SHADOW_FILTER_SIZE == 3

        float uw0 = (3.0 - 2.0 * s);
        float uw1 = (1.0 + 2.0 * s);

        float u0 = (2.0 - s) / uw0 - 1.0;
        float u1 = s / uw1 + 1.0;

        float vw0 = (3.0 - 2.0 * t);
        float vw1 = (1.0 + 2.0 * t);

        float v0 = (2.0 - t) / vw0 - 1;
        float v1 = t / vw1 + 1;

        sum += uw0 * vw0 * SAMPLE_SHADOW_MAP(u0, v0);
        sum += uw1 * vw0 * SAMPLE_SHADOW_MAP(u1, v0);
        sum += uw0 * vw1 * SAMPLE_SHADOW_MAP(u0, v1);
        sum += uw1 * vw1 * SAMPLE_SHADOW_MAP(u1, v1);

        return sum * 1.0 / 16.0;

    #elif SHADOW_FILTER_SIZE == 5

        float uw0 = (4.0 - 3.0 * s);
        float uw1 = 7.0;
        float uw2 = (1.0 + 3.0 * s);

        float u0 = (3.0 - 2.0 * s) / uw0 - 2.0;
        float u1 = (3.0 + s) / uw1;
        float u2 = s / uw2 + 2.0;

        float vw0 = (4.0 - 3.0 * t);
        float vw1 = 7.0;
        float vw2 = (1.0 + 3.0 * t);

        float v0 = (3.0 - 2.0 * t) / vw0 - 2.0;
        float v1 = (3.0 + t) / vw1;
        float v2 = t / vw2 + 2;

        sum += uw0 * vw0 * SAMPLE_SHADOW_MAP(u0, v0);
        sum += uw1 * vw0 * SAMPLE_SHADOW_MAP(u1, v0);
        sum += uw2 * vw0 * SAMPLE_SHADOW_MAP(u2, v0);

        sum += uw0 * vw1 * SAMPLE_SHADOW_MAP(u0, v1);
        sum += uw1 * vw1 * SAMPLE_SHADOW_MAP(u1, v1);
        sum += uw2 * vw1 * SAMPLE_SHADOW_MAP(u2, v1);

        sum += uw0 * vw2 * SAMPLE_SHADOW_MAP(u0, v2);
        sum += uw1 * vw2 * SAMPLE_SHADOW_MAP(u1, v2);
        sum += uw2 * vw2 * SAMPLE_SHADOW_MAP(u2, v2);

        return sum * 1.0 / 144.0;

    #elif SHADOW_FILTER_SIZE == 7

        float uw0 = (5.0 * s - 6.0);
        float uw1 = (11.0 * s - 28.0);
        float uw2 = -(11.0 * s + 17.0);
        float uw3 = -(5.0 * s + 1.0);

        float u0 = (4.0 * s - 5.0) / uw0 - 3.0;
        float u1 = (4.0 * s - 16.0) / uw1 - 1.0;
        float u2 = -(7.0 * s + 5.0) / uw2 + 1.0;
        float u3 = -s / uw3 + 3.0;

        float vw0 = (5.0 * t - 6.0);
        float vw1 = (11.0 * t - 28.0);
        float vw2 = -(11.0 * t + 17.0);
        float vw3 = -(5.0 * t + 1.0);

        float v0 = (4.0 * t - 5.0) / vw0 - 3.0;
        float v1 = (4.0 * t - 16.0) / vw1 - 1.0;
        float v2 = -(7.0 * t + 5.0) / vw2 + 1.0;
        float v3 = -t / vw3 + 3.0;

        sum += uw0 * vw0 * SAMPLE_SHADOW_MAP(u0, v0);
        sum += uw1 * vw0 * SAMPLE_SHADOW_MAP(u1, v0);
        sum += uw2 * vw0 * SAMPLE_SHADOW_MAP(u2, v0);
        sum += uw3 * vw0 * SAMPLE_SHADOW_MAP(u3, v0);

        sum += uw0 * vw1 * SAMPLE_SHADOW_MAP(u0, v1);
        sum += uw1 * vw1 * SAMPLE_SHADOW_MAP(u1, v1);
        sum += uw2 * vw1 * SAMPLE_SHADOW_MAP(u2, v1);
        sum += uw3 * vw1 * SAMPLE_SHADOW_MAP(u3, v1);

        sum += uw0 * vw2 * SAMPLE_SHADOW_MAP(u0, v2);
        sum += uw1 * vw2 * SAMPLE_SHADOW_MAP(u1, v2);
        sum += uw2 * vw2 * SAMPLE_SHADOW_MAP(u2, v2);
        sum += uw3 * vw2 * SAMPLE_SHADOW_MAP(u3, v2);

        sum += uw0 * vw3 * SAMPLE_SHADOW_MAP(u0, v3);
        sum += uw1 * vw3 * SAMPLE_SHADOW_MAP(u1, v3);
        sum += uw2 * vw3 * SAMPLE_SHADOW_MAP(u2, v3);
        sum += uw3 * vw3 * SAMPLE_SHADOW_MAP(u3, v3);

        return sum * 1.0 / 2704.0;
    #else
        return 0.0;
    #endif
#undef SAMPLE_SHADOW_MAP
}

/*
float FilterShadowMapVaryingPCF(in Texture2DArray<float>  tex2DShadowMap,
                                in SamplerComparisonState tex2DShadowMap_sampler,
                                in ShadowMapAttribs       ShadowAttribs,
                                in CascadeSamplingInfo    SamplingInfo,
                                in float2                 f2ReceiverPlaneDepthBias,
                                in float2                 f2FilterSize)
{
    //float2 maxFilterSize = MaxKernelSize / abs(CascadeScales[0].xy);
    //float2 filterSize = clamp(min(FilterSize.xx, maxFilterSize) * abs(CascadeScales[cascadeIdx].xy), 1.0f, MaxKernelSize);

    float result = 0.0f;

    // Get the size of the shadow map
    uint2 shadowMapSize;
    uint numSlices;
    tex2DShadowMap.GetDimensions(shadowMapSize.x, shadowMapSize.y, numSlices);

    float2 texelSize = 1.0f / shadowMapSize;

    //#if UsePlaneDepthBias_
    //    float2 receiverPlaneDepthBias = ComputeReceiverPlaneDepthBias(shadowPosDX, shadowPosDY);

    //    // Static depth biasing to make up for incorrect fractional sampling on the shadow map grid
    //    float fractionalSamplingError = dot(float2(1.0f, 1.0f) * texelSize, abs(receiverPlaneDepthBias));
    //    float shadowDepth = shadowPos.z - min(fractionalSamplingError, 0.01f);
    //#else
    //    float shadowDepth = shadowPos.z - Bias;
    //#endif

    float2 filterSize = f2FilterSize * shadowMapSize;

    [branch]
    if (filterSize.x > 1.0 || filterSize.y > 1.0)
    {
        // Get the texel that will be sampled
        float2 shadowTexel = SamplingInfo.f2UV * shadowMapSize;
        float2 texelFraction = frac(shadowTexel);

        float2 Radius = filterSize / 2.0;

        int2 minOffset = int2(floor(texelFraction - Radius));
        int2 maxOffset = int2(texelFraction + Radius);

        float weightSum = 0.0;

        [loop]
        for(int y = minOffset.y; y <= maxOffset.y; ++y)
        {
            float yWeight = 1.0;
            if(y == minOffset.y)
                yWeight = saturate((Radius.y - texelFraction.y) + 1.0 + y);
            else if(y == maxOffset.y)
                yWeight = saturate(Radius.y + texelFraction.y - y);

            [loop]
            for(int x = minOffset.x; x <= maxOffset.x; ++x)
            {
                float2 sampleOffset = texelSize * float2(x, y);
                float2 samplePos = SamplingInfo.f2UV + sampleOffset;

                //#if UsePlaneDepthBias_
                //    // Compute offset and apply planar depth bias
                //    float sampleDepth = shadowDepth + dot(sampleOffset, receiverPlaneDepthBias);
                //#else
                //    float sampleDepth = shadowDepth;
                //#endif

                float sampleDepth = SamplingInfo.fDepth + dot(sampleOffset, f2ReceiverPlaneDepthBias);

                float sample = tex2DShadowMap.SampleCmp(tex2DShadowMap_sampler, float3(samplePos.xy, SamplingInfo.iCascadeIdx), sampleDepth);

                float xWeight = 1.0;
                if(x == minOffset.x)
                    xWeight = saturate((Radius.x - texelFraction.x) + 1.0 + x);
                else if(x == maxOffset.x)
                    xWeight = saturate(Radius.x + texelFraction.x - x);

                float2 sampleCoverage = float2(xWeight, yWeight);

                float sampleWeight = sampleCoverage.x * sampleCoverage.y;
                weightSum += sampleWeight;

                result += sample * sampleWeight;
            }
        }

        result /= weightSum;
    }
    else
    {
        result = tex2DShadowMap.SampleCmp(tex2DShadowMap_sampler, float3(SamplingInfo.f2UV, SamplingInfo.iCascadeIdx), SamplingInfo.fDepth);
    }

    return result;
}
*/

float FilterShadowMapVaryingPCF(in Texture2DArray<float>  tex2DShadowMap,
                                in SamplerComparisonState tex2DShadowMap_sampler,
                                in ShadowMapAttribs       ShadowAttribs,
                                in CascadeSamplingInfo    SamplingInfo,
                                in float2                 f2ReceiverPlaneDepthBias,
                                in float2                 f2FilterSize)
{
    f2FilterSize = float2(5, 5);//max(f2FilterSize * ShadowAttribs.f4ShadowMapDim.xy, float2(1.0, 1.0));
    float2 f2CenterTexel = SamplingInfo.f2UV * ShadowAttribs.f4ShadowMapDim.xy;
    float2 f2MinBnd = f2CenterTexel - f2FilterSize / 2.0;
    float2 f2MaxBnd = f2CenterTexel + f2FilterSize / 2.0;
    int2 MinXY = int2(floor(f2MinBnd));
    int2 MaxXY = int2(ceil(f2MaxBnd));
    float TotalWeight = 0.0;
    float Sum = 0.0;
    [loop]
    for(int x = MinXY.x; x < MaxXY.x; ++x)
    {
        [loop]
        for(int y = MinXY.y; y < MaxXY.y; ++y)
        {
            float2 f2UV = float2(x, y) + float2(0.5, 0.5);
            float HorzWeight = min(f2UV.x + 0.5, f2MaxBnd.x) - max(f2UV.x - 0.5, f2MinBnd.x);
            float VertWeight = min(f2UV.y + 0.5, f2MaxBnd.y) - max(f2UV.y - 0.5, f2MinBnd.y);
            float Weight = HorzWeight * VertWeight;
            const float DepthClamp = 1e-8;
            float fDepth = max(SamplingInfo.fDepth + dot(f2UV - f2CenterTexel, f2ReceiverPlaneDepthBias), DepthClamp);
            f2UV *= ShadowAttribs.f4ShadowMapDim.zw;
            if (f2UV.x > 0.0 && f2UV.y > 0.0 && f2UV.x < 1.0 && f2UV.y < 1.0)
            {
                Sum += tex2DShadowMap.SampleCmp(tex2DShadowMap_sampler, float3(f2UV, SamplingInfo.iCascadeIdx), fDepth) * Weight;
                TotalWeight += Weight;
            }
        }
    }
    return Sum / TotalWeight;
    
    /*
f2FilterSize = float2(6.5, 6.5)  / ShadowAttribs.f4ShadowMapDim.xy;
    int2 i2NumSamples = max(int2(ceil(f2FilterSize * ShadowAttribs.f4ShadowMapDim.xy)) , int2(1,1));
    float sum = 0;
    f2ReceiverPlaneDepthBias *= ShadowAttribs.f4ShadowMapDim.xy;
    [loop]
    for(int x=0; x < i2NumSamples.x; ++x)
    {
        [loop]
        for(int y=0; y < i2NumSamples.y; ++y)
        {
            float2 f2dUV = lerp(-f2FilterSize.xy/2.0, +f2FilterSize.xy/2.0, float2(float(x) + 0.5, float(y)+0.5) / float2(i2NumSamples));
            const float DepthClamp = 1e-8;
            float fDepth = max(SamplingInfo.fDepth + dot(f2dUV, f2ReceiverPlaneDepthBias), DepthClamp);
            sum += tex2DShadowMap.SampleCmp(tex2DShadowMap_sampler, float3(SamplingInfo.f2UV + f2dUV, SamplingInfo.iCascadeIdx), fDepth);
        }
    }
    return sum / float(i2NumSamples.x * i2NumSamples.y);*/
}


float FilterShadowCascade(in ShadowMapAttribs       ShadowAttribs,
                          in Texture2DArray<float>  tex2DShadowMap,
                          in SamplerComparisonState tex2DShadowMap_sampler,
                          in float3                 f3ddXPosInLightViewSpace,
                          in float3                 f3ddYPosInLightViewSpace,
                          in CascadeSamplingInfo    SamplingInfo)
{
    float3 f3ddXShadowMapUVDepth  = f3ddXPosInLightViewSpace * SamplingInfo.f3LightSpaceScale * F3NDC_XYZ_TO_UVD_SCALE;
    float3 f3ddYShadowMapUVDepth  = f3ddYPosInLightViewSpace * SamplingInfo.f3LightSpaceScale * F3NDC_XYZ_TO_UVD_SCALE;
    float2 f2DepthSlopeScaledBias = ComputeReceiverPlaneDepthBias(f3ddXShadowMapUVDepth, f3ddYShadowMapUVDepth);
    float2 f2SlopeScaledBiasClamp = float2(ShadowAttribs.fReceiverPlaneDepthBiasClamp, ShadowAttribs.fReceiverPlaneDepthBiasClamp);
    f2DepthSlopeScaledBias = clamp(f2DepthSlopeScaledBias, -f2SlopeScaledBiasClamp, f2SlopeScaledBiasClamp);
    f2DepthSlopeScaledBias *= ShadowAttribs.f4ShadowMapDim.zw;

    float FractionalSamplingError = dot( float2(1.0, 1.0), abs(f2DepthSlopeScaledBias.xy) ) + ShadowAttribs.fFixedDepthBias;
    SamplingInfo.fDepth -= FractionalSamplingError;

#if SHADOW_FILTER_SIZE > 0
    return FilterShadowMapFixedPCF(tex2DShadowMap, tex2DShadowMap_sampler, ShadowAttribs.f4ShadowMapDim, SamplingInfo, f2DepthSlopeScaledBias);
#else
    float2 f2FilterSize = ShadowAttribs.fFilterWorldSize * SamplingInfo.f3LightSpaceScale.xy * F3NDC_XYZ_TO_UVD_SCALE.xy;
    return FilterShadowMapVaryingPCF(tex2DShadowMap, tex2DShadowMap_sampler, ShadowAttribs, SamplingInfo, f2DepthSlopeScaledBias, f2FilterSize);
#endif
}


struct FilteredShadow
{
    float fLightAmount;
    int   iCascadeIdx;
    float fNextCascadeBlendAmount;
};

FilteredShadow FilterShadowMap(in ShadowMapAttribs       ShadowAttribs,
                               in Texture2DArray<float>  tex2DShadowMap,
                               in SamplerComparisonState tex2DShadowMap_sampler,
                               in float3                 f3PosInLightViewSpace,
                               in float                  fCameraSpaceZ)
{
    CascadeSamplingInfo SamplingInfo = FindCascade(ShadowAttribs, f3PosInLightViewSpace.xyz, fCameraSpaceZ);
    FilteredShadow Shadow;
    Shadow.iCascadeIdx             = SamplingInfo.iCascadeIdx;
    Shadow.fNextCascadeBlendAmount = 0.0;
    Shadow.fLightAmount            = 1.0;

    if (SamplingInfo.iCascadeIdx == ShadowAttribs.iNumCascades)
        return Shadow;

    float3 f3ddXPosInLightViewSpace = ddx(f3PosInLightViewSpace);
    float3 f3ddYPosInLightViewSpace = ddy(f3PosInLightViewSpace);

    Shadow.fLightAmount = FilterShadowCascade(ShadowAttribs, tex2DShadowMap, tex2DShadowMap_sampler, f3ddXPosInLightViewSpace, f3ddYPosInLightViewSpace, SamplingInfo);
    
#if FILTER_ACROSS_CASCADES
    if (SamplingInfo.iCascadeIdx+1 < ShadowAttribs.iNumCascades)
    {
        CascadeSamplingInfo NextCscdSamplingInfo = GetCascadeSamplingInfo(ShadowAttribs, f3PosInLightViewSpace, SamplingInfo.iCascadeIdx + 1);
        float NextCascadeShadow = FilterShadowCascade(ShadowAttribs, tex2DShadowMap, tex2DShadowMap_sampler, f3ddXPosInLightViewSpace, f3ddYPosInLightViewSpace, NextCscdSamplingInfo);
        Shadow.fNextCascadeBlendAmount = GetNextCascadeBlendAmount(ShadowAttribs, fCameraSpaceZ, SamplingInfo, NextCscdSamplingInfo);
        Shadow.fLightAmount = lerp(Shadow.fLightAmount, NextCascadeShadow, Shadow.fNextCascadeBlendAmount);
    }
#endif

    return Shadow;
}




// Reduces VSM light bleedning
float ReduceLightBleeding(float pMax, float amount)
{
  // Remove the [0, amount] tail and linearly rescale (amount, 1].
   return saturate((pMax - amount) / (1.0 - amount));
}

float ChebyshevUpperBound(float2 f2Moments, float fMean, float fMinVariance, float fLightBleedingReduction)
{
    // Compute variance
    float Variance = f2Moments.y - (f2Moments.x * f2Moments.x);
    Variance = max(Variance, fMinVariance);

    // Compute probabilistic upper bound
    float d = fMean - f2Moments.x;
    float pMax = Variance / (Variance + (d * d));

    pMax = ReduceLightBleeding(pMax, fLightBleedingReduction);

    // One-tailed Chebyshev
    return (fMean <= f2Moments.x ? 1.0 : pMax);
}

float2 GetEVSMExponents(float positiveExponent, float negativeExponent, bool Is32BitFormat)
{
    float maxExponent = Is32BitFormat ? 42.0 : 5.54;
    // Clamp to maximum range of fp32/fp16 to prevent overflow/underflow
    return min(float2(positiveExponent, negativeExponent), float2(maxExponent, maxExponent));
}

// Applies exponential warp to shadow map depth, input depth should be in [0, 1]
float2 WarpDepthEVSM(float depth, float2 exponents)
{
    // Rescale depth into [-1, 1]
    depth = 2.0 * depth - 1.0;
    float pos =  exp( exponents.x * depth);
    float neg = -exp(-exponents.y * depth);
    return float2(pos, neg);
}

float SampleVSM(in ShadowMapAttribs       ShadowAttribs,
                in Texture2DArray<float4> tex2DVSM,
                in SamplerState           tex2DVSM_sampler,
                in CascadeSamplingInfo    SamplingInfo,
                in float2                 f2ddXShadowMapUV,
                in float2                 f2ddYShadowMapUV)
{
    float2 f2Occluder = tex2DVSM.SampleGrad(tex2DVSM_sampler, float3(SamplingInfo.f2UV, SamplingInfo.iCascadeIdx), f2ddXShadowMapUV, f2ddYShadowMapUV).xy;
    return ChebyshevUpperBound(f2Occluder, SamplingInfo.fDepth, ShadowAttribs.fVSMBias, ShadowAttribs.fVSMLightBleedingReduction);
}

float SampleEVSM(in ShadowMapAttribs       ShadowAttribs,
                 in Texture2DArray<float4> tex2DEVSM,
                 in SamplerState           tex2DEVSM_sampler,
                 in CascadeSamplingInfo    SamplingInfo,
                 in float2                 f2ddXShadowMapUV,
                 in float2                 f2ddYShadowMapUV)
{
    float2 f2Exponents = GetEVSMExponents(ShadowAttribs.fEVSMPositiveExponent, ShadowAttribs.fEVSMNegativeExponent, ShadowAttribs.bIs32BitEVSM);
    float2 f2WarpedDepth = WarpDepthEVSM(SamplingInfo.fDepth, f2Exponents);

    float4 f4Occluder = tex2DEVSM.SampleGrad(tex2DEVSM_sampler, float3(SamplingInfo.f2UV, SamplingInfo.iCascadeIdx), f2ddXShadowMapUV, f2ddYShadowMapUV);

    // Derivative of warping at depth
    float2 f2DepthScale = ShadowAttribs.fVSMBias * f2Exponents * f2WarpedDepth;
    float2 f2MinVariance = f2DepthScale * f2DepthScale;

    float fContrib = ChebyshevUpperBound(f4Occluder.xy, f2WarpedDepth.x, f2MinVariance.x, ShadowAttribs.fVSMLightBleedingReduction);
    #if SHADOW_MODE == SHADOW_MODE_EVSM4
        float fNegContrib = ChebyshevUpperBound(f4Occluder.zw, f2WarpedDepth.y, f2MinVariance.y, ShadowAttribs.fVSMLightBleedingReduction);
        fContrib = min(fContrib, fNegContrib);
    #endif

    return fContrib;
}

float SampleFilterableShadowCascade(in ShadowMapAttribs       ShadowAttribs,
                                    in Texture2DArray<float4> tex2DShadowMap,
                                    in SamplerState           tex2DShadowMap_sampler,
                                    in float3                 f3ddXPosInLightViewSpace,
                                    in float3                 f3ddYPosInLightViewSpace,
                                    in CascadeSamplingInfo    SamplingInfo)
{
    float3 f3ddXShadowMapUVDepth = f3ddXPosInLightViewSpace * SamplingInfo.f3LightSpaceScale * F3NDC_XYZ_TO_UVD_SCALE;
    float3 f3ddYShadowMapUVDepth = f3ddYPosInLightViewSpace * SamplingInfo.f3LightSpaceScale * F3NDC_XYZ_TO_UVD_SCALE;
#if SHADOW_MODE == SHADOW_MODE_VSM
    return SampleVSM(ShadowAttribs, tex2DShadowMap, tex2DShadowMap_sampler, SamplingInfo, f3ddXShadowMapUVDepth.xy, f3ddYShadowMapUVDepth.xy);
#elif SHADOW_MODE == SHADOW_MODE_EVSM2 || SHADOW_MODE == SHADOW_MODE_EVSM4
    return SampleEVSM(ShadowAttribs, tex2DShadowMap, tex2DShadowMap_sampler, SamplingInfo, f3ddXShadowMapUVDepth.xy, f3ddYShadowMapUVDepth.xy);
#else
    return 1.0;
#endif
}

FilteredShadow SampleFilterableShadowMap(in ShadowMapAttribs       ShadowAttribs,
                                         in Texture2DArray<float4> tex2DShadowMap,
                                         in SamplerState           tex2DShadowMap_sampler,
                                         in float3                 f3PosInLightViewSpace,
                                         in float                  fCameraSpaceZ)
{
    CascadeSamplingInfo SamplingInfo = FindCascade(ShadowAttribs, f3PosInLightViewSpace.xyz, fCameraSpaceZ);
    FilteredShadow Shadow;
    Shadow.iCascadeIdx             = SamplingInfo.iCascadeIdx;
    Shadow.fNextCascadeBlendAmount = 0.0;
    Shadow.fLightAmount            = 1.0;

    if (SamplingInfo.iCascadeIdx == ShadowAttribs.iNumCascades)
        return Shadow;

    float3 f3ddXPosInLightViewSpace = ddx(f3PosInLightViewSpace);
    float3 f3ddYPosInLightViewSpace = ddy(f3PosInLightViewSpace);

    Shadow.fLightAmount = SampleFilterableShadowCascade(ShadowAttribs, tex2DShadowMap, tex2DShadowMap_sampler, f3ddXPosInLightViewSpace, f3ddYPosInLightViewSpace, SamplingInfo);

#if FILTER_ACROSS_CASCADES
    if (SamplingInfo.iCascadeIdx+1 < ShadowAttribs.iNumCascades)
    {
        CascadeSamplingInfo NextCscdSamplingInfo = GetCascadeSamplingInfo(ShadowAttribs, f3PosInLightViewSpace, SamplingInfo.iCascadeIdx + 1);
        float NextCascadeShadow = SampleFilterableShadowCascade(ShadowAttribs, tex2DShadowMap, tex2DShadowMap_sampler, f3ddXPosInLightViewSpace, f3ddYPosInLightViewSpace, NextCscdSamplingInfo);
        Shadow.fNextCascadeBlendAmount = GetNextCascadeBlendAmount(ShadowAttribs, fCameraSpaceZ, SamplingInfo, NextCscdSamplingInfo);
        Shadow.fLightAmount = lerp(Shadow.fLightAmount, NextCascadeShadow, Shadow.fNextCascadeBlendAmount);
    }
#endif

    return Shadow;
}




float3 GetCascadeColor(FilteredShadow Shadow)
{
    float3 f3CascadeColors[MAX_CASCADES];
    f3CascadeColors[0] = float3(0,1,0);
    f3CascadeColors[1] = float3(0,0,1);
    f3CascadeColors[2] = float3(1,1,0);
    f3CascadeColors[3] = float3(0,1,1);
    f3CascadeColors[4] = float3(1,0,1);
    f3CascadeColors[5] = float3(0.3, 1, 0.7);
    f3CascadeColors[6] = float3(0.7, 0.3,1);
    f3CascadeColors[7] = float3(1, 0.7, 0.3);
    float3 Color = f3CascadeColors[min(Shadow.iCascadeIdx, MAX_CASCADES-1)];
#if FILTER_ACROSS_CASCADES
    float3 NextCascadeColor = f3CascadeColors[min(Shadow.iCascadeIdx+1, MAX_CASCADES-1)];
    Color = lerp(Color, NextCascadeColor, Shadow.fNextCascadeBlendAmount);
#endif
    return Color;
}

#endif //_SHADOWS_FXH_