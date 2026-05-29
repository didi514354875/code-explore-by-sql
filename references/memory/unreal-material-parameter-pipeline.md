---
name: unreal-material-parameter-pipeline
description: UE材质表达式→HLSL编译→FUniformExpressionSet→Preshader VM→GPU cbuffer完整链路，含实际源码片段和行号
metadata:
  type: reference
  originSessionId: b8787d42-28da-400d-a159-c2a6aec630af
  updatedSessionId: current
---

# Unreal Engine 材质参数管道 — 完整链路

基于 UE 5.x 源码实际提取（MaterialUniformExpressions.h/cpp、MaterialRenderProxy.cpp、Preshader.cpp、PreshaderEvaluate.h、ShaderBaseClasses.cpp、MaterialShared.h）

## 总体架构

```
编辑期 (Compile Time)
  UMaterial 表达式图
    → FHLSLMaterialTranslator (翻译器)
      → HLSL 代码 (GPU 端)
      → FUniformExpressionSet (参数元数据 + Preshader 字节码)
      → FRHIUniformBufferLayout ("Material" cbuffer 布局)
      存入 FMaterialShaderMap / DDC

运行时 CPU
  FMaterialRenderProxy::EvaluateUniformExpressions()
    → FUniformExpressionSet::FillUniformBuffer()
      → 直接参数求值 (标量/向量/纹理)
      → Preshader VM 求值 (复杂表达式)
    → RHICreateUniformBuffer()

运行时 GPU
  FMaterialShader::GetShaderBindings()
    → ShaderBindings.Add(MaterialUniformBuffer, Cache.UniformBuffer)
    → GPU Shader: Material.PreshaderBuffer[i]
```

---

## 第 1 层：编译期 — 表达式如何变成字节码

### FMaterialUniformExpression 类型体系

**文件**: `Engine/Source/Runtime/Engine/Private/Materials/MaterialUniformExpressions.h:602`

```cpp
class FMaterialUniformExpression : public FRefCountedObject
{
public:
    virtual ~FMaterialUniformExpression() {}
    virtual FMaterialUniformExpressionType* GetType() const = 0;
    virtual class FMaterialUniformExpressionTexture* GetTextureUniformExpression() { return nullptr; }
    virtual class FMaterialUniformExpressionExternalTexture* GetExternalTextureUniformExpression() { return nullptr; }
    virtual bool IsConstant() const { return false; }
    virtual bool IsIdentical(const FMaterialUniformExpression* OtherExpression) const { return false; }

    // 生成 Preshader 字节码
    virtual void WriteNumberOpcodes(UE::Shader::FPreshaderData& OutData) const;

    // 直接取值（简单常量）
    virtual void GetNumberValue(const struct FMaterialRenderContext& Context, FLinearColor& OutValue) const;
};
```

通过宏注册类型：
```cpp
#define DECLARE_MATERIALUNIFORMEXPRESSION_TYPE(Name) \
    public: \
    static FMaterialUniformExpressionType StaticType; \
    virtual FMaterialUniformExpressionType* GetType() const { return &StaticType; }

#define IMPLEMENT_MATERIALUNIFORMEXPRESSION_TYPE(Name) \
    FMaterialUniformExpressionType Name::StaticType(TEXT(#Name));
```

关键子类：
| 表达式类型 | 用途 |
|-----------|------|
| `FMaterialUniformExpressionScalarParameter` | 标量参数 (Metallic, Roughness) |
| `FMaterialUniformExpressionVectorParameter` | 向量参数 (BaseColor) |
| `FMaterialUniformExpressionTexture` | 纹理参数 |
| `FMaterialUniformExpressionTime` | 时间驱动动画 |
| `FMaterialUniformExpressionFoldedMath` | 可折叠为常量的数学运算 |
| `FMaterialUniformExpressionExternalTexture` | 外部纹理 |

### 编译器如何决定：Preshader vs GPU HLSL？

