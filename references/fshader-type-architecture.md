# FShaderType Logical Architecture

`FShaderType` is the central **registration metadata class** in UE's shader type system. It holds static descriptive information needed for compilation, lookup, and instantiation, but not compiled bytecode (that belongs to `FShader` / `FShaderResource`).

## 1. Information Categories (6 Dimensions)

From `FShaderType` getter methods (`Engine/Source/Runtime/RenderCore/Public/Shader.h:1238-1566`):

| Dimension | Getters | Description |
|-----------|---------|-------------|
| **Identity** | `GetName`, `GetFName`, `GetHashedName` | Type name, FName handle, hashed name |
| **Source Location** | `GetShaderFilename`, `GetHashedShaderFilename`, `GetFunctionName` | .usf file path, entry function name |
| **Type Classification** | `GetFrequency`, `GetTypeForDynamicCast`, `GetLayout`, `GetTypeSize` | Shader frequency (VS/PS/CS...), RTTI enum, memory layout |
| **Permutation** | `GetPermutationCount` | Total permutation count (drives ShouldCompilePermutation) |
| **Parameter Binding** | `GetRootParametersMetadata`, `GetReferencedUniformBuffers` | Root parameter struct, referenced UniformBuffer set |
| **Runtime Tracking** | `GetNumShaders` | Current active compiled instance count |

## 2. Class Hierarchy

```
FShaderType (Shader.h:1238)          <- base: 6 dimensions above
|
+-- FGlobalShaderType (GlobalShader.h:87)
|   + ShouldCompilePermutation, ShouldPrecachePermutation
|   + CompiledShaderInitializerType (compilation initializer)
|
+-- FMaterialShaderType (MaterialShaderType.h:95)
|   + CompiledShaderInitializerType (extends: UniformExpressionSet)
|
+-- FMeshMaterialShaderType (MeshMaterialShaderType.h:26)
|   + CompiledShaderInitializerType (extends: VertexFactoryType)
|
+-- FNiagaraShaderType (NiagaraShaderType.h)
|   + AddUniformBufferIncludesToEnvironment, BeginCompileShaderFromSource
|
+-- FOpenColorIOShaderType (OpenColorIOShaderType.h)
|   + SetupCompileEnvironment (color space conversion params)
|
+-- FComputeKernelShaderType (ComputeKernelShaderType.h)
|   + kernel-specific compilation pipeline
|
+-- FNNERuntimeIREEShaderType (NNERuntimeIREEShaderType.h)
    + NNE inference shader compilation pipeline
```

### Subclass Extensions

- **FGlobalShaderType**: Global shaders (not bound to material/mesh), adds permutation compilation strategy
- **FMaterialShaderType**: Material shaders, `CompiledShaderInitializerType` extends with `FUniformExpressionSet`
- **FMeshMaterialShaderType**: Mesh material shaders, further extends with `FVertexFactoryType` association

## 3. FShaderPipelineType - Pipeline Dimension (Shader.h:1931)

Describes **multi-stage shader pipelines**, composing multiple `FShaderType` instances:

| Info | Method | Meaning |
|------|--------|---------|
| Stage composition | `GetStages()` -> `TArray<FShaderType*>` | Shader types for each pipeline stage |
| Stage capabilities | `HasMeshShader`, `HasGeometry`, `HasPixelShader` | Whether each stage exists |
| Pipeline classification | `IsGlobalTypePipeline`, `IsMaterialTypePipeline`, `IsMeshMaterialTypePipeline` | Pipeline type domain |
| Primary entry file | `GetHashedPrimaryShaderFilename` | Primary shader file identifier |

## 4. FShader - Runtime Instance (Shader.h:829)

`FShader` is the **compiled runtime instance**, holding FShaderType metadata + compilation artifacts:

| Dimension | Method | Content |
|-----------|--------|---------|
| Type association | `GetType`, `GetVertexFactoryType` | Corresponding FShaderType / VertexFactoryType |
| Platform | `GetShaderPlatform`, `GetTarget` | Target platform and compilation target |
| Compilation stats | `GetNumInstructions`, `GetNumTextureSamplers`, `GetCodeSize` | Instruction count, sampler count, bytecode size |
| Parameter binding | `GetUniformBufferParameter` (multiple overloads) | UniformBuffer parameter binding lookup |
| Frozen state | `IsFrozen`, `GetResourceIndex` | Index in shader map and frozen state |

