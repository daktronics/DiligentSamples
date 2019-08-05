/*     Copyright 2015-2019 Egor Yusov
 *  
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF ANY PROPRIETARY RIGHTS.
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

#pragma once 

#include "SampleBase.h"
#include "BasicMath.h"

namespace Diligent
{

class Tutorial07_GeometryShader final : public SampleBase
{
public:
    virtual void GetEngineInitializationAttribs(DeviceType        DevType, 
                                                EngineCreateInfo& Attribs)override final;
    virtual void Initialize(IEngineFactory*  pEngineFactory,
                            IRenderDevice*   pDevice, 
                            IDeviceContext** ppContexts, 
                            Uint32           NumDeferredCtx, 
                            ISwapChain*      pSwapChain)override final;
    virtual void Render()override final;
    virtual void Update(double CurrTime, double ElapsedTime)override final;
    virtual const Char* GetSampleName()const override final{return "Tutorial07: Geometry Shader";}

private:
    void CreatePipelineState();
    void CreateVertexBuffer();
    void CreateIndexBuffer();
    void LoadTexture();
    void InitUI();

    RefCntAutoPtr<IPipelineState> m_pPSO;
    RefCntAutoPtr<IBuffer> m_CubeVertexBuffer;
    RefCntAutoPtr<IBuffer> m_CubeIndexBuffer;
    RefCntAutoPtr<IBuffer> m_ShaderConstants;
    RefCntAutoPtr<ITextureView> m_TextureSRV;
    RefCntAutoPtr<IShaderResourceBinding> m_SRB;
    float4x4 m_WorldViewProjMatrix;
    float m_LineWidth = 3.f;
};

}