在 `FHLSLMaterialTranslator::Translate()` 中：
- **只依赖 uniform** 的表达式（参数常量、Time、数学运算等）→ 编译为 **Preshader 字节码**，在 CPU 端求值
- **依赖插值顶点数据** 的表达式（TexCoord、WorldNormal、VertexColor 等）→ 编译为 **GPU HLSL**，在 Shader 中逐像素计算
- 调用 `AddUniformExpression()` 注册到 `FUniformExpressionSet`

---

## 第 2 层：FUniformExpressionSet — 参数元数据中心

**文件**: `Engine/Source/Runtime/Engine/Public/MaterialShared.h`
**Type Layout 注册**: `Engine/Source/Runtime/Engine/Private/Materials/MaterialShared.cpp:4007` — `IMPLEMENT_TYPE_LAYOUT(FUniformExpressionSet)`

```cpp
struct FUniformExpressionSet
{
    // === 直接参数 (简单标量/向量，走材质实例链解析) ===
    TMemoryImageArray<FMaterialUniformParameterEvaluation> UniformParameterEvaluations;

    // === Preshader (复杂表达式 → 字节码VM) ===
    TMemoryImageArray<FMaterialUniformPreshaderHeader> UniformPreshaders;
    FPreshaderData UniformPreshaderData;          // 字节码
    uint32 UniformPreshaderBufferSize;            // Preshader 结果占用 buffer 大小

    // === 标量参数元信息 ===
    TMemoryImageArray<FMaterialNumericParameterInfo> UniformNumericParameters;

    // === 纹理参数 (7种类型: 2D, Cube, 3D, Virtual, Volume, SparseVolume...) ===
    TMemoryImageArray<FMaterialTextureParameterInfo> UniformTextureParameters[7];

    // === VT 栈 ===
    TMemoryImageArray<FMaterialVirtualTextureStack> VTStacks;

    // === 默认值 (编译快照) ===
    TMemoryImageArray<uint8> DefaultValues;

    // === Uniform Buffer 布局 (名称为 "Material") ===
    FRHIUniformBufferLayoutInitializer UniformBufferLayoutInitializer;
};
```

---

## 第 3 层：运行时入口 — EvaluateUniformExpressions

**文件**: `Engine/Source/Runtime/Engine/Private/Materials/MaterialRenderProxy.cpp:13834`

```cpp
void FMaterialRenderProxy::EvaluateUniformExpressions(
    FRHICommandListBase& RHICmdList,
    FUniformExpressionCache& OutUniformExpressionCache,
    const FMaterialRenderContext& Context,
    FUniformExpressionCacheAsyncUpdater* Updater) const
{
    SCOPE_CYCLE_COUNTER(STAT_CacheUniformExpressions);

    // 1. 从 ShaderMap 获取编译好的 UniformExpressionSet
    FMaterialShaderMap* ShaderMap = Context.Material.GetRenderingThreadShaderMap();
    const FUniformExpressionSet& UniformExpressionSet = ShaderMap->GetUniformExpressionSet();

    // 2. 先设 null，增大检测线程安全 bug 的窗口
    //    (如果在求值期间被访问，会在 GetShaderBindings 中断言失败)
    OutUniformExpressionCache.CachedUniformExpressionShaderMap = nullptr;

    // 3. 重置 VT 分配
    OutUniformExpressionCache.ResetAllocatedVTs();

    // 4. 为每个 VT 栈分配 AllocatedVT
    // 5. 调用 FillUniformBuffer → 见第4层
    // 6. RHICreateUniformBuffer() 或 UpdateUniformBuffer()
    // 7. OutUniformExpressionCache.CachedUniformExpressionShaderMap = ShaderMap;
}
```

**FUniformExpressionCache** (`MaterialRenderProxy.h:357`):
```cpp
struct FUniformExpressionCache
{
    FUniformBufferRHIRef UniformBuffer;                          // 最终的 RHI Uniform Buffer
    TArray<IAllocatedVirtualTexture*> AllocatedVTs;              // 分配的 VT
    TArray<FGuid> ParameterCollections;                          // 参数集合 GUID
    const FMaterialShaderMap* CachedUniformExpressionShaderMap;  // 用于验证缓存有效性
};
```

---