## 5. Compilation Initializer (FShaderCompiledShaderInitializerType, Shader.h:1610)

Bridge from **compilation output to runtime instance**:

- `FShaderType*` - target shader type
- `FShaderParameterMap` - parameter mapping table
- Permutation ID
- Compiler output (bytecode, reflection data)
- Shader map hash
- Subclasses extend this (MaterialShaderType adds UniformExpressionSet, MeshMaterialShaderType adds VertexFactoryType)

## 6. Summary Diagram

```
+---------------------------------------------------+
|                   FShaderType                      |
|  [Identity]  Name, FName, HashedName              |
|  [Source]    Filename, FunctionName                |
|  [Classify]  Frequency, TypeForDynamicCast, Layout |
|  [Permute]   PermutationCount                      |
|  [Params]    RootParametersMetadata, RefUBs        |
|  [Tracking]  NumShaders                            |
+---------------------------------------------------+
|  Subclass extensions (Global/Material/MeshMaterial/ |
|  Niagara/OpenColorIO/Compute/NNE)                  |
|  + domain-specific CompiledShaderInitializerType   |
|  + ShouldCompilePermutation / SetupEnvironment     |
+---------------------------------------------------+
|            FShaderPipelineType                      |
|  [Stages]   Stages(TArray<FShaderType*>)           |
|  [Caps]     HasMeshShader, HasGeometry, HasPixel   |
+---------------------------------------------------+
|              FShader (runtime instance)             |
|  [Artifact]  NumInstructions, CodeSize, Samplers   |
|  [Platform]  ShaderPlatform, Target, ResourceIdx   |
|  [Binding]   UniformBufferParameter lookup         |
+---------------------------------------------------+
```

