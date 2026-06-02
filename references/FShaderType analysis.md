 FShaderType 深度架构分析

  一、核心数据全景

  FShaderType（定义于 Source/Runtime/RenderCore/Public/Shader.h:1238-1566）是 Unreal Engine Shader 系统的元类型（Meta-Type），它不是 shader 本身，而是关于 shader 类型的描述符和工厂。其数据可以分为四大类：

  1. 身份与定位元数据（Identity Metadata）

  Name / TypeName / HashedName          — 类型名称，用于序列化和查找
  SourceFilename / HashedSourceFilename — .usf 源文件路径，编译入口
  FunctionName                         — 入口函数名（如 "MainPS"）
  Frequency (EShaderFrequency)         — shader 阶段（VS/PS/CS/RT...）
  TypeSize                             — FShader 子类的 sizeof
  TypeLayout (FTypeLayoutDesc*)        — 反射布局描述

  2. 分型枚举（Dynamic Cast Key）

  ShaderTypeForDynamicCast (EShaderTypeForDynamicCast) — 枚举标识

  这是一个关键设计——不是用虚函数/RTTI，而是用一个枚举 + reinterpret_cast 实现 O(1) 动态转型：

  // Shader.h:1364-1382
  FGlobalShaderType* GetGlobalShaderType() {
      return (ShaderTypeForDynamicCast == EShaderTypeForDynamicCast::Global)
          ? reinterpret_cast<FGlobalShaderType*>(this) : nullptr;
  }

  类型层级包含：Global、Material、MeshMaterial、Niagara、OCIO、ComputeKernel、NNERuntimeIREE 等。

  3. 策略函数指针表（Strategy Function Table）

  这是 FShaderType 最核心的数据——一组 C 函数指针，构成了一个手工打造的虚函数表：

  ConstructSerializedRef   — 从序列化数据反序列化构造 FShader*
  ConstructCompiledRef     — 从编译输出构造 FShader*
  ShouldCompilePermutationRef — 判断某个 permutation 是否需要编译
  ShouldPrecachePermutationRef — 控制 permutation 预缓存策略
  GetRayTracingPayloadTypeRef — RT shader 的 payload 类型
  GetShaderBindingLayoutTypeRef — shader binding layout
  // Editor-only:
  ModifyCompilationEnvironmentRef — 修改编译环境（#defines, includes）
  ValidateCompiledResultRef — 编译后验证
  GetOverrideJobPriorityRef — 编译优先级

  4. 参数反射元数据（Parameter Reflection）

  RootParametersMetadata (FShaderParametersMetadata*) — 根 shader 参数结构体的反射信息
  ReferencedUniformBuffers (TSet<FShaderParametersMetadata*>) — 引用的 uniform buffer 结构集合

  ---
  二、数据在编译管线中的流转

  整个编译管线是 Begin → Compile (Async) → Finish 三阶段模型：

  Phase 1: 注册与发现（静态初始化）

  IMPLEMENT_SHADER_TYPE(, FScreenPS, TEXT("/Engine/Private/ScreenPixelShader.usf"), TEXT("Main"), SF_Pixel)

  这个宏（见 ScreenRendering.cpp:13）在 main() 之前执行，创建 FShaderType 实例，将：
  - Name = "FScreenPS"
  - SourceFilename = "/Engine/Private/ScreenPixelShader.usf"
  - FunctionName = "Main"
  - Frequency = SF_Pixel
  - 各函数指针指向 FScreenPS 的静态方法

  所有 FShaderType 通过 GlobalListLink（TLinkedList<FShaderType*>）串联进全局链表。

  Phase 2: BeginCompileShader — 元数据注入编译输入

  每种 shader 类型子类（FMeshMaterialShaderType、FMaterialShaderType、FNiagaraShaderType 等）都有自己的 BeginCompileShader，但最终都调用 ::GlobalBeginCompileShader()（ShaderCompiler.cpp:3163）。

  关键数据注入点：

  // ShaderCompiler.cpp:3210-3211
  Input.RootParametersStructure = ShaderType->GetRootParametersMetadata();
  Input.ShaderName = ShaderType->GetName();

  GlobalBeginCompileShader 执行的元数据注入序列：

  ┌─────────────────────────┬─────────────────────────────────────────────┬───────────────────────────────────────────────────┐
  │          步骤           │                  数据来源                   │                     注入目标                      │
  ├─────────────────────────┼─────────────────────────────────────────────┼───────────────────────────────────────────────────┤
  │ 平台信息                │ FDataDrivenShaderPlatformInfo               │ Input.Target, Input.ShaderFormat                  │
  ├─────────────────────────┼─────────────────────────────────────────────┼───────────────────────────────────────────────────┤
  │ Shader 阶段定义         │ ShaderType->GetFrequency()                  │ SET_SHADER_DEFINE(PIXELSHADER/VERTEXSHADER/...)   │
  ├─────────────────────────┼─────────────────────────────────────────────┼───────────────────────────────────────────────────┤
  │ 根参数结构              │ ShaderType->GetRootParametersMetadata()     │ Input.RootParametersStructure                     │
  ├─────────────────────────┼─────────────────────────────────────────────┼───────────────────────────────────────────────────┤
  │ Uniform Buffer Includes │ ShaderType->ReferencedUniformBuffers        │ Input.Environment.IncludeVirtualPathToContentsMap │
  ├─────────────────────────┼─────────────────────────────────────────────┼───────────────────────────────────────────────────┤
  │ 编译环境修改            │ ShaderType->ModifyCompilationEnvironmentRef │ Input.Environment (defines, flags)                │
  ├─────────────────────────┼─────────────────────────────────────────────┼───────────────────────────────────────────────────┤
  │ Shader Binding Layout   │ ShaderType->GetShaderBindingLayoutRef       │ RHI binding layout                                │
  └─────────────────────────┴─────────────────────────────────────────────┴───────────────────────────────────────────────────┘

  Phase 3: 异步编译（Shader Compile Worker）

  编译器读取 .usf 源码，根据 FShaderCompilerInput 中的所有 defines、includes、flags 进行编译，产出 FShaderCompilerOutput：

  FShaderCompilerOutput:
    ├── Compiled bytecode (uint8[])
    ├── FShaderParameterMap  — name → {BufferIndex, BaseIndex, Size, Type}
    ├── NumInstructions
    ├── NumTextureSamplers
    └── CodeSize

  FShaderParameterMap 是编译器回馈的元数据核心——它记录了 HLSL 中每个 uniform 变量在编译后的字节码中的精确位置。

  Phase 4: FinishCompileShader — 从编译输出构造运行时 Shader

  // 构造 CompiledShaderInitializerType（Shader.h:1212-1225）
  FShaderCompiledShaderInitializerType(
      Type,                    // FShaderType* — 元类型
      Parameters,              // FShaderType::FParameters* — 类型参数
      PermutationId,           // int32 — permutation 索引
      CompilerOutput,          // 包含 bytecode + ParameterMap
      MaterialShaderMapHash,   // 材质 shader map 哈希
      ShaderPipeline,          // 所属 pipeline
      VertexFactoryType        // 关联的 vertex factory
  );

  // 调用工厂函数
  ShaderType->ConstructCompiled(Initializer);
  // → ConstructCompiledRef(...)
  // → new FScreenPS(Initializer)

  Phase 5: FShader 构造 — 参数绑定建立

  FShader::FShader(const CompiledShaderInitializerType&) （Shader.cpp:762-798）做了两件关键的事：

  第一件：BuildParameterMapInfo(ParameterMap)（Shader.cpp:821-935）

  将编译器输出的 flat parameter map 分类为结构化的 FShaderParameterMapInfo：

  ParameterMap (flat)                    ParameterMapInfo (structured)
  ─────────────────                      ─────────────────────────────
  "View.UniformBuffer" → {Type:UB}  →   UniformBuffers: [{BufferIndex}]
  "MyTexture" → {Type:SRV}          →   SRVs: [{BaseIndex, BufferIndex}]
  "MySampler" → {Type:Sampler}      →   TextureSamplers: [{BaseIndex}]
  "Param.x" → {Type:LooseData}      →   LooseParameterBuffers: [{BaseIndex, Size}]

  第二件：自动绑定 Uniform Buffer

  // Shader.cpp:791-799
  for (auto* StructIt = FShaderParametersMetadata::GetStructList(); StructIt; ...) {
      if (Initializer.ParameterMap.ContainsParameterAllocation(StructIt->GetShaderVariableName())) {
          UniformBufferParameterStructs.Add(StructIt->GetShaderVariableHashedName());
          FShaderUniformBufferParameter& Param = UniformBufferParameters.AddDefaulted_GetRef();
          Param.Bind(Initializer.ParameterMap, StructIt->GetShaderVariableName(), SPF_Mandatory);
      }
  }

  这段代码遍历所有全局注册的 FShaderParametersMetadata（即所有 C++ 中声明的 uniform buffer 结构体），如果编译器输出表明这个 shader 实际使用了某个 uniform buffer，就自动建立绑定。

  ---
  三、运行时绑定与渲染管线使用

  FShaderParameterBindings 的运行时结构

  // Shader.h:749-778
  struct FParameter {
      uint16 BufferIndex;  // 哪个 constant buffer / uniform buffer
      uint16 BaseIndex;    // register 绑定点
      uint16 ByteOffset;   // buffer 内偏移
      uint16 ByteSize;     // 数据大小
  };

  struct FResourceParameter {
      uint16 ByteOffset;
      uint8  BaseIndex;              // shader register 编号
      EUniformBufferBaseType BaseType; // 精确类型（Texture2D, SamplerState, ...）
  };

  运行时渲染管线通过两种方式使用这些绑定：

  1. 显式参数绑定（通过 BEGIN_SHADER_PARAMETER_STRUCT 宏声明的参数）：

  Bindings.BindForRootShaderParameters(this, PermutationId, ParameterMap);

  BindForRootShaderParameters 根据 RootParametersMetadata 的反射信息，将编译器输出中的偏移量映射到 C++ 结构体成员。

  2. 自动 Uniform Buffer 查找（FShader::GetUniformBufferParameter<T>()）：

  template<typename UniformBufferStructType>
  const TShaderUniformBufferParameter<UniformBufferStructType>& GetUniformBufferParameter() const {
      const FShaderParametersMetadata* Metadata = UniformBufferStructType::FTypeInfo::GetStructMetadata();
      // 通过 HashedName 在 UniformBufferParameterStructs 数组中查找
  }

  渲染 Pass 中设置参数的典型模式：
  // 在渲染 Pass 中
  FMyShaderPS* Shader = ...; // 从 ShaderMap 获取编译好的 shader
  RHICmdList.SetShaderParameter(
      Shader->GetPixelShader(),
      Binding.BufferIndex,    // 来自 FShaderParameterBindings
      Binding.ByteOffset,     // 来自编译器输出的偏移
      DataSize,
      &Data                   // C++ 端数据
  );

  ---
  四、逻辑架构与设计哲学

  1. Type Object 模式 + 元编程（Meta-Class Architecture）

  FShaderType 的本质是一个手工打造的元类系统：

  C++ 类型系统          →  UE Shader 元类型系统
  ──────────────         ─────────────────────
  class FScreenPS        →  FShaderType { Name="FScreenPS", Source="ScreenPixelShader.usf" }
  typeof(FScreenPS)      →  FShaderType* (全局注册表中查找)
  new FScreenPS(...)     →  FShaderType::ConstructCompiled(Initializer)
  virtual methods        →  函数指针表 (ShouldCompilePermutation, ModifyCompilationEnvironment, ...)
  dynamic_cast           →  EShaderTypeForDynamicCast 枚举 + reinterpret_cast

  为什么不用 C++ 原生 RTTI？
  - Shader 类型在引擎启动时批量注册，需要跨模块迭代（所有 DLL 中的 shader 都要被发现）
  - 编译时（cooking）需要按名称序列化/反序列化类型引用
  - 运行时需要在无源码情况下动态构造 shader 实例（从 .ushinc / DDCC 加载）
  - 虚函数表会增加每个实例的开销，而 FShaderType 是单例（每个类型一个），用函数指针更节省

  2. 编译时/运行时分离（Compile-Time / Runtime Split）

  这是最核心的设计哲学：

  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
  │   Editor/Cook     │     │   Async Compile  │     │   Game Thread    │
  │                    │     │   Worker         │     │                  │
  │ FShaderType 元数据 │────→│ HLSL → Bytecode  │────→│ FShader 实例     │
  │ + Material/VM     │     │ + ParameterMap   │     │ + Bindings       │
  │ + Permutation     │     │ + Hashes         │     │ + Bytecode ref   │
  └──────────────────┘     └──────────────────┘     └──────────────────┘
          │                         │                         │
     全部是类型信息           编译器产出绑定元数据       运行时只读绑定表

  - Editor 拥有类型系统：FShaderType 的全部函数指针都可用
  - 编译器产出绑定信息：FShaderParameterMap 从编译后的字节码中提取
  - 运行时只有数据表：FShaderParameterBindings 是编译后的静态偏移表，用于直接设置寄存器

  这意味着运行时零反射开销——所有绑定在编译时已经解析为精确的 register offset。

  3. Permutation 矩阵（Variation Explosion 管理）

  TotalPermutationCount
  ShouldCompilePermutation(Parameters)  — 过滤掉不需要的 permutation
  ShouldPrecachePermutation(Parameters) — 控制预缓存策略

  这是一个延迟计算策略：不编译所有可能的 permutation（可能有数千个），而是通过 ShouldCompilePermutation 在材质/平台/feature level 上下文中动态决定哪些需要编译。

  4. Hash-Based 去重与缓存

  SourceHash     — 源码哈希，用于 hot-reload 检测
  OutputHash     — 编译输出哈希，用于去重（不同 material 可能编译出相同代码）
  MaterialShaderMapHash — 材质维度上的 shader map 哈希
  StructureLayoutHash — 参数结构布局哈希

  这是一套content-addressable 缓存系统——通过哈希值唯一标识编译结果，避免重复编译。

  5. 分层架构（Layered Subclassing）

  FShaderType                    (RenderCore — 公共元类型机制)
  ├── FGlobalShaderType          (RenderCore — 不依赖材质的全局 shader)
  ├── FMaterialShaderType        (Engine — 依赖材质但无 vertex factory)
  ├── FMeshMaterialShaderType    (Engine — 依赖材质 + vertex factory)
  ├── FNiagaraShaderType         (Niagara — GPU 粒子系统)
  ├── FComputeKernelShaderType   (ComputeFramework — compute kernel)
  ├── FOpenColorIOShaderType     (OpenColorIO — 色彩空间转换)
  └── FNNERuntimeIREEShaderType  (NNERuntimeIREE — 神经网络推理)

  每一层添加了特定领域的编译逻辑：
  - FGlobalShaderType：无材质依赖，编译最简单
  - FMeshMaterialShaderType：需要 VertexFactory + Material 两维度的编译环境
  - FNiagaraShaderType：从 VM 脚本动态生成 HLSL

  这种分层使得核心编译管线（GlobalBeginCompileShader）保持通用，而领域特定的逻辑通过 ModifyCompilationEnvironment 和 ShouldCompilePermutation 注入。

  ---
  五、总结：设计哲学的五个核心原则

  ┌───────────────────┬──────────────────────────────────────────────────────────┬────────────────────────────┐
  │       原则        │                         实现方式                         │            价值            │
  ├───────────────────┼──────────────────────────────────────────────────────────┼────────────────────────────┤
  │ 元数据驱动        │ FShaderType 作为类型描述符，驱动编译、绑定、序列化全流程 │ 消除硬编码，支持跨模块扩展 │
  ├───────────────────┼──────────────────────────────────────────────────────────┼────────────────────────────┤
  │ 编译时决断        │ 所有参数绑定在编译时解析为精确偏移                       │ 运行时零反射开销           │
  ├───────────────────┼──────────────────────────────────────────────────────────┼────────────────────────────┤
  │ 异步生产者-消费者 │ Begin/Finish 两阶段分离                                  │ 多核并行编译               │
  ├───────────────────┼──────────────────────────────────────────────────────────┼────────────────────────────┤
  │ 哈希去重          │ SourceHash + OutputHash + MaterialShaderMapHash          │ 避免冗余编译和存储         │
  ├───────────────────┼──────────────────────────────────────────────────────────┼────────────────────────────┤
  │ 开闭原则          │ 新 shader 类型只需实现 FShader 子类 + 注册宏             │ 无需修改编译管线核心代码   │
  └───────────────────┴──────────────────────────────────────────────────────────┴────────────────────────────┘

  这是一个经典的类型对象（Type Object）+ 策略模式（Strategy）+ 两阶段构造（Two-Phase Construction） 的组合架构，以最小运行时开销实现了最大灵活性和可扩展性。