## 第 4 层：FillUniformBuffer — 如何把参数写入 Buffer

**文件**: `Engine/Source/Runtime/Engine/Private/Materials/MaterialUniformExpressions.cpp:41630`

### 4.1 入口

```cpp
void FUniformExpressionSet::FillUniformBuffer(
    const FMaterialRenderContext& MaterialRenderContext,
    TConstArrayView<IAllocatedVirtualTexture*> AllocatedVTs,
    const FRHIUniformBufferLayout* UniformBufferLayout,
    uint8* TempBuffer, int TempBufferSize) const
{
    using namespace UE::Shader;
    check(IsInParallelRenderingThread());

    if (UniformBufferLayout->ConstantBufferSize > 0)
    {
        void* BufferCursor = TempBuffer;

        // ① VT 集合打包的页面表 uniform
        // ② 每个 VT 栈的页面表数据
        // ③ 每个 VT 图层的打包 uniform
        // ④ Sparse Volume Texture 打包 uniform

        // ⑤ 直接参数评估 (简单标量/向量)
        for (const FMaterialUniformParameterEvaluation& Eval : UniformParameterEvaluations)
        {
            // 材质实例链解析：RenderProxy覆盖 → TransientOverrides → 默认值
            FValue Value = GetParameterValue(Eval, Context);
            CopyValueToUniformBuffer(Value, (float*)TempBuffer, Eval.BufferOffset);
        }

        // ⑥ Preshader 求值 (复杂表达式)
        for (const FMaterialUniformPreshaderHeader& Header : UniformPreshaders)
        {
            FPreshaderDataContext DataContext(UniformPreshaderData,
                Header.OpcodeOffset, Header.OpcodeSize);
            FPreshaderValue Result = EvaluatePreshader(
                this, Context, Stack, DataContext);
            CopyValueToUniformBuffer(Result, (float*)TempBuffer, Header.BufferOffset);
        }
    }
}
```

### 4.2 CopyValueToUniformBuffer — 类型感知写入

```cpp
static void CopyValueToUniformBuffer(
    const UE::Shader::FValue& Value, float* PreshaderBuffer, uint32 BufferOffset)
{
    FValueTypeDescription UniformTypeDesc = GetValueTypeDescription(Value.GetType());

    if (UniformTypeDesc.ComponentType == EValueComponentType::Float)
    {
        // Float: 直接逐分量复制
        FFloatValue FloatValue = Value.AsFloat();
        float* DestAddress = PreshaderBuffer + BufferOffset;
        for (int32 i = 0; i < Value.GetNumComponents(); ++i)
            *DestAddress++ = FloatValue[i];
    }
    else if (UniformTypeDesc.ComponentType == EValueComponentType::Int)
    {
        // Int: 按 int32 写入
        FIntValue IntValue = Value.AsInt();
        int32* DestAddress = (int32*)PreshaderBuffer + BufferOffset;
        for (int32 i = 0; i < Value.GetNumComponents(); ++i)
            *DestAddress++ = IntValue[i];
    }
    else if (UniformTypeDesc.ComponentType == EValueComponentType::Bool)
    {
        // Bool: 按位掩码写入 (32个bool打包为一个uint32)
        FBoolValue BoolValue = Value.AsBool();
        uint32 Mask = 0u;
        for (int32 i = 0; i < Value.GetNumComponents(); ++i)
            if (BoolValue[i]) Mask |= (1u << i);

        uint32 BufferOffsetAdjusted = BufferOffset / 32u;
        uint32 BufferBitOffset = BufferOffset % 32u;
        uint32* DestAddress = (uint32*)PreshaderBuffer + BufferOffsetAdjusted;
        if (BufferBitOffset == 0u)
            *DestAddress = Mask;          // 首次写入初始化
        else
            *DestAddress |= (Mask << BufferBitOffset);  // 与已有位合并
    }
    else if (UniformTypeDesc.ComponentType == EValueComponentType::Double)
    {
        // Double: 拆分为 High/Low 两个 float (模拟 GPU double)
        FDoubleValue DoubleValue = Value.AsDouble();
        float ValueHigh[4] = {}, ValueLow[4] = {};
        for (int32 i = 0; i < Value.GetNumComponents(); ++i) {
            const FDFScalar ScalarValue(DoubleValue[i]);
            ValueHigh[i] = ScalarValue.High;
            ValueLow[i] = ScalarValue.Low;
        }
        float* DestAddress = PreshaderBuffer + BufferOffset;
        for (int32 i = 0; i < Value.GetNumComponents(); ++i)
            *DestAddress++ = ValueHigh[i];
        for (int32 i = 0; i < Value.GetNumComponents(); ++i)
            *DestAddress++ = ValueLow[i];
    }
}
```