FShaderType records **"what it is"** (identity, frequency, source location) and **"how to compile"** (permutation count, parameter structure, UniformBuffer dependencies). FShader records **"what was compiled"** (instruction count, bytecode, platform bindings). FShaderPipelineType is the cross-stage orchestration layer, composing multiple FShaderTypes into a complete rendering pipeline.





 FShaderType 逻辑架构
  
  FShaderType 是 UE 着色器类型系统的注册表核心，定义在 Shader.h:1238-1566。它以函数指针表 + 元数据字段的方式记录了一个
   shader 的以下方面：

  1. 身份标识 (Identity)

  ┌──────────────────────────┬───────────────────────────┬──────────────────────────────────────┐
  │           字段           │           类型            │                 含义                 │
  ├──────────────────────────┼───────────────────────────┼──────────────────────────────────────┤
  │ Name                     │ const TCHAR*              │ 着色器类型名字符串，如 "TBasePassPS" │
  ├──────────────────────────┼───────────────────────────┼──────────────────────────────────────┤
  │ TypeName                 │ FName                     │ UE FName 表示                        │
  ├──────────────────────────┼───────────────────────────┼──────────────────────────────────────┤
  │ HashedName               │ FHashedName               │ 哈希化名称，用于快速查找             │
  ├──────────────────────────┼───────────────────────────┼──────────────────────────────────────┤
  │ ShaderTypeForDynamicCast │ EShaderTypeForDynamicCast │ RTTI 替代的枚举，用于安全向下转型    │
  └──────────────────────────┴───────────────────────────┴──────────────────────────────────────┘

  EShaderTypeForDynamicCast 枚举定义了所有合法的子类型（X-macro SHADER_TYPE_LIST）:

  Global, Material, MeshMaterial, Niagara, OCIO, ComputeKernel, NNERuntimeIREE

  2. 源码定位 (Source Location)

  ┌──────────────────────┬──────────────┬─────────────────────────────────────────────────────────────┐
  │         字段         │     类型     │                            含义                             │
  ├──────────────────────┼──────────────┼─────────────────────────────────────────────────────────────┤
  │ SourceFilename       │ const TCHAR* │ .usf 文件路径，如 "/Engine/Private/BasePassPixelShader.usf" │
  ├──────────────────────┼──────────────┼─────────────────────────────────────────────────────────────┤
  │ HashedSourceFilename │ FHashedName  │ 哈希化源文件路径                                            │
  ├──────────────────────┼──────────────┼─────────────────────────────────────────────────────────────┤
  │ FunctionName         │ const TCHAR* │ 入口函数名（如 "Main"）                                     │
  └──────────────────────┴──────────────┴─────────────────────────────────────────────────────────────┘

  3. 着色器阶段 (Shader Frequency)

  ┌───────────┬────────┬────────────────────────────────────────────────────┐
  │   字段    │  类型  │                        含义                        │
  ├───────────┼────────┼────────────────────────────────────────────────────┤
  │ Frequency │ uint32 │ EShaderFrequency — VS/HS/DS/GS/PS/CS/Mesh/AS/MS 等 │
  └───────────┴────────┴────────────────────────────────────────────────────┘

  4. 排列系统 (Permutation)

  ┌──────────────────────────────┬──────────┬──────────────────────────────────────────────────────────┐
  │             字段             │   类型   │                           含义                           │
  ├──────────────────────────────┼──────────┼──────────────────────────────────────────────────────────┤
  │ TotalPermutationCount        │ int32    │ 总排列数（由 FPermutationDomain::PermutationCount 决定） │
  ├──────────────────────────────┼──────────┼──────────────────────────────────────────────────────────┤
  │ ShouldCompilePermutationRef  │ 函数指针 │ 判断某排列是否需要编译                                   │
  ├──────────────────────────────┼──────────┼──────────────────────────────────────────────────────────┤
  │ ShouldPrecachePermutationRef │ 函数指针 │ 判断某排列是否需要预缓存                                 │
  └──────────────────────────────┴──────────┴──────────────────────────────────────────────────────────┘

  5. 类型布局与反射 (Type Layout)

  ┌────────────────────────┬────────────────────────────┬─────────────────────────────────────┐
  │          字段          │            类型            │                含义                 │
  ├────────────────────────┼────────────────────────────┼─────────────────────────────────────┤
  │ TypeLayout             │ FTypeLayoutDesc*           │ 序列化/反射布局描述符               │
  ├────────────────────────┼────────────────────────────┼─────────────────────────────────────┤
  │ TypeSize               │ uint32                     │ sizeof(ShaderClass) — 用于内存分配  │
  ├────────────────────────┼────────────────────────────┼─────────────────────────────────────┤
  │ RootParametersMetadata │ FShaderParametersMetadata* │ 根 shader parameter struct 的元数据 │
  └────────────────────────┴────────────────────────────┴─────────────────────────────────────┘

  6. 构造/序列化函数指针 (Construction)

  ┌────────────────────────┬─────────────────────────────┐
  │        函数指针        │            含义             │
  ├────────────────────────┼─────────────────────────────┤
  │ ConstructSerializedRef │ 从反序列化构造 FShader 实例 │
  ├────────────────────────┼─────────────────────────────┤
  │ ConstructCompiledRef   │ 从编译输出构造 FShader 实例 │
  └────────────────────────┴─────────────────────────────┘

  7. 编译管线钩子 (Compile Pipeline Hooks)

  ┌──────────────────────────────────────────┬─────────────────────────────────────────┐
  │                 函数指针                 │                  含义                   │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┤
  │ GetRayTracingPayloadTypeRef              │ 返回光追 payload 类型                   │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┤
  │ GetShaderBindingLayoutRef                │ 返回 shader binding layout              │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┤
  │ ModifyCompilationEnvironmentRef (Editor) │ 修改编译环境（添加 define、include 等） │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┤
  │ ValidateCompiledResultRef (Editor)       │ 验证编译输出正确性                      │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┤
  │ GetOverrideJobPriorityRef (Editor)       │ 覆盖编译任务优先级                      │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┤
  │ GetPermutationIdStringRef (Editor)       │ 排列 ID 的字符串表示                    │
  └──────────────────────────────────────────┴─────────────────────────────────────────┘

  8. 依赖追踪 (Dependency Tracking, Editor-only)

  ┌──────────────────────────┬──────────────────────────────────┬────────────────────────────────────────────┐
  │           字段           │               类型               │                    含义                    │
  ├──────────────────────────┼──────────────────────────────────┼────────────────────────────────────────────┤
  │ ReferencedUniformBuffers │ TSet<FShaderParametersMetadata*> │ 该 shader 引用的所有 Uniform Buffer 结构体 │
  └──────────────────────────┴──────────────────────────────────┴────────────────────────────────────────────┘

  9. 全局注册 (Global Registry)

  ┌────────────────┬───────────────────────────┬────────────────────┐
  │      字段      │           类型            │        含义        │
  ├────────────────┼───────────────────────────┼────────────────────┤
  │ GlobalListLink │ TLinkedList<FShaderType*> │ 挂入全局链表的节点 │
  └────────────────┴───────────────────────────┴────────────────────┘

  静态方法 GetTypeList()、GetShaderTypeByName()、GetNameToTypeMap() 提供全局查找。

  ---
  子类层次
  
  每个子类增加的维度：

  FShaderType (基类 — 上述全部)
   ├── FGlobalShaderType          + SetupCompileEnvironment / ShouldCompilePipeline (无额外状态)
   ├── FMaterialShaderType        + UniformExpressionSet, MaterialShaderMapHash, Material 绑定
   ├── FMeshMaterialShaderType    + VertexFactoryType 依赖 (mesh 渲染需要顶点工厂)
   ├── FNiagaraShaderType         + Niagara 特定编译逻辑
   ├── FOpenColorIOShaderType     + OCIO 颜色空间转换
   ├── FComputeKernelShaderType   + Compute Kernel
   └── FNNERuntimeIREEShaderType  + NNE 推理运行时

  FShaderPipelineType (管线级分组)

  Shader.h:1931-2014 — 将多个 FShaderType* 组合为渲染管线:

  ┌──────────────────────────────┬───────────────────────────────────┐
  │             字段             │               含义                │
  ├──────────────────────────────┼───────────────────────────────────┤
  │ Stages[]                     │ 有序阶段数组 (PS→GS→DS→HS→VS)     │
  ├──────────────────────────────┼───────────────────────────────────┤
  │ AllStages[SF_NumFrequencies] │ 按 frequency 索引的阶段映射       │
  ├──────────────────────────────┼───────────────────────────────────┤
  │ bShouldOptimizeUnusedOutputs │ 是否为每个管线组合生成独立 shader │
  └──────────────────────────────┴───────────────────────────────────┘

  注册机制

  通过 IMPLEMENT_SHADER_TYPE 宏在全局构造期间自动注册:
  1. 创建静态 FShaderType 实例（包含上述全部元数据 + 函数指针）
  2. 创建 FShaderTypeRegistration 对象，延迟提交到全局注册表
  3. FShaderType::Initialize() 在引擎启动时建立 name→type 映射和 uniform buffer 引用关系



    Unreal Engine FShaderType 逻辑架构
  
  FShaderType (Shader.h:1238-1566) 是 UE 渲染系统中 shader 类的元类（metaclass），描述「一个 shader 是什么」而非
  shader 实例本身（实例是 FShader）。它是 shader 类型注册表、编译入口和反序列化工厂的统一抽象。

  一、继承体系（按用途分类）

  EShaderTypeForDynamicCast (Shader.h:1242-1245) 枚举了 7 个一级子类，分别对应不同 shader 应用场景（通过
  SHADER_TYPE_LIST 宏展开）：

  ┌───────────────────────────┬────────────────┬────────────────────────────────────────────────────────┐
  │           子类            │     枚举值     │                          用途                          │
  ├───────────────────────────┼────────────────┼────────────────────────────────────────────────────────┤
  │ FGlobalShaderType         │ Global         │ 全局 shader（Pass shader、post-process等），不依赖材质 │
  ├───────────────────────────┼────────────────┼────────────────────────────────────────────────────────┤
  │ FMaterialShaderType       │ Material       │ 与材质关联但不需要 vertex factory                      │
  ├───────────────────────────┼────────────────┼────────────────────────────────────────────────────────┤
  │ FMeshMaterialShaderType   │ MeshMaterial   │ 材质 + vertex factory 的组合（最常见的 mesh 渲染路径） │
  ├───────────────────────────┼────────────────┼────────────────────────────────────────────────────────┤
  │ FNiagaraShaderType        │ Niagara        │ Niagara 粒子系统 GPU 模拟 shader                       │
  ├───────────────────────────┼────────────────┼────────────────────────────────────────────────────────┤
  │ FOpenColorIOShaderType    │ OCIO           │ 色彩管理变换 shader                                    │
  ├───────────────────────────┼────────────────┼────────────────────────────────────────────────────────┤
  │ FComputeKernelShaderType  │ ComputeKernel  │ ComputeFramework 自定义 compute kernel                 │
  ├───────────────────────────┼────────────────┼────────────────────────────────────────────────────────┤
  │ FNNERuntimeIREEShaderType │ NNERuntimeIREE │ 神经网络推理 shader                                    │
  └───────────────────────────┴────────────────┴────────────────────────────────────────────────────────┘

  FShaderType 用「枚举标签 + reinterpret_cast」实现轻量级 RTTI——GetGlobalShaderType() / AsGlobalShaderType()
  (Shader.h:1359-1466) 系列方法做向下转型，避免 dynamic_cast 的开销。

  二、一个 shader 类被记录的信息分类（FShaderType 私有字段，Shader.h:1517-1565）

  FShaderType 把"一个 shader 类的所有元信息"分成 6 类：

  1. 身份标识（Identity）

  ┌──────────────────────────┬────────────────────────┬────────────────────────────────────┐
  │           字段           │          类型          │                含义                │
  ├──────────────────────────┼────────────────────────┼────────────────────────────────────┤
  │ Name                     │ const TCHAR*           │ C++ 类型名字面量，如 "FBasePassPS" │
  ├──────────────────────────┼────────────────────────┼────────────────────────────────────┤
  │ TypeName                 │ FName                  │ Name 的 FName 形式                 │
  ├──────────────────────────┼────────────────────────┼────────────────────────────────────┤
  │ HashedName               │ FHashedName            │ 用于 Map 查找的哈希                │
  ├──────────────────────────┼────────────────────────┼────────────────────────────────────┤
  │ ShaderTypeForDynamicCast │ enum                   │ 子类标签（Global/Material/...）    │
  ├──────────────────────────┼────────────────────────┼────────────────────────────────────┤
  │ TypeLayout               │ const FTypeLayoutDesc* │ 反射布局信息（用于序列化）         │
  └──────────────────────────┴────────────────────────┴────────────────────────────────────┘

  2. 源代码定位（Source Code Location）

  ┌──────────────────────┬───────────────────────────────────────────────────┐
  │         字段         │                       含义                        │
  ├──────────────────────┼───────────────────────────────────────────────────┤
  │ SourceFilename       │ .usf 源文件路径                                   │
  ├──────────────────────┼───────────────────────────────────────────────────┤
  │ HashedSourceFilename │ 源文件路径的哈希                                  │
  ├──────────────────────┼───────────────────────────────────────────────────┤
  │ FunctionName         │ shader 入口函数名（如 "MainPS"）                  │
  ├──────────────────────┼───────────────────────────────────────────────────┤
  │ Frequency            │ shader stage（VS/PS/CS/GS/...，EShaderFrequency） │
  └──────────────────────┴───────────────────────────────────────────────────┘

  3. 实例化工厂（Object Construction，函数指针）

  ┌────────────────────────┬───────────────────────────────┐
  │          字段          │             用途              │
  ├────────────────────────┼───────────────────────────────┤
  │ ConstructSerializedRef │ 反序列化时空构造 FShader 实例 │
  ├────────────────────────┼───────────────────────────────┤
  │ ConstructCompiledRef   │ 编译完成后用编译产物构造实例  │
  ├────────────────────────┼───────────────────────────────┤
  │ TypeSize               │ FShader 派生类的 sizeof       │
  └────────────────────────┴───────────────────────────────┘

  4. 编译策略（Compile Policy，函数指针）

  通过若干 typedef 指向静态成员函数，只在编辑器构建时存在(WITH_EDITOR)：

  ┌─────────────────────────────────┬─────────────────────────────────────────────┐
  │              字段               │                  决策内容                   │
  ├─────────────────────────────────┼─────────────────────────────────────────────┤
  │ ShouldCompilePermutationRef     │ 在当前平台/参数下要不要编译这个 permutation │
  ├─────────────────────────────────┼─────────────────────────────────────────────┤
  │ ShouldPrecachePermutationRef    │ PSO 预缓存策略                              │
  ├─────────────────────────────────┼─────────────────────────────────────────────┤
  │ ModifyCompilationEnvironmentRef │ 写入编译宏（OutEnvironment.SetDefine(...))  │
  ├─────────────────────────────────┼─────────────────────────────────────────────┤
  │ ValidateCompiledResultRef       │ 编译后参数校验                              │
  ├─────────────────────────────────┼─────────────────────────────────────────────┤
  │ GetOverrideJobPriorityRef       │ 编译任务优先级 override                     │
  ├─────────────────────────────────┼─────────────────────────────────────────────┤
  │ GetPermutationIdStringRef       │ 调试用的 permutation 描述串                 │
  └─────────────────────────────────┴─────────────────────────────────────────────┘

  5. 排列（Permutations）& 资源绑定

  ┌───────────────────────────────┬────────────────────────────────────────────────────────────────┐
  │             字段              │                              含义                              │
  ├───────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ TotalPermutationCount         │ 该 shader 类的排列总数（domain 笛卡尔积）                      │
  ├───────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ GetRayTracingPayloadTypeRef   │ RT shader payload 类型选择                                     │
  ├───────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ GetShaderBindingLayoutTypeRef │ shader binding layout                                          │
  ├───────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ RootParametersMetadata        │ shader 根参数 struct 的反射元信息（FShaderParametersMetadata） │
  └───────────────────────────────┴────────────────────────────────────────────────────────────────┘

  6. 注册表 & uniform buffer 依赖

  ┌────────────────────────────────────┬─────────────────────────────────────────────────────────────────┐
  │                字段                │                              含义                               │
  ├────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ GlobalListLink                     │ TLinkedList<FShaderType*> 节点，把所有 FShaderType 串成全局链表 │
  ├────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ ReferencedUniformBuffers（编辑器） │ 该 shader 引用的 uniform buffer struct 集合，编辑时热重载会更新 │
  └────────────────────────────────────┴─────────────────────────────────────────────────────────────────┘

  三、全局注册机制

  FShaderType 在构造时（即 C++ 静态初始化期）：
  1. 把 this 插入 GlobalListLink 全局链表 → GetTypeList() (Shader.h:1271)
  2. 注册进 GetNameToTypeMap() 哈希表 (Shader.h:1279) 供按名查找
  3. 同时进入 GetSortedShaderTypes(Type) 数组（Shader.cpp:static TArray<FShaderType*>* SortedTypesArray），按子类分桶

  这套机制使得 所有 IMPLEMENT_SHADER_TYPE 宏在 main() 之前就完成了元类注册，运行时按名/按文件名/按子类即可枚举所有
  shader 类。

  四、关键查询入口（静态方法，Shader.h:1273-1283）

  ┌───────────────────────────────────────────┬────────────────────────────────────────────────────────┐
  │                   方法                    │                          作用                          │
  ├───────────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ GetTypeList()                             │ 拿到全部 FShaderType* 链表                             │
  ├───────────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ GetShaderTypeByName(Name)                 │ 按 C++ 类名查找                                        │
  ├───────────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ GetShaderTypesByFilename(usf)             │ 按源文件查找（修改某个 .usf 时找出受影响的 shader 类） │
  ├───────────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ GetNameToTypeMap()                        │ 全局 FHashedName -> FShaderType* 表                    │
  ├───────────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ GetSortedTypes(EShaderTypeForDynamicCast) │ 按一级分类拿到该桶的所有类型                           │
  ├───────────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ Initialize(...)                           │ 静态初始化：解析每个 usf 引用的 uniform buffer         │
  └───────────────────────────────────────────┴────────────────────────────────────────────────────────┘

  总结一句话

  FShaderType 把 "一个 shader 类" 拆解为「身份 + 源码定位 + 实例工厂 + 编译策略 + 排列/绑定 + 
  注册表」六类元数据，并通过 7 个一级子类（Global/Material/MeshMaterial/Niagara/OCIO/ComputeKernel/NNERuntimeIREE）分
  桶管理；构造期自动注册到全局链表与哈希表中，使 shader 编译管线可以按名字、按 usf 源文件、按类别枚举所有 shader。