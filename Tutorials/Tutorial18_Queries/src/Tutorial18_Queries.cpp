/*
 *  Copyright 2019-2020 Diligent Graphics LLC
 *  Copyright 2015-2019 Egor Yusov
 *  
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  
 *      http://www.apache.org/licenses/LICENSE-2.0
 *  
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 *  In no event and under no legal theory, whether in tort (including negligence), 
 *  contract, or otherwise, unless required by applicable law (such as deliberate 
 *  and grossly negligent acts) or agreed to in writing, shall any Contributor be
 *  liable for any damages, including any direct, indirect, special, incidental, 
 *  or consequential damages of any character arising as a result of this License or 
 *  out of the use or inability to use the software (including but not limited to damages 
 *  for loss of goodwill, work stoppage, computer failure or malfunction, or any and 
 *  all other commercial damages or losses), even if such Contributor has been advised 
 *  of the possibility of such damages.
 */

#include <sstream>

#include "Tutorial18_Queries.h"
#include "MapHelper.hpp"
#include "GraphicsUtilities.h"
#include "TextureUtilities.h"
#include "CommonlyUsedStates.h"
#include "../../Common/src/TexturedCube.h"
#include "imgui.h"

namespace Diligent
{

SampleBase* CreateSample()
{
    return new Tutorial18_Queries();
}

void Tutorial18_Queries::CreateCubePSO()
{
    // Create a shader source stream factory to load shaders from files.
    RefCntAutoPtr<IShaderSourceInputStreamFactory> pShaderSourceFactory;
    m_pEngineFactory->CreateDefaultShaderSourceStreamFactory(nullptr, &pShaderSourceFactory);

    m_pCubePSO = TexturedCube::CreatePipelineState(m_pDevice,
                                                   m_pSwapChain->GetDesc().ColorBufferFormat,
                                                   m_pSwapChain->GetDesc().DepthBufferFormat,
                                                   pShaderSourceFactory,
                                                   "cube.vsh",
                                                   "cube.psh");

    // Create dynamic uniform buffer that will store our transformation matrix
    // Dynamic buffers can be frequently updated by the CPU
    CreateUniformBuffer(m_pDevice, sizeof(float4x4), "VS constants CB", &m_CubeVSConstants);

    // Since we did not explcitly specify the type for 'Constants' variable, default
    // type (SHADER_RESOURCE_VARIABLE_TYPE_STATIC) will be used. Static variables never
    // change and are bound directly through the pipeline state object.
    m_pCubePSO->GetStaticVariableByName(SHADER_TYPE_VERTEX, "Constants")->Set(m_CubeVSConstants);

    // Since we are using mutable variable, we must create a shader resource binding object
    // http://diligentgraphics.com/2016/03/23/resource-binding-model-in-diligent-engine-2-0/
    m_pCubePSO->CreateShaderResourceBinding(&m_pCubeSRB, true);
}

void Tutorial18_Queries::Initialize(IEngineFactory*  pEngineFactory,
                                    IRenderDevice*   pDevice,
                                    IDeviceContext** ppContexts,
                                    Uint32           NumDeferredCtx,
                                    ISwapChain*      pSwapChain)
{
    SampleBase::Initialize(pEngineFactory, pDevice, ppContexts, NumDeferredCtx, pSwapChain);

    CreateCubePSO();

    // Load textured cube
    m_CubeVertexBuffer = TexturedCube::CreateVertexBuffer(pDevice);
    m_CubeIndexBuffer  = TexturedCube::CreateIndexBuffer(pDevice);
    m_CubeTextureSRV   = TexturedCube::LoadTexture(pDevice, "DGLogo.png")->GetDefaultView(TEXTURE_VIEW_SHADER_RESOURCE);
    // Set cube texture SRV in the SRB
    m_pCubeSRB->GetVariableByName(SHADER_TYPE_PIXEL, "g_Texture")->Set(m_CubeTextureSRV);

    // Check query support
    const auto& Features = pDevice->GetDeviceCaps().Features;
    if (Features.PipelineStatisticsQueries)
    {
        QueryDesc queryDesc;
        queryDesc.Name = "Pipeline statistics query";
        queryDesc.Type = QUERY_TYPE_PIPELINE_STATISTICS;
        m_pPipelineStatsQuery.reset(new ScopedQueryHelper{m_pDevice, queryDesc, 2});
    }

    if (Features.OcclusionQueries)
    {
        QueryDesc queryDesc;
        queryDesc.Name = "Occlusion query";
        queryDesc.Type = QUERY_TYPE_OCCLUSION;
        m_pOcclusionQuery.reset(new ScopedQueryHelper{m_pDevice, queryDesc, 2});
    }

    if (Features.TimestampQueries)
    {
        m_pDurationQuery.reset(new DurationQueryHelper{m_pDevice, 2});
    }
}

void Tutorial18_Queries::UpdateUI()
{
    ImGui::SetNextWindowPos(ImVec2(10, 10), ImGuiCond_FirstUseEver);
    if (ImGui::Begin("Query data", nullptr, ImGuiWindowFlags_AlwaysAutoResize))
    {
        if (m_pPipelineStatsQuery || m_pOcclusionQuery || m_pDurationQuery)
        {
            std::stringstream params_ss, values_ss;
            if (m_pPipelineStatsQuery)
            {
                params_ss << "Input vertices" << std::endl
                          << "Input primitives" << std::endl
                          << "VS Invocations" << std::endl
                          << "Clipping Invocations" << std::endl
                          << "Rasterized Primitives" << std::endl
                          << "PS Invocations" << std::endl;

                values_ss << m_PipelineStatsData.InputVertices << std::endl
                          << m_PipelineStatsData.InputPrimitives << std::endl
                          << m_PipelineStatsData.VSInvocations << std::endl
                          << m_PipelineStatsData.ClippingInvocations << std::endl
                          << m_PipelineStatsData.ClippingPrimitives << std::endl
                          << m_PipelineStatsData.PSInvocations << std::endl;
            }

            if (m_pOcclusionQuery)
            {
                params_ss << "Samples rendered" << std::endl;
                values_ss << m_OcclusionData.NumSamples << std::endl;
            }

            if (m_pDurationQuery)
            {
                params_ss << "Render time (mus)" << std::endl;
                values_ss << static_cast<int>(m_RenderDuration * 1000000) << std::endl;
            }
            ImGui::TextDisabled("%s", params_ss.str().c_str());
            ImGui::SameLine();
            ImGui::TextDisabled("%s", values_ss.str().c_str());
        }
        else
        {
            ImGui::TextDisabled("Queries are not supported by this device");
        }
    }
    ImGui::End();
}

// Render a frame
void Tutorial18_Queries::Render()
{
    auto* pRTV = m_pSwapChain->GetCurrentBackBufferRTV();
    auto* pDSV = m_pSwapChain->GetDepthBufferDSV();
    // Clear the back buffer
    const float ClearColor[] = {0.350f, 0.350f, 0.350f, 1.0f};
    m_pImmediateContext->ClearRenderTarget(pRTV, ClearColor, RESOURCE_STATE_TRANSITION_MODE_TRANSITION);
    m_pImmediateContext->ClearDepthStencil(pDSV, CLEAR_DEPTH_FLAG, 1.f, 0, RESOURCE_STATE_TRANSITION_MODE_TRANSITION);

    {
        // Map the cube's constant buffer and fill it in with its model-view-projection matrix
        MapHelper<float4x4> CBConstants(m_pImmediateContext, m_CubeVSConstants, MAP_WRITE, MAP_FLAG_DISCARD);
        *CBConstants = m_WorldViewProjMatrix.Transpose();
    }

    // Bind vertex and index buffers
    Uint32   offset   = 0;
    IBuffer* pBuffs[] = {m_CubeVertexBuffer};
    m_pImmediateContext->SetVertexBuffers(0, 1, pBuffs, &offset, RESOURCE_STATE_TRANSITION_MODE_TRANSITION, SET_VERTEX_BUFFERS_FLAG_RESET);
    m_pImmediateContext->SetIndexBuffer(m_CubeIndexBuffer, 0, RESOURCE_STATE_TRANSITION_MODE_TRANSITION);

    // Set the cube's pipeline state
    m_pImmediateContext->SetPipelineState(m_pCubePSO);

    // Commit the cube shader's resources
    m_pImmediateContext->CommitShaderResources(m_pCubeSRB, RESOURCE_STATE_TRANSITION_MODE_TRANSITION);

    // Draw the cube
    DrawIndexedAttribs DrawAttrs;
    DrawAttrs.IndexType  = VT_UINT32; // Index type
    DrawAttrs.NumIndices = 36;
    DrawAttrs.Flags      = DRAW_FLAG_VERIFY_ALL; // Verify the state of vertex and index buffers

    // Begin supported queries
    if (m_pPipelineStatsQuery)
        m_pPipelineStatsQuery->Begin(m_pImmediateContext);
    if (m_pOcclusionQuery)
        m_pOcclusionQuery->Begin(m_pImmediateContext);
    if (m_pDurationQuery)
        m_pDurationQuery->Begin(m_pImmediateContext);

    m_pImmediateContext->DrawIndexed(DrawAttrs);

    // End queries
    if (m_pDurationQuery)
        m_pDurationQuery->End(m_pImmediateContext, m_RenderDuration);
    if (m_pOcclusionQuery)
        m_pOcclusionQuery->End(m_pImmediateContext, &m_OcclusionData, sizeof(m_OcclusionData));
    if (m_pPipelineStatsQuery)
        m_pPipelineStatsQuery->End(m_pImmediateContext, &m_PipelineStatsData, sizeof(m_PipelineStatsData));
}

void Tutorial18_Queries::Update(double CurrTime, double ElapsedTime)
{
    SampleBase::Update(CurrTime, ElapsedTime);
    UpdateUI();

    // Set cube world view matrix
    float4x4 CubeWorldView = float4x4::RotationY(static_cast<float>(CurrTime)) * float4x4::RotationX(-PI_F * 0.1f) * float4x4::Translation(0.0f, 0.0f, 5.0f);
    float    NearPlane     = 0.1f;
    float    FarPlane      = 100.f;
    float    aspectRatio   = static_cast<float>(m_pSwapChain->GetDesc().Width) / static_cast<float>(m_pSwapChain->GetDesc().Height);

    // Projection matrix differs between DX and OpenGL
    auto Proj = float4x4::Projection(PI_F / 4.0f, aspectRatio, NearPlane, FarPlane, m_pDevice->GetDeviceCaps().IsGLDevice());

    // Compute world-view-projection matrix
    m_WorldViewProjMatrix = CubeWorldView * Proj;
}

} // namespace Diligent