### 4.3 直接参数解析链路

```
MaterialRenderProxy->GetParameterShaderValue()  → 渲染代理覆盖
  ↓ 未找到
Material.TransientOverrides.GetNumericOverride() → 编辑器覆盖 (WITH_EDITOR)
  ↓ 未找到
GetDefaultParameterValue() → 编译时默认值（从 DefaultValues 数组）
  ↓
CopyValueToUniformBuffer() → 写入 TempBuffer
```

---

## 第 5 层：Preshader VM — 字节码解释器

**文件声明**: `Engine/Source/Runtime/Engine/Private/Shader/PreshaderEvaluate.h:674`
**文件实现**: `Engine/Source/Runtime/Engine/Private/Shader/Preshader.cpp:47929`

### 5.1 API 声明

```cpp
namespace UE::Shader {

struct FPreshaderDataContext
{
    explicit FPreshaderDataContext(const FPreshaderData& InData);
    FPreshaderDataContext(const FPreshaderDataContext& InContext, uint32 InOffset, uint32 InSize);

    const uint8* RESTRICT Ptr;       // 当前指令指针
    const uint8* RESTRICT EndPtr;    // 字节码范围末尾
    TArrayView<const FScriptName> Names;
    TArrayView<const FPreshaderStructType> StructTypes;
    TArrayView<const EValueComponentType> StructComponentTypes;
};

ENGINE_API FPreshaderValue EvaluatePreshader(
    const FUniformExpressionSet* UniformExpressionSet,
    const FMaterialRenderContext& Context,
    FPreshaderStack& Stack,                    // 运行时栈
    FPreshaderDataContext& RESTRICT Data);     // 字节码上下文
}
```

### 5.2 VM 主循环 (~50 种操作码)

```cpp
FPreshaderValue EvaluatePreshader(
    const FUniformExpressionSet* UniformExpressionSet,
    const FMaterialRenderContext& Context,
    FPreshaderStack& Stack,
    FPreshaderDataContext& RESTRICT Data)
{
    uint8 const* const DataEnd = Data.EndPtr;
    Stack.Reset();

    while (Data.Ptr < DataEnd)
    {
        const EPreshaderOpcode Opcode = (EPreshaderOpcode)ReadPreshaderValue<uint8>(Data);
        switch (Opcode)
        {
        case ConstantZero:    EvaluateConstantZero(Stack, Data); break;
        case Constant:        EvaluateConstant(Stack, Data); break;
        case GetField:        EvaluateGetField(Stack, Data); break;
        case SetField:        EvaluateSetField(Stack, Data); break;
        case Parameter:       EvaluateParameter(Stack, UniformExpressionSet,
                                   ReadPreshaderValue<uint16>(Data), Context); break;
        case PushValue:       EvaluatePushValue(Stack, Data); break;
        case Assign:          EvaluateAssign(Stack); break;
        // 二元运算
        case Add:  EvaluateBinaryOpInPlace(Stack, AddInPlace, Add); break;
        case Sub:  EvaluateBinaryOpInPlace(Stack, SubInPlace, Sub); break;
        case Mul:  EvaluateBinaryOpInPlace(Stack, MulInPlace, Mul); break;
        case Div:  EvaluateBinaryOpInPlace(Stack, DivInPlace, Div); break;
        case Less: EvaluateBinaryOp(Stack, Less); break;
        case Greater: EvaluateBinaryOp(Stack, Greater); break;
        case LessEqual: EvaluateBinaryOp(Stack, LessEqual); break;
        case GreaterEqual: EvaluateBinaryOp(Stack, GreaterEqual); break;
        case Fmod:   EvaluateBinaryOpInPlace(Stack, FmodInPlace, Fmod); break;
        case Modulo: EvaluateBinaryOpInPlace(Stack, ModuloInPlace, Modulo); break;
        case Min: EvaluateBinaryOpInPlace(Stack, MinInPlace, Min); break;
        case Max: EvaluateBinaryOpInPlace(Stack, MaxInPlace, Max); break;
        case Clamp: /* ... */ break;
        // 三角函数
        case Sin: case Cos: case Tan: case Asin: case Acos: case Atan: case Atan2: /* ... */
        // 数学函数
        case Sqrt: case Rcp: case Length: case Normalize: /* ... */
        case Abs: case Floor: case Ceil: case Round: case Trunc: case Sign: case Frac: /* ... */
        case Log2: case Log10: case Exp: case Exp2: /* ... */
        // 向量操作
        case Dot: case Cross: /* ... */
        case ComponentSwizzle: case AppendVector: /* ... */
        // 控制流
        case Jump: case JumpIfFalse: /* ... */
        // 纹理
        case TextureSize: case TexelSize: /* ... */
        }
    }
    return Stack.PopValue();
}
```

### 5.3 条件跳转实现

```cpp
static void EvaluateJump(FPreshaderDataContext& RESTRICT Data)
{
    const int32 JumpOffset = ReadPreshaderValue<int32>(Data);
    check(Data.Ptr + JumpOffset <= Data.EndPtr);
    Data.Ptr += JumpOffset;
}

static void EvaluateJumpIfFalse(FPreshaderStack& Stack, FPreshaderDataContext& RESTRICT Data)
{
    const int32 JumpOffset = ReadPreshaderValue<int32>(Data);
    const FValue ConditionValue = Stack.PopValue().AsShaderValue();
    if (!ConditionValue.AsBoolScalar())
        Data.Ptr += JumpOffset;  // 条件为假时跳转
}
```

### 5.4 GPU 端访问生成的代码

**文件**: `Engine/Source/Runtime/Engine/Private/Materials/MaterialUniformExpressions.cpp:31` — `WriteMaterialUniformAccess()`

```cpp
void WriteMaterialUniformAccess(uint32 NumComponents, uint32 UniformOffset, FStringBuilderBase& OutResult)
{
    uint32 RegisterIndex = UniformOffset / 4;
    uint32 RegisterOffset = UniformOffset % 4;
    // 生成: Material.PreshaderBuffer[3].xy
    //   或: float3(Material.PreshaderBuffer[1], Material.PreshaderBuffer[2].x)
    OutResult.Appendf(TEXT("Material.PreshaderBuffer[%u]"), RegisterIndex);
}
```

**为什么需要 VM？** 编译期无法确定参数的具体值（材质实例可能运行时才创建），但可以在编译期生成求值表达式序列。运行时只需执行字节码即可得到最终值 — 避免 GPU 重复计算常量表达式。

---

## 第 6 层：GPU 绑定 — 数据如何进入 Shader

**文件**: `Engine/Source/Runtime/Renderer/Private/ShaderBaseClasses.cpp:15001`

### 6.1 Uniform Buffer 名称

```cpp
// MaterialShader.h
FName FMaterialShader::UniformBufferLayoutName(TEXT("Material"));
```

### 6.2 FMaterialShader 构造函数 — 编译期绑定

```cpp
FMaterialShader::FMaterialShader(const CompiledShaderInitializerType& Initializer)
{
    // 绑定 "Material" uniform buffer parameter
    MaterialUniformBuffer.Bind(Initializer.ParameterMap, TEXT("Material"));

    // 绑定参数集合 uniform buffers (MaterialCollection0, MaterialCollection1, ...)
    for (CollectionIndex : UniformExpressionSet.ParameterCollections)
    {
        FShaderUniformBufferParameter CollectionParameter;
        CollectionParameter.Bind(Initializer.ParameterMap,
            *FString::Printf(TEXT("MaterialCollection%u"), CollectionIndex));
        ParameterCollectionUniformBuffers.Add(CollectionParameter);
    }
}
```

### 6.3 GetShaderBindings — 每帧调用

```cpp
void FMaterialShader::GetShaderBindings(
    const FSceneInterface* Scene,
    const ERHIFeatureLevel::Type FeatureLevel,
    const FMaterialRenderProxy& MaterialRenderProxy,
    const FMaterial& Material,
    FMeshDrawSingleShaderBindings& ShaderBindings) const
{
    // 1. 从 RenderProxy 获取缓存的 Uniform Buffer
    const FUniformExpressionCache& UniformExpressionCache =
        MaterialRenderProxy.UniformExpressionCache[FeatureLevel];

    // 2. 验证缓存有效 (ShaderMap 匹配，防止 UMaterial 被重新编译后的悬空指针)
    check(UniformExpressionCache.CachedUniformExpressionShaderMap
        == Material.GetRenderingThreadShaderMap());
    check(UniformExpressionCache.UniformBuffer);

    // 3. 绑定主 Material Uniform Buffer ← 零拷贝
    ShaderBindings.Add(MaterialUniformBuffer, UniformExpressionCache.UniformBuffer);

    // 4. 绑定参数集合 Uniform Buffers (MaterialCollection0, MaterialCollection1, ...)
    const TArray<FGuid>& ParameterCollections = UniformExpressionCache.ParameterCollections;
    int32 NumToSet = FMath::Min(ParameterCollectionUniformBuffers.Num(), ParameterCollections.Num());
    for (int32 CollectionIndex = 0; CollectionIndex < NumToSet; CollectionIndex++)
    {
        FRHIUniformBuffer* UniformBuffer = GetParameterCollectionBuffer(
            ParameterCollections[CollectionIndex], Scene);
        SetUniformBufferParameter(BatchedParameters,
            ParameterCollectionUniformBuffers[CollectionIndex], UniformBuffer);
    }
}
```

### 6.4 GPU Shader 侧消费

在生成的 Pixel Shader 中（`MaterialTemplate.ush`）：
```hlsl
// CPU 预计算值:
Material.PreshaderBuffer[3].xy          // float2
Material.PreshaderBuffer[1]             // float4
float3(Material.PreshaderBuffer[1], Material.PreshaderBuffer[2].x)  // float3 跨寄存器

// 纹理直接绑定到 SRV（不经 Uniform Buffer）
// FMaterialPixelParameters 包含插值数据（TexCoords, WorldNormal, VertexColor, SvPosition）
// 组合所有输入 → PixelMaterialInputs (BaseColor, Metallic, Roughness, ...)
```

---

## 完整数据流总结

```
编辑期 (Compile Time):
  UMaterial 表达式图
    │ FHLSLMaterialTranslator::Translate()
    │ ├─ 遍历材质属性链 (BaseColor, Metallic, ...)
    │ ├─ Uniform-only 表达式 → Preshader 字节码
    │ ├─ 顶点依赖表达式 → GPU HLSL code chunks
    │ └─ AddUniformExpression() → FUniformExpressionSet
    ▼
  存储到 FMaterialShaderMap / DDC
    ├─ FUniformExpressionSet (参数描述 + 字节码 + cbuffer 布局)
    └─ HLSL Shader 代码

运行时 CPU (Evaluation):
  FMaterialRenderProxy::CacheUniformExpressions()
    └─ EvaluateUniformExpressions()                     ← MaterialRenderProxy.cpp:13834
       ├─ 获取 FUniformExpressionSet (从 ShaderMap)
       ├─ 分配临时 TempBuffer (ConstantBufferSize 字节)
       ├─ FillUniformBuffer():                          ← MaterialUniformExpressions.cpp:41630
       │   ├─ VT 页面表数据
       │   ├─ 直接参数: 实例链 GetParameterValue() → CopyValueToUniformBuffer()
       │   └─ 复杂参数: EvaluatePreshader() VM 求值 → CopyValueToUniformBuffer()
       └─ RHICreateUniformBuffer(TempBuffer)
          → FUniformExpressionCache::UniformBuffer

运行时 GPU (每帧绘制):
  FMaterialShader::GetShaderBindings()                   ← ShaderBaseClasses.cpp:15001
    ├─ ShaderBindings.Add("Material", Cache.UniformBuffer)    ← 零拷贝绑定
    └─ ShaderBindings.Add("MaterialCollectionN", ...)

  GPU Pixel Shader:
    ├─ Material.PreshaderBuffer[i] → CPU 预计算的参数值
    ├─ 纹理 SRV (直接绑定，不经 Uniform Buffer)
    ├─ FMaterialPixelParameters (插值顶点数据)
    └─ → PixelMaterialInputs (BaseColor, Metallic, Roughness, ...)
```

## 核心设计思想

UE 将材质参数分为两类：
1. **CPU 可预计算**（uniform 参数、数学组合）→ Preshader VM 每帧求值后直接写入 cbuffer，避免 GPU 重复计算
2. **GPU 必须计算**（依赖插值数据）→ 留在 HLSL 中逐像素计算

"编译期字节码生成 + 运行时 VM 求值 + cbuffer 零拷贝绑定" 的三段式架构是 UE 材质系统高性能的关键。

## 关键文件索引

| 文件 | 行号 | 关键内容 |
|------|------|---------|
| `Engine/Private/Materials/MaterialUniformExpressions.h` | 602 | `FMaterialUniformExpression` 基类 + 所有子类声明 |
| `Engine/Private/Materials/MaterialUniformExpressions.cpp` | 41630 | `FillUniformBuffer()` 主实现 |
| `Engine/Private/Materials/MaterialUniformExpressions.cpp` | ~41658 | `CopyValueToUniformBuffer()` — Float/Int/Bool/Double 类型感知写入 |
| `Engine/Private/Materials/MaterialUniformExpressions.cpp` | 31 | `WriteMaterialUniformAccess()` — 生成 `Material.PreshaderBuffer[i]` 访问代码 |
| `Engine/Private/Materials/MaterialRenderProxy.cpp` | 13834 | `EvaluateUniformExpressions()` 运行时入口 |
| `Engine/Public/Materials/MaterialRenderProxy.h` | 357 | `FUniformExpressionCache` (含 `UniformBuffer` + `CachedUniformExpressionShaderMap`) |
| `Engine/Public/MaterialShared.h` | — | `FUniformExpressionSet` 完整定义 |
| `Engine/Private/Materials/MaterialShared.cpp` | 4007 | `IMPLEMENT_TYPE_LAYOUT(FUniformExpressionSet)` |
| `Engine/Public/MaterialCompiler.h` | — | `FMaterialCompiler` 纯虚接口 |
| `Engine/Private/Materials/HLSLMaterialTranslator.h` | — | `FHLSLMaterialTranslator`、`FShaderCodeChunk` |
| `Engine/Private/Materials/HLSLMaterialTranslator.cpp` | 44136 | `Translate()` 编译入口 |
| `Engine/Private/Materials/HLSLMaterialTranslator.cpp` | 143766 | `GetMaterialShaderCode()` 最终 Shader 代码生成 |
| `Engine/Private/Shader/Preshader.h` | — | `FPreshaderData`、`EPreshaderOpcode` 枚举 (~50种) |
| `Engine/Private/Shader/Preshader.cpp` | 47929 | `EvaluatePreshader()` VM 主循环 |
| `Engine/Private/Shader/PreshaderEvaluate.h` | 674 | `EvaluatePreshader()` API 声明 + `FPreshaderDataContext` |
| `Engine/Shaders/Private/MaterialTemplate.ush` | — | `FMaterialPixelParameters`、`Material` uniform buffer |
| `Renderer/Public/MaterialShader.h` | — | `FMaterialShader` (UniformBufferLayoutName="Material") |
| `Renderer/Private/ShaderBaseClasses.cpp` | 15001 | `FMaterialShader::GetShaderBindings()` |
