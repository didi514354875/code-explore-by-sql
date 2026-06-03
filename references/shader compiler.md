  1️⃣ FShaderPipelineType 是什么

  FShaderPipelineType (Source/Runtime/RenderCore/Public/Shader.h:1930) 是 Unreal 渲染系统中将多个 Shader Stage 绑定为一个完整图形管线的类型系统。

  它的核心字段极简：

  class FShaderPipelineType {
      const TCHAR* Name;
      TArray<const FShaderType*> Stages;     // 有序的 stage 列表
      const FShaderType* AllStages[SF_NumFrequencies]; // 按频率索引
      bool bShouldOptimizeUnusedOutputs;     // 是否生成独立的专用 shader
      // 还有全局链表、排序数组等管理结构
  };

  注册方式

  通过 6 个宏声明（Shader.h:2018-2035）：

  ┌──────────────────────────────────────┬──────────────────────────────┐
  │                  宏                  │          Stage 组合          │
  ├──────────────────────────────────────┼──────────────────────────────┤
  │ IMPLEMENT_SHADERPIPELINE_TYPE_VSPS   │ Vertex + Pixel               │
  ├──────────────────────────────────────┼──────────────────────────────┤
  │ IMPLEMENT_SHADERPIPELINE_TYPE_VS     │ Vertex only                  │
  ├──────────────────────────────────────┼──────────────────────────────┤
  │ IMPLEMENT_SHADERPIPELINE_TYPE_VSGSPS │ Vertex + Geometry + Pixel    │
  ├──────────────────────────────────────┼──────────────────────────────┤
  │ IMPLEMENT_SHADERPIPELINE_TYPE_VSGS   │ Vertex + Geometry            │
  ├──────────────────────────────────────┼──────────────────────────────┤
  │ IMPLEMENT_SHADERPIPELINE_TYPE_MSPS   │ Mesh + Pixel                 │
  ├──────────────────────────────────────┼──────────────────────────────┤
  │ IMPLEMENT_SHADERPIPELINE_TYPE_MSASPS │ Mesh + Amplification + Pixel │
  └──────────────────────────────────────┴──────────────────────────────┘

  最后一个参数 bRemoveUnused 决定 pipeline 行为模式（见下节）。

  三大家族

  Pipeline 的类型由它的第一个 shader stage 的 GetTypeForDynamicCast() 决定（Shader.cpp:1084-1089）：

  ┌──────────────┬──────────────────────────────┬─────────────────────────────────────────────┐
  │     类型     │           判断函数           │                   作用域                    │
  ├──────────────┼──────────────────────────────┼─────────────────────────────────────────────┤
  │ Global       │ IsGlobalTypePipeline()       │ Renderer 全局单例，如后处理、全屏 pass      │
  ├──────────────┼──────────────────────────────┼─────────────────────────────────────────────┤
  │ Material     │ IsMaterialTypePipeline()     │ 与材质参数绑定，由 FMaterialShaderType 派生 │
  ├──────────────┼──────────────────────────────┼─────────────────────────────────────────────┤
  │ MeshMaterial │ IsMeshMaterialTypePipeline() │ 同时依赖材质 + VertexFactory，最常见        │
  └──────────────┴──────────────────────────────┴─────────────────────────────────────────────┘

  ---
  2️⃣ 与普通 Material Shader 的关键区别

  A. 编译模式：专用 vs 共享

  这是 core difference，由 bShouldOptimizeUnusedOutputs 控制：

  ┌───────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────┐
  │                   │                              bShouldOptimizeUnusedOutputs = true                               │                         bShouldOptimizeUnusedOutputs = false                         │
  ├───────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
  │ 编译行为          │ 为 pipeline 生成独立专用 shader（去除多余输出）                                                │ 复用同类型的独立 shader，pipeline 只作为依赖挂上去                                   │
  ├───────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
  │ SubmitCompileJobs │ 调用 FMaterialShaderType::BeginCompileShaderPipeline() 为整个 pipeline 提交 一组新 compile job │ 从已提交的独立 shader job 中找到对应 job，把 pipeline 加到其 SharingPipelines 列表中 │
  └───────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────┘

  底层实现在 MaterialShader.cpp:2650-2725：

  if (Pipeline->ShouldOptimizeUnusedOutputs(ShaderPlatform)) {
      // 模式 A：为整个 pipeline 编译专用 shader（可裁减 unused interpolators）
      FMaterialShaderType::BeginCompileShaderPipeline(..., Pipeline, ...);
  } else {
      // 模式 B：复用已有的独立 shader
      FShaderCompileJob** Job = SharedShaderJobs.Find(ShaderTypePermutation);
      (*Job)->SharingPipelines.Add(Pipeline);
  }

  B. 运行时获取路径不同

  - 普通 Material Shader：通过 FMaterialShaderMap::GetShader(ShaderType, PermutationId) 在 shader map 中按类型查找
  - ShaderPipelineType：通过 FMaterial::TryGetShaders(InTypes) 传入 InTypes.PipelineType，从 shader map 中一次取出 整个 pipeline 的所有 stage（MaterialShared.cpp:3835-3900）

  关键代码：
  if (InTypes.PipelineType && RHISupportsShaderPipelines(...)) {
      FShaderPipeline* Pipeline = ShaderMapContent->GetShaderPipeline(InTypes.PipelineType);
      if (Pipeline) {
          OutShaders.Pipeline = Pipeline;  // 一次获取整个管线
          for (int32 Freq = 0; Freq < SF_NumGraphicsFrequencies; ++Freq) {
              OutShaders.Shaders[Freq] = Pipeline->GetShader((EShaderFrequency)Freq);
          }
      }
  }

  C. Permutation 限制

  Pipeline 中的每个 shader type 只能有 1 个 permutation（Shader.cpp 构造函数中有 assert）：

  checkf(ShaderType->GetPermutationCount() == 1,
      TEXT("Shader '%s' has multiple shader permutations. Shader pipelines only support a single permutation."))

  这是因为 pipeline 本身没有 permutation ID 的概念——它是一个固定的 stage 组合，不是多个变体。

  D. 平台门控

  Pipeline 功能只在支持 Graphics Pipeline State Object (PSO) 的 RHI 上生效：

  // DataDrivenShaderPlatformInfo.h:1082
  inline bool RHISupportsShaderPipelines(const FStaticShaderPlatform Platform) {
      return FDataDrivenShaderPlatformInfo::GetSupportsPipelineShaders(Platform);
  }

  实际运行时还有第二层开关 UseShaderPipelines()，可在平台配置中禁用即使硬件支持。

  ---
  3️⃣ 实际使用场景

  场景 A：Global Shader Pipeline（后处理/全屏 pass）

  // VelocityRendering.cpp:318
  IMPLEMENT_SHADERPIPELINE_TYPE_VSPS(StandardVelocityPipeline,
      TVelocityVS<EVelocityPassMode::Velocity_Standard>,
      TVelocityPS<EVelocityPassMode::Velocity_Standard>,
      true);  // 优化 unused outputs

  场景 B：Depth Only Pipeline（深度预 pass）

  // DepthRendering.cpp:160
  IMPLEMENT_SHADERPIPELINE_TYPE_VS(DepthNoPixelPipeline, TDepthOnlyVS<false>, true);
  IMPLEMENT_SHADERPIPELINE_TYPE_VSPS(DepthPipeline, TDepthOnlyVS<false>, FDepthOnlyPS, true);

  场景 C：Anisotropy Pass

  // AnisotropyRendering.cpp:91
  IMPLEMENT_SHADERPIPELINE_TYPE_VSPS(AnisotropyPipeline, FAnisotropyVS, FAnisotropyPS, true);

  编译流程中的角色

  在 FMaterialShaderMapLayoutCache::CreateLayout()（MaterialShader.cpp:3163-3296）中，pipeline 的处理流程：

  1. 从全局排序列表中获取 SortedMaterialPipelineTypes / SortedMeshMaterialPipelineTypes
  2. 逐一调用 ShouldCompilePipeline() 检查是否需要编译
  3. 通过的 pipeline 加入 Layout.ShaderPipelines 数组
  4. 在 SubmitCompileJobs 阶段决定是生成专用 shader 还是复用已有 shader

  布局哈希的影响

  Pipeline 参与布局哈希计算（MaterialShader.cpp:3207-3222），这意味着：
  - 新增/删除 pipeline type → shader map 缓存失效
  - pipeline 的 source hash 变化 → shader 重编译

  ---
  4️⃣ 总结：什么时候用 Pipeline，什么时候用普通 Material Shader？

  ┌───────────────────────────────────────────────┬──────────────────────────────────────────────────┐
  │                    你需要                     │                     使用方式                     │
  ├───────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ 一个多 stage 是固定组合、需要一起查出的       │ FShaderPipelineType + FMaterial::TryGetShaders() │
  ├───────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ 需要裁减 vs/ps 之间不用的 interpolator 输出   │ bShouldOptimizeUnusedOutputs = true              │
  ├───────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ 只需要单个 shader stage（如一个 PS 做后处理） │ 普通 IMPLEMENT_MATERIAL_SHADER_TYPE              │
  ├───────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ Stage 组合需要多个 permutation 变体           │ 普通 shader type（pipeline 不支持 permutation）  │
  └───────────────────────────────────────────────┴──────────────────────────────────────────────────┘

  核心区别一句话：ShaderPipelineType 将 VS+PS 等 stage 绑定为不可分割的单元一起编译和查找，允许 HLSL 编译器在跨 stage 层面优化（移除不用的输出插值器），而普通 Material Shader 各 stage 独立编译、独立查找。

✻ Churned for 45s

※ recap: You asked about Unreal's FShaderPipelineType — I've given a full analysis of its purpose, where it's used, and how it differs from regular material shaders. Let me know if you want to dive deeper into any specific part or have follow-up questions. (disable recaps in /config)

❯ /code-source-sql-search 详细解析ShaderCompiler.cpp中GlobalBeginCompileShader 函数的实现, MaterialShader或者globalshader怎么触发编译的

  Thought for 12s, called code-source-sql 9 times (ctrl+o to expand)

● Now let me look at the callers — how each shader type triggers compilation:

  Thought for 1s, called code-source-sql 3 times (ctrl+o to expand)

● Now let me see how SubmitCompileJobs orchestrates the entire flow:

  Thought for 1s, called code-source-sql 2 times (ctrl+o to expand)

● Now I have the complete picture. Here's the detailed analysis:

  ---
  ABSTRACTION FRAME (for "GlobalBeginCompileShader 实现解析")

  - Layer 1: [Core Function] — GlobalBeginCompileShader at ShaderCompiler.cpp:3163，所有 shader 编译的统一入口
  - Layer 2: [Input Assembly] — 构建 FShaderCompilerInput，设置所有平台/渲染相关的 #define 和 compiler flags
  - Layer 3: [Callers] — 三种 shader 类型各自通过 PrepareXxxShaderCompileJob 进入
  - Layer 4: [Orchestration] — VerifyGlobalShaders / FMaterialShaderMap::SubmitCompileJobs 决定何时触发编译
  - Layer 5: [Pipeline Handling] — Pipeline shader 的额外处理路径

  ---
  1️⃣ GlobalBeginCompileShader 的整体定位

  文件：Source/Runtime/Engine/Private/ShaderCompiler/ShaderCompiler.cpp:3163-4177
  声明：Source/Runtime/Engine/Public/ShaderCompiler.h:1315-1350

  这是 所有 Unreal Shader 编译的统一底层入口函数。它不负责"决定是否编译"，而是负责填充 FShaderCompilerInput 结构体，把所有全局状态摊平成 shader 编译所需的宏定义（#define）、编译器 flags、debug 信息、uniform buffer 引用等。

  它有两个重载版本——一个接受 const FString& 的 DebugDescription/DebugExtension，另一个接受 const TCHAR*。前者只是简单转调后者（ShaderCompiler.cpp:3112-3127）。

  参数签名

  void GlobalBeginCompileShader(
      const FString& DebugGroupName,        // 材质名 / "Global"
      const FVertexFactoryType* VFType,     // MeshMaterial 才有，Global/Material 为 nullptr
      const FShaderType* ShaderType,        // 当前要编译的 shader type
      const FShaderPipelineType* ShaderPipelineType, // 所属 pipeline（可能为 nullptr）
      int32 PermutationId,                  // permutation ID
      const TCHAR* SourceFilename,          // .usf 源文件路径
      const TCHAR* FunctionName,            // HLSL 入口函数名
      FShaderTarget Target,                 // (Frequency, Platform)
      FShaderCompilerInput& Input,          // 要填充的 output
      bool bAllowDevelopmentShaderCompile,  // 是否允许 development 编译
      const TCHAR* DebugDescription,
      const TCHAR* DebugExtension
  );

  ---
  2️⃣ 函数各阶段详细拆解

  阶段 A：基础信息填充 (L3163-L3220)

  Input.Target = Target;
  Input.ShaderFormat = ShaderFormatName;
  Input.VirtualSourceFilePath = SourceFilename;
  Input.EntryPointName = FunctionName;
  Input.DumpDebugInfoRootPath = ...;
  Input.DebugGroupName = DebugGroupName;
  Input.DebugDescription = DebugDescription;
  Input.ShaderName = ShaderType->GetName();
  Input.RootParametersStructure = ShaderType->GetRootParametersMetadata();
  Input.bBindlessEnabled = UE::ShaderCompiler::ShouldCompileWithBindlessEnabled(...);

  同时做文件路径校验：必须是 .usf 扩展名，不能包含 .ush。

  阶段 B：Debug Group Name 组装 (L3225-L3325)

  构建层级化的调试名称，格式为：

  资产材质名 / VF名(如果有) / ShaderType名 / PermutationId

  例如：MaterialName/LocalVertexFactory/TBasePassPS/0

  如果启用了 GDumpShaderDebugInfoShort，还会缩写常见名称：
  - BasePass → BP, Shadow → Shdw, DistanceField → DistFiel

  阶段 C：Shader Frequency #define (L3335-L3349)

  为每个 shader stage 设置对应的 #define：

  SET_SHADER_DEFINE(Input.Environment, PIXELSHADER,   Target.Frequency == SF_Pixel);
  SET_SHADER_DEFINE(Input.Environment, VERTEXSHADER,  Target.Frequency == SF_Vertex);
  SET_SHADER_DEFINE(Input.Environment, COMPUTESHADER, Target.Frequency == SF_Compute);
  // ... MESHSHADER, GEOMETRYSHADER, RAYxxxSHADER etc.

  阶段 D：平台/Renderer Feature #define 的海洋 (L3350-L4160)

  这是函数最核心也最庞大的部分。它设置了 数百个 shader 宏定义，覆盖：

  ┌───────────────┬────────────────────────────────────────────────────────────────────────┐
  │     类别      │                                  例子                                  │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ Shading Path  │ SHADING_PATH_DEFERRED, FORWARD_SHADING                                 │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ Mobile        │ SHADING_PATH_MOBILE, MOBILE_DEFERRED_SHADING, ALLOW_FRAMEBUFFER_FETCH  │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ VR/Stereo     │ INSTANCED_STEREO, MULTI_VIEW, MOBILE_MULTI_VIEW                        │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ Compiler      │ COMPILER_DXC, COMPILER_SUPPORTS_HLSL2021                               │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ GBuffer       │ GBUFFER_HAS_VELOCITY, SELECTIVE_BASEPASS_OUTPUTS                       │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ Substrate     │ SUBSTRATE_ENABLED, SUBSTRATE_GBUFFER_FORMAT, SUBSTRATE_SHADING_QUALITY │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ Platform caps │ PLATFORM_SUPPORTS_MESH_SHADERS_TIER0/1, PLATFORM_SUPPORTS_BINDLESS     │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ Optimization  │ CFLAG_Debug, CFLAG_ForceOptimization, CFLAG_RemoveDeadCode             │
  ├───────────────┼────────────────────────────────────────────────────────────────────────┤
  │ Misc          │ USE_DBUFFER, VELOCITY_ENCODE_DEPTH, PROJECT_SUPPORTS_LUMEN             │
  └───────────────┴────────────────────────────────────────────────────────────────────────┘

  关键设计模式：这个函数把所有 C++ 端的平台/功能判断提前转化为 HLSL 宏，使得 .usf 文件中的 #ifdef 可以被求值。这避免了在 shader 中做运行时判断。

  阶段 E：Uniform Buffer & Include 处理 (L3470-L3490)

  ShaderType->AddUniformBufferIncludesToEnvironment(Input.Environment, ShaderPlatform);
  if (VFType) {
      VFType->AddUniformBufferIncludesToEnvironment(Input.Environment, ShaderPlatform);
  }

  同时添加 GeneratedInstancedStereo.ush 到包含路径。

  阶段 F：Shader Format 后处理 (L4160-L4177)

  函数末尾，允许特定 shader format 插件进一步修改 Input：

  const IShaderFormat* Format = GetTargetPlatformManagerRef().FindShaderFormat(ShaderFormatName);
  Format->ModifyShaderCompilerInput(Input);

  FShaderCompileUtilities::ApplyDerivedDefines(Input.Environment, Input.SharedEnvironment, Platform);

  ▎ 重要观察：这个函数不调用 GShaderCompilingManager->SubmitJobs()。它只负责填充 FShaderCompilerInput。实际提交 job 是在调用方完成。

  ---
  3️⃣ 三种 Shader 类型的调用链

  Global Shader：PrepareGlobalShaderCompileJob

  文件：ShaderCompilerEditor.cpp:84-114

  调用方：VerifyGlobalShaders()（ShaderCompiler.cpp:4724-4925）

  调用时机：
  1. 引擎启动时 FGlobalShaderMap::Compile() 首次编译
  2. r.CompileShaders 控制台命令手动触发
  3. Shader source 变化导致 OutdatedShaderTypes 时热重编译

  void PrepareGlobalShaderCompileJob(...) {
      // DebugGroupName 固定为 "Global"
      static FString GlobalName(TEXT("Global"));
      NewJob->bIsGlobalShader = true;

      ::GlobalBeginCompileShader(
          GlobalName,       // DebugGroupName = "Global"
          nullptr,          // VFType = null
          ShaderType,
          ShaderPipeline,
          Key.PermutationId,
          ShaderType->GetShaderFilename(),
          ShaderType->GetFunctionName(),
          FShaderTarget(ShaderType->GetFrequency(), Platform),
          NewJob->Input     // 不传 bAllowDevelopmentShaderCompile, 默认 true
      );
  }

  关键差异：
  - VFType 为 nullptr → 函数内跳过了所有 VF 相关的 uniform buffer
  - DebugGroupName 固定 "Global" → 相当于 Global / ShaderTypeName / PermutationId
  - bAllowDevelopmentShaderCompile 使用默认值 true

  Material Shader：PrepareMaterialShaderCompileJob

  文件：MaterialShader.cpp:1846-1879

  调用方：FMaterialShaderType::BeginCompileShader() → FMaterialShaderMap::SubmitCompileJobs()

  调用时机：
  - 材质初次渲染
  - 材质参数变化导致 shader map 失效
  - Shader source 变化
  - r.CompileShadersForMaterial 手动重编译

  void PrepareMaterialShaderCompileJob(...) {
      NewJob->bBypassCache = Material->IsPreview() || !Material->IsPersistent();
      NewJob->Input.SharedEnvironment = MaterialEnvironment;

      Material->SetupExtraCompilationSettings(NewJob->Input.ExtraSettings);
      ShaderType->SetupCompileEnvironment(Platform, Material, Key.PermutationId, ...);

      ::GlobalBeginCompileShader(
          DebugGroupName,   // = 材质名
          nullptr,          // VFType = null（Material shader 不依赖 VF）
          ShaderType,
          ShaderPipeline,
          Key.PermutationId,
          ShaderType->GetShaderFilename(),
          ShaderType->GetFunctionName(),
          FShaderTarget(ShaderType->GetFrequency(), Platform),
          NewJob->Input,
          true,             // bAllowDevelopmentShaderCompile = true
          DebugDescription,
          DebugExtension
      );
  }

  关键差异：
  - VFType 为 nullptr（与 Global 相同）
  - SharedEnvironment 指向材质编译共享环境（包含材质自定义代码、全局 #define 等）
  - DebugGroupName 是材质的资产名称

  Mesh Material Shader：PrepareMeshMaterialShaderCompileJob

  文件：MeshMaterialShader.cpp:23-73

  调用方：FMeshMaterialShaderType::BeginCompileShader() → FMaterialShaderMap::SubmitCompileJobs()

  void PrepareMeshMaterialShaderCompileJob(...) {
      NewJob->bIsGlobalShader = false;

      VertexFactoryType->ModifyCompilationEnvironment(...);
      Material->SetupExtraCompilationSettings(NewJob->Input.ExtraSettings);
      ShaderType->SetupCompileEnvironment(Platform, MaterialParameters, VertexFactoryType, ...);

      bAllowDevelopmentShaderCompile = Material->GetAllowDevelopmentShaderCompile();

      ::GlobalBeginCompileShader(
          DebugGroupName,
          VertexFactoryType,    // ← 这里是关键差异：有 VFType！
          ShaderType,
          ShaderPipeline,
          Key.PermutationId,
          ShaderType->GetShaderFilename(),
          ShaderType->GetFunctionName(),
          FShaderTarget(ShaderType->GetFrequency(), Platform),
          NewJob->Input,
          bAllowDevelopmentShaderCompile,
          DebugDescription,
          DebugExtension
      );
  }

          nullptr,          // VFType = null（Material shader 不依赖 VF）
          ShaderType,
          ShaderPipeline,
          Key.PermutationId,
          ShaderType->GetShaderFilename(),
          ShaderType->GetFunctionName(),
          FShaderTarget(ShaderType->GetFrequency(), Platform),
          NewJob->Input,
          true,             // bAllowDevelopmentShaderCompile = true
          DebugDescription,
          DebugExtension
      );
  }

  关键差异：
  - VFType 为 nullptr（与 Global 相同）
  - SharedEnvironment 指向材质编译共享环境（包含材质自定义代码、全局 #define 等）
  - DebugGroupName 是材质的资产名称

  Mesh Material Shader：PrepareMeshMaterialShaderCompileJob

  文件：MeshMaterialShader.cpp:23-73

  调用方：FMeshMaterialShaderType::BeginCompileShader() → FMaterialShaderMap::SubmitCompileJobs()

  void PrepareMeshMaterialShaderCompileJob(...) {
      NewJob->bIsGlobalShader = false;

      VertexFactoryType->ModifyCompilationEnvironment(...);
      Material->SetupExtraCompilationSettings(NewJob->Input.ExtraSettings);
      ShaderType->SetupCompileEnvironment(Platform, MaterialParameters, VertexFactoryType, ...);

      bAllowDevelopmentShaderCompile = Material->GetAllowDevelopmentShaderCompile();

      ::GlobalBeginCompileShader(
          DebugGroupName,
          VertexFactoryType,    // ← 这里是关键差异：有 VFType！
          ShaderType,
          ShaderPipeline,
          Key.PermutationId,
          ShaderType->GetShaderFilename(),
          ShaderType->GetFunctionName(),
          FShaderTarget(ShaderType->GetFrequency(), Platform),
          NewJob->Input,
          bAllowDevelopmentShaderCompile,
          DebugDescription,
          DebugExtension
      );
  }

          bAllowDevelopmentShaderCompile,
          DebugDescription,
          DebugExtension
      );
  }

  关键差异：
  - VFType 不为 null → 函数内会添加 VF 的 uniform buffer、VF 名到 debug group name
  - bAllowDevelopmentShaderCompile 来自材质属性，可以被材质实例覆盖
  - TargetPlatform 从 MaterialEnvironment 传播

  ---
  4️⃣ Pipeline 编译的特殊处理

  当 ShaderPipeline != nullptr 时：

  1. GlobalBeginCompileShader 内部在 debug group name 后追加 pipeline 名：
  if (ShaderPipelineType) {
      Input.DebugGroupName = Input.DebugGroupName / ShaderPipelineType->GetName();
  }
  2. 在 SubmitCompileJobs 层面有两种策略（MaterialShader.cpp:2650-2725）：

  2. bShouldOptimizeUnusedOutputs = true：
    - 为 pipeline 创建独立的专用 compile job
    - HLSL 编译器可以跨 stage 剪裁未使用的 interpolator
    - 对应 FMaterialShaderType::BeginCompileShaderPipeline()

  bShouldOptimizeUnusedOutputs = false：
    - 从已有的独立 shader job 中查找，把 pipeline 作为共享引用挂上去
    - 对应 SharedShaderJobs.Find(ShaderTypePermutation) 后 push 到 SharingPipelines
  3. 此外有 FPipelinedShaderFilter 机制（MaterialShader.cpp:2534），过滤掉那些已经被 pipeline 覆盖的独立 shader，避免重复编译。

  ---
  5️⃣ 完整调用链总结

  [Global Shader]
    FGlobalShaderMap::Compile() / VerifyGlobalShaders()
      → FGlobalShaderTypeCompiler::BeginCompileShader()
        → PrepareGlobalShaderCompileJob()
          → GlobalBeginCompileShader()       ← 填充 Input
      → GShaderCompilingManager->SubmitJobs()  ← 提交

  [Material Shader]
    FMaterialShaderMap::SubmitCompileJobs()
      → FMaterialShaderType::BeginCompileShader()
        → PrepareMaterialShaderCompileJob()
          → GlobalBeginCompileShader()       ← 填充 Input
      → GShaderCompilingManager->SubmitJobs()  ← 提交

  [Mesh Material Shader]
    FMaterialShaderMap::SubmitCompileJobs()
      → FMeshMaterialShaderType::BeginCompileShader()
        → PrepareMeshMaterialShaderCompileJob()
          → GlobalBeginCompileShader()       ← 填充 Input（含 VFType）
      → GShaderCompilingManager->SubmitJobs()  ← 提交

  [Pipeline Shader]
    SubmitCompileJobs() 中 pipeline 分支
      → bShouldOptimizeUnusedOutputs ?
        Yes: BeginCompileShaderPipeline()
               → 为每个 stage 调用 PrepareXxxShaderCompileJob()
        No:  AppendSharingPipeline()  // 复用已有 shader job

  ---
  6️⃣ 关键设计模式总结

  1. GlobalBeginCompileShader 不是"开始编译"而只是"填充 Input" — 命名有些误导性。实际提交在 SubmitJobs()。
  2. 所有平台/功能开关在进入 shader 编译前拍平成 #define — 确保 .usf 可以专注做渲染逻辑而不是处理平台差异性。
  3. 三入口共享一个底层函数 — Global/Material/MeshMaterial 三者的差异只在于 VFType 是否非空、DebugGroupName 不同。
  4. Pipeline 编译在更上层处理 — GlobalBeginCompileShader 只处理 pipeline 名追加到 debug path 这一小件事；实际的双路径策略（专用 vs 共享）在 SubmitCompileJobs / VerifyGlobalShaders 中决策。





    Unreal Shader 编译完整链路图谱

  1. 整体架构概览

  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │                              UNREAL SHADER COMPILATION                          │
  │                                    ARCHITECTURE                                   │
  └─────────────────────────────────────────────────────────────────────────────────┘
                                             │
                      ┌──────────────────────┼──────────────────────┐
                      │                      │                      │
                      ▼                      ▼                      ▼
          ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
          │   Global Shader   │  │  Material Shader  │  │ Shader Pipeline   │
          │   Compilation     │  │    Compilation    │  │   Compilation     │
          └───────────────────┘  └───────────────────┘  └───────────────────┘
                      │                      │                      │
                      └──────────────────────┼──────────────────────┘
                                             │
                                             ▼
                          ┌─────────────────────────────────┐
                          │   GlobalBeginCompileShader()    │
                          │   (统一 Input 填充中心)         │
                          │   ShaderCompiler.cpp:3163      │
                          └─────────────────────────────────┘
                                             │
                                             ▼
                          ┌─────────────────────────────────┐
                          │  FShaderCompilingManager::      │
                          │  SubmitJobs()                   │
                          └─────────────────────────────────┘
                                             │
                                             ▼
                          ┌─────────────────────────────────┐
                          │      异步编译进程               │
                          │   (DXC / FXC / Metal / etc.)   │
                          └─────────────────────────────────┘

  ---
  2. 详细调用链路分解

  2.1 Global Shader 编译链路

  触发时机:
  ├── 引擎启动: FGlobalShaderMap::Compile()
  ├── 控制台命令: r.CompileShaders
  ├── Shader source 变化: OutdatedShaderTypes
  └── 平台切换: FGlobalShaderType::ShouldCompilePermutation()

  调用链:
  VerifyGlobalShaders()
      │  [ShaderCompiler.cpp:4724-4925]
      ├─ 遍历 FShaderType::GetTypeList()
      ├─ 检查 ShouldCompilePermutation()
      │
      ▼
  FGlobalShaderTypeCompiler::BeginCompileShader()
      │
      ▼
  PrepareGlobalShaderCompileJob()
      │  [ShaderCompilerEditor.cpp:84-114]
      │
      ├─ SetupCompileEnvironment()     ─── ShaderType 特定环境
      ├─ NewJob->bIsGlobalShader = true
      ├─ DebugGroupName = "Global"
      │
      ▼
  GlobalBeginCompileShader()
      │  [ShaderCompiler.cpp:3163-4177]
      │
      ├─ 填充 FShaderCompilerInput
      │
      ▼
  GShaderCompilingManager->SubmitJobs()

  关键参数值 (Global Shader):
  GlobalBeginCompileShader(
      DebugGroupName = "Global",           // 固定值
      VFType = nullptr,                     // 无 VertexFactory
      ShaderType = <GlobalShaderType>,      // 如 FBasePassPS
      ShaderPipeline = nullptr 或 <Pipeline>,
      PermutationId = <ID>,
      bAllowDevelopmentShaderCompile = true, // 默认
      ...
  );

  ---
  2.2 Material Shader 编译链路

  触发时机:
  ├── 材质首次渲染
  ├── 材质参数变化
  ├── Shader source 变化
  ├── VertexFactory 切换
  └── 控制台命令: r.CompileShadersForMaterial

  调用链:
  FMaterial::GetShaderMap()
      │
      ▼
  FMaterialShaderMap::SubmitCompileJobs()
      │  [MaterialShader.cpp:2478-2725]
      │
      ├─ AcquireMaterialShaderMapLayout()  ─── 获取需要编译的 shader/pipeline 列表
      ├─ 遍历 Layout.Shaders
      │   │
      │   ▼
      │   FMaterialShaderType::BeginCompileShader()
      │       │
      │       ▼
      │   PrepareMaterialShaderCompileJob()
      │       │  [MaterialShader.cpp:1846-1879]
      │       │
      │       ├─ Material->SetupExtraCompilationSettings()
      │       ├─ ShaderType->SetupCompileEnvironment()
      │       ├─ NewJob->bBypassCache = Material->IsPreview()
      │       │
      │       ▼
      │   GlobalBeginCompileShader()
      │
      └─ GShaderCompilingManager->SubmitJobs()

  关键参数值 (Material Shader):
  GlobalBeginCompileShader(
      DebugGroupName = <MaterialAssetName>,     // 材质资产名
      VFType = nullptr,                          // Material shader 不依赖 VF
      ShaderType = <MaterialShaderType>,         // 如 TDeferredLightPS
      ShaderPipeline = nullptr 或 <Pipeline>,
      PermutationId = kUniqueShaderPermutationId,
      bAllowDevelopmentShaderCompile = true,
      SharedEnvironment = MaterialEnvironment,   // 包含材质自定义代码
      ...
  );

  ---
  2.3 MeshMaterial Shader 编译链路

  触发时机: 与 Material Shader 相同，但涉及 VertexFactory

  调用链:
  FMaterialShaderMap::SubmitCompileJobs()
      │
      ├─ 遍历 Layout.MeshShaderMaps
      │   │
      │   ▼
      │   FMeshMaterialShaderType::BeginCompileShader()
      │       │
      │       ▼
      │   PrepareMeshMaterialShaderCompileJob()
      │       │  [MeshMaterialShader.cpp:23-73]
      │       │
      │       ├─ VertexFactoryType->ModifyCompilationEnvironment()
      │       ├─ ShaderType->SetupCompileEnvironment()
      │       ├─ Material->SetupExtraCompilationSettings()
      │       ├─ bAllowDevelopmentShaderCompile = Material->GetAllowDevelopmentShaderCompile()
      │       │
      │       ▼
      │   GlobalBeginCompileShader()
      │
      └─ GShaderCompilingManager->SubmitJobs()

  关键参数值 (MeshMaterial Shader):
  GlobalBeginCompileShader(
      DebugGroupName = <MaterialAssetName> / <VFName>,
      VFType = <VertexFactoryType>,              // ← 关键差异
      ShaderType = <MeshMaterialShaderType>,     // 如 TBasePassPS<FUniformLightMapPolicy>
      ShaderPipeline = nullptr 或 <Pipeline>,
      PermutationId = kUniqueShaderPermutationId,
      bAllowDevelopmentShaderCompile = <Material Property>,
      ...
  );

  ---
  2.4 Shader Pipeline 编译链路

  两种策略 (由 bShouldOptimizeUnusedOutputs 决定):

  策略 A: bShouldOptimizeUnusedOutputs = true (专用 shader)
  ┌─────────────────────────────────────────────────────────────────┐
  │ SubmitCompileJobs()                                             │
  │   ├─ 检查 Pipeline->ShouldOptimizeUnusedOutputs()               │
  │   ├─ 调用 BeginCompileShaderPipeline()                          │
  │   │   │                                                         │
  │   │   └─ 为每个 stage 调用 PrepareXxxShaderCompileJob()        │
  │   │       └─ GlobalBeginCompileShader(ShaderPipeline = <Pipeline>)│
  │   │       └─ HLSL 可跨 stage 优化 interpolator                  │
  │   └─ 每个独立的 pipeline stage 对应一个 FShaderCompileJob      │
  └─────────────────────────────────────────────────────────────────┘

  策略 B: bShouldOptimizeUnusedOutputs = false (共享 shader)
  ┌─────────────────────────────────────────────────────────────────┐
  │ SubmitCompileJobs()                                             │
  │   ├─ 先编译独立 shader                                          │
  │   │   └─ SharedShaderJobs.Add(ShaderTypePermutation, Job)       │
  │   │                                                             │
  │   ├─ 遍历 Layout.ShaderPipelines                                │
  │   │   ├─ 查找 SharedShaderJobs 中对应的 Job                     │
  │   │   ├─ Job->SharingPipelines.Add(Pipeline)                     │
  │   │   └─ 多个 Pipeline 复用同一个 Shader 对象                   │
  │   │                                                             │
  │   └─ 最后一个 Stage 的 FShader 对象被多个 Pipeline 共享          │
  └─────────────────────────────────────────────────────────────────┘

  ---
  3. GlobalBeginCompileShader 数据填充图谱

  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │                        GlobalBeginCompileShader() 数据填充中心                        │
  │                      ShaderCompiler.cpp:3163-4177                                      │
  └─────────────────────────────────────────────────────────────────────────────────────┘
                                             │
          ┌──────────────────────────────────┼──────────────────────────────────┐
          │                                  │                                  │
          ▼                                  ▼                                  ▼
  ┌───────────────────────┐    ┌───────────────────────┐    ┌───────────────────────┐
  │  基础信息填充        │    │  平台特性宏定义      │    │  编译器 Flags         │
  │  (L3175-L3220)       │    │  (L3335-L4140)        │    │  (L3540-L3630)        │
  ├───────────────────────┤    ├───────────────────────┤    ├───────────────────────┤
  │ Input.Target         │    │ PIXELSHADER           │    │ CFLAG_Debug           │
  │ Input.ShaderFormat   │    │ VERTEXSHADER          │    │ CFLAG_ForceOptimization│
  │ Input.SourceFilename │    │ COMPUTESHADER         │    │ CFLAG_HLSL2021        │
  │ Input.EntryPointName │    │ MESHSHADER            │    │ CFLAG_ForceDXC        │
  │ Input.DebugGroupName  │    │ GEOMETRYSHADER        │    │ CFLAG_WarningsAsErrors│
  │ Input.ShaderName     │    │ RAYxxxSHADER          │    │ CFLAG_RemoveDeadCode   │
  │ Input.RootParameters │    │ COMPILER_DXC          │    │ CFLAG_DisableSourceStr│
  │ Input.bBindlessEnabled│   │ COMPILER_SUPPORTS_HLSL│    │ CFLAG_SkipValidation   │
  └───────────────────────┘    │ 2021                  │    │ CFLAG_GenerateSymbols  │
                                │ PLATFORM_MAX_SAMPLERS │    │ CFLAG_Archive(Metal)  │
                                │ PLATFORM_SUPPORTS_xxx │    └───────────────────────┘
                                │ FORWARD_SHADING       │
                                │ INSTANCED_STEREO      │
                                │ SUBSTRATE_ENABLED     │
                                │ PROJECT_SUPPORTS_LUMEN│
                                │ VELOCITY_ENCODE_DEPTH │
                                └───────────────────────┘
                                             │
          ┌──────────────────────────────────┼──────────────────────────────────┐
          │                                  │                                  │
          ▼                                  ▼                                  ▼
  ┌───────────────────────┐    ┌───────────────────────┐    ┌───────────────────────┐
  │  Uniform Buffer      │    │  Platform-Specific    │    │  色彩空间/Other      │
  │  Include 处理        │    │  配置                │    │  配置                │
  │  (L3470-L3490)       │    │  (L3350-L3690)        │    │  (L3700-L4160)       │
  ├───────────────────────┤    ├───────────────────────┤    ├───────────────────────┤
  │ ShaderType->AddUB()  │    │ Metal 平台配置:       │    │ WORKING_COLOR_SPACE   │
  │ VFType->AddUB()      │    │ - Metal shader 版本   │    │ UE_LEGACY_LUMINANCE   │
  │ InstancedStereo.ush  │    │ - Archive 模式        │    │ UE_LWC_RENDER_TILE_x  │
  │                      │    │ - FastIntrinsics      │    │ NANITE_ASSEMBLY_DATA  │
  └───────────────────────┘    │ Android:              │    │ PROJECT_OIT          │
                                │ - 禁用 dev shaders   │    │ PROJECT_SUPPORT_SKY_  │
                                │ Mobile:               │    │ ATMOSPHERE           │
                                │ - Forward/Deferred    │    │ SUPPORT_LOCALFOGVOL   │
                                │ - FramebufferFetch    │    │ └───────────────────────┘
                                │ - UBO emulation      │
                                └───────────────────────┘

  ---
  4. 完整数据流图谱

  输入参数                      GlobalBeginCompileShader 内部处理                    输出: FShaderCompilerInput
  ─────────────────────────────────────────────────────────────────────────────────────────────────────
  DebugGroupName         ───────▶  Input.DebugGroupName = DebugGroupName / VFName /           │
  VFType (MeshMaterial)   │       │   PipelineName / ShaderTypeName / PermutationId        │
          │              │       │                                                          │
          │              ▼       │   Input.Target = Target                                 │
          ▼       Input.SourceFilename = SourceFilename                                   │
  ShaderType            │       │   Input.EntryPointName = FunctionName                    │
          │              │       │   Input.ShaderName = ShaderType->GetName()               │
          │              ▼       │   Input.RootParametersStructure =                        │
          ▼       Input.ShaderPlatformName = FDataDriven...GetName()                      │
  ShaderPipeline        │       │   Input.ShaderFormat = ShaderFormatName                  │
          │              │       │   Input.VirtualSourceFilePath = SourceFilename           │
          │              ▼       │   Input.bBindlessEnabled = ShouldCompileWithBindless()   │
          ▼       SET_SHADER_DEFINE(PIXELSHADER/VERTEXSHADER/...) ← Frequency macro        │
  PermutationId         │       │   SET_SHADER_DEFINE(FORWARD_SHADING)                     │
          │              │       │   SET_SHADER_DEFINE(SHADING_PATH_DEFERRED/MOBILE)        │
          │              ▼       │   SET_SHADER_DEFINE(INSTANCED_STEREO/MULTI_VIEW)          │
          ▼       SET_SHADER_DEFINE(PLATFORM_MAX_SAMPLERS) ← 平台能力                      │
  SourceFilename        │       │   SET_SHADER_DEFINE(PLATFORM_SUPPORTS_xxx)                │
          │              │       │   SET_SHADER_DEFINE(SUBSTRATE_ENABLED/xxx)                │
          │              ▼       │   SET_SHADER_DEFINE(PROJECT_SUPPORTS_LUMEN)              │
          ▼       SET_SHADER_DEFINE(VELOCITY_ENCODE_DEPTH)                                 │
  FunctionName          │       │   SET_SHADER_DEFINE(USE_DBUFFER/GBUFFER_xxx)               │
          │              │       │   SET_SHADER_DEFINE(NANITE_xxx)                          │
          │              ▼       │                                                          │
          ▼       if (bIsDxcEnabled) Add(CFLAG_ForceDXC)                                  │
  bAllowDevCompile      │       │   if (Metal) Add(CFLAG_Archive)                         │
          │              │       │   if (ShouldOptimize) Add(CFLAG_Debug)                   │
          │              ▼       │   if (bUsingMobile) Add(CFLAG_UseEmulatedUB)              │
          ▼       ShaderType->AddUniformBufferIncludesToEnvironment()                     │
  Input (Environment)   │       │   if (VFType) VFType->AddUniformBufferIncludes()          │
          │              │       │   Add GeneratedInstancedStereo.ush                       │
          │              ▼       │                                                          │
          ▼       Format->ModifyShaderCompilerInput(Input)                                  │
                        │       │   ApplyDerivedDefines(Environment, SharedEnv)             │
                        │       │                                                          │
                        ▼       ▼                                                          │
                        最终 FShaderCompilerInput 包含:                                     │
                        ├── Target (Frequency, Platform)                                    │
                        ├── Environment (所有 #define + compiler flags)                   │
                        ├── SharedEnvironment (材质共享环境)                                │
                        ├── VirtualSourceFilePath / EntryPointName                           │
                        ├── DebugGroupName / DebugDescription                               │
                        ├── RootParametersStructure                                        │
                        ├── bBindlessEnabled                                               │
                        └── Platform/Feature flags                                          │
                                                                                            │
                                                                                            ▼
                                                                                      GShaderCompilingManager->
                                                                                      SubmitJobs(CompileJobs)

  ---
  5. 三种 Shader 类型的关键差异对比表

  ┌─────────────────────────┬──────────────────────┬────────────────────────────┬────────────────────────────────┐
  │          维度           │    Global Shader     │      Material Shader       │      MeshMaterial Shader       │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ VFType                  │ nullptr              │ nullptr                    │ 非空                           │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ DebugGroupName          │ "Global"             │ 材质资产名                 │ 材质名 + VF名                  │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ PermutationId           │ 0-N (多 permutation) │ kUniqueShaderPermutationId │ kUniqueShaderPermutationId     │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ SharedEnvironment       │ 无                   │ MaterialEnvironment        │ MaterialEnvironment            │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ SetupCompileEnvironment │ GlobalShaderType::   │ MaterialShaderType::       │ MeshMaterialShaderType::       │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ Uniform Buffer          │ 仅 ShaderType        │ 仅 ShaderType              │ ShaderType + VFType            │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ bIsGlobalShader         │ true                 │ false                      │ false                          │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ bBypassCache            │ false                │ Material->IsPreview()      │ Material->IsPreview()          │
  ├─────────────────────────┼──────────────────────┼────────────────────────────┼────────────────────────────────┤
  │ bAllowDevCompile        │ true (默认)          │ true                       │ Material->GetAllowDevCompile() │
  └─────────────────────────┴──────────────────────┴────────────────────────────┴────────────────────────────────┘

  ---
  6. Pipeline 编译的数据流分支

  Pipeline 判断逻辑:
  ┌─────────────────────────────────────────────────────────────────┐
  │  SubmitCompileJobs()                                             │
  │   │                                                              │
  │   ├─ for (Pipeline : Layout.ShaderPipelines)                     │
  │   │   │                                                          │
  │   │   ├─ if (Pipeline->ShouldOptimizeUnusedOutputs(Platform))   │
  │   │   │   │  = true  ──────────────────────┐                   │
  │   │   │   │                               │                   │
  │   │   │   ▼                               ▼                   │
  │   │   │  【路径 A: 专用 Pipeline Shader】   │                   │
  │   │   │  ┌──────────────────────────┐      │                   │
  │   │   │  │ BeginCompileShaderPipeline()│      │                   │
  │   │   │  │  ├─ 为每个 Stage 创建 Job  │      │                   │
  │   │   │  │  │  └─ GlobalBeginCompileShader(│      │                   │
  │   │   │  │  │      ShaderPipeline=Pipeline│      │                   │
  │   │   │  │  │  )                         │      │                   │
  │   │   │  │  ├─ Job.bCompilingForShaderPipeline│                │
  │   │   │  │  └─ 输出可被 HLSL 跨 stage 优化的 shader              │
  │   │   │  └──────────────────────────┘      │                   │
  │   │   │                               │                   │
  │   │   └─ else (bShouldOptimize= false)  │                   │
  │   │       │  = false ───────────────────┘                   │
  │   │       │                                                   │
  │   │       ▼                                                   │
  │   │      【路径 B: 共享 Shader】                               │
  │   │      ┌──────────────────────────┐                         │
  │   │      │ SharedShaderJobs 中的 Job│                         │
  │   │      │  └─ Job->SharingPipelines│                         │
  │   │      │      .Add(Pipeline)      │                         │
  │   │      └──────────────────────────┘                         │
  │   │                                                           │
  │   └─ 结果:                                                    │
  │       - 路径 A: 每个 Pipeline Stage 有独立 FShader 对象        │
  │       - 路径 B: 多个 Pipeline 共享同一个 FShader 对象          │
  │       - 在 TryGetShaders() 中通过 Pipeline 字段区分           │
  └─────────────────────────────────────────────────────────────────┘

  ---
  这就是完整的 Unreal Shader 编译链路图谱。从触发点到 GlobalBeginCompileShader 的数据填充，再到最终提交编译的全过程都已经覆盖。
















    Unreal Shader CompileJobs 完整分析

  基于读取的代码，我为你整理了 Shader CompileJobs 的完整架构：

  ---
  1. 编译作业类层次结构

  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │                        FShaderCommonCompileJob (基类)                                  │
  │                        ShaderCompilerJobTypes.h:177-300                               │
  │  ─────────────────────────────────────────────────────────────────────────────────│
  │  通用字段:                                                                        │
  │  ├── NextLink/PrevLink              │ 链表节点（用于管理）                          │
  │  ├── PendingShaderMap             │ 所属的 ShaderMap                              │
  │  ├── NumRefs/Hash/Id              │ 引用计数、Hash、ID                            │
  │  ├── Type                          │ Single 或 Pipeline                            │
  │  ├── Priority/PendingPriority     │ 优先级                                        │
  │  ├── CurrentWorker                 │ 当前 Worker 类型                              │
  │  ├── bFinalized/bSucceeded         │ 完成状态                                      │
  │  ├── bErrorsAreLikelyToBeCode      │ 错误是否是代码问题                            │
  │  ├── bReleased                     │ 是否已释放                                    │
  │  ├── bInputHashSet                 │ InputHash 是否已设置                          │
  │  ├── bIsDefaultMaterial            │ 是否为默认材质                                │
  │  ├── bIsGlobalShader               │ 是否为 Global Shader                          │
  │  ├── bBypassCache                  │ 是否绕过缓存                                  │
  │  ├── InputHash                     │ 输入 Hash（用于缓存查找）                     │
  │  ├── TimeAddedToPendingQueue       │ 时间戳：加入队列                              │
  │  ├── TimeAssignedToExecution       │ 时间戳：分配执行                              │
  │  ├── TimeExecutionCompleted        │ 时间戳：执行完成                              │
  │  ├── JobCacheRef                   │ JobCache 引用                                │
  │  ├── JobStatusPtr                  │ 状态指针                                      │
  │  └── RequestOwner                  │ DDC/Distributed Build 请求所有者               │
  │                                                                                      │
  │  虚方法:                                                                            │
  │  ├── GetInputHash()               │ 获取输入 Hash                                  │
  │  ├── SerializeOutput()             │ 序列化输出（用于缓存）                        │
  │  ├── AppendDebugName()            │ 生成调试名称                                  │
  │  ├── AppendDiagnostics()          │ 生成诊断信息                                  │
  │  ├── OnComplete()                 │ 编译完成回调（已弃用）                        │
  │  └── OnComplete(Ctx)              │ 编译完成回调（新版本）                       │
  └─────────────────────────────────────────────────────────────────────────────────────┘
                                      │
              ┌───────────────────────┴───────────────────────┐
              │                                             │
              ▼                                             ▼
  ┌─────────────────────────────────────────┐  ┌─────────────────────────────────────────┐
  │    FShaderCompileJob (Single)            │  │  FShaderPipelineCompileJob (Pipeline)    │
  │    ShaderCompilerJobTypes.h:333-372     │  │  ShaderCompilerJobTypes.h:399-435       │
  ├─────────────────────────────────────────┤  ├─────────────────────────────────────────┤
  │  Key: FShaderCompileJobKey               │  │  Key: FShaderPipelineCompileJobKey      │
  │  │   ├─ ShaderType                       │  │  │   ├─ ShaderPipeline                  │
  │  │   ├─ VFType                           │  │  │   ├─ VFType                         │
  │  │   └─ PermutationId                   │  │  │   └─ PermutationId                  │
  │  │                                      │  │  │                                     │
  │  Input: FShaderCompilerInput             │  │  StageJobs: TArray<FShaderCompileJob*>│
  │  PreprocessOutput: FShaderPreprocessOutput│  │  │  每个阶段对应一个 Single Job         │
  │  SecondaryPreprocessOutput               │  │  │                                     │
  │  Output: FShaderCompilerOutput           │  │  方法:                                │
  │  SecondaryOutput                         │  │  ├─ GetInputHash()                   │
  │  ShaderParameters                        │  │  ├─ SerializeOutput()               │
  │  SharingPipelines                        │  │  ├─ AppendDebugName()                │
  │  │   └─ Map<VF*, Array<Pipeline*>>       │  │  ├─ AppendDiagnostics()            │
  │  │       (共享此 shader 的 pipelines)    │  │  └─ OnComplete(Ctx)                 │
  │                                        │  │                                     │
  │  方法:                                  │  └─────────────────────────────────────────┘
  │  ├─ GetSingleShaderJob() [this]         │
  │  ├─ GetShaderPipelineJob() [null]       │
  │  ├─ SerializeWorkerInput()              │
  │  ├─ SerializeWorkerOutput()             │
  │  ├─ SerializeArtifact()                 │
  │  └─ GetFinalSourceView()               │
  └─────────────────────────────────────────┘

  ---
  2. 编译作业的键（Job Keys）

  FShaderCompileJobKey (Single Shader)

  struct FShaderCompileJobKey
  {
      const FShaderType* ShaderType;      // 要编译的 shader 类型
      const FVertexFactoryType* VFType;   // VertexFactory 类型（Material shader 为空）
      int32 PermutationId;                // Permutation ID

      // Hash 计算
      uint32 MakeHash(uint32 Id) const {
          return HashCombine(HashCombine(HashCombine(GetTypeHash(Id),
                                                GetTypeHash(VFType)),
                                                GetTypeHash(ShaderType)),
                                        GetTypeHash(PermutationId));
      }
  };

  FShaderPipelineCompileJobKey (Pipeline Shader)

  struct FShaderPipelineCompileJobKey
  {
      const FShaderPipelineType* ShaderPipeline;  // Pipeline 类型
      const FVertexFactoryType* VFType;           // VertexFactory 类型
      int32 PermutationId;                        // Permutation ID

      // Hash 计算（类似，但基于 ShaderPipeline）
  };

  ---
  3. 编译输入：FShaderCompilerInput

  ShaderCompilerCore.h:209-352

  struct FShaderCompilerInput {
      // === 目标信息 ===
      FShaderTarget Target;           // (Frequency, Platform)
      FName ShaderFormat;            // 如 D3D, Metal, Vulkan
      FName CompressionFormat;       // 如 Oodle, Zlib
      FName ShaderPlatformName;      // 平台名称
      FName PreferredShaderCodeFormat; // DXIL vs DXBC

      // === 源代码信息 ===
      FString VirtualSourceFilePath; // .usf 文件路径
      FString EntryPointName;        // HLSL 入口函数名
      FString ShaderName;            // Shader 名称

      // === 平台能力 ===
      uint32 SupportedHardwareMask;  // 硬件掩码

      // === 调试信息 ===
      EShaderDebugInfoFlags DebugInfoFlags;
      TArray<FString> RequiredSymbols;
      TArray<FString> UsedOutputs;        // Pipeline 使用的输出
      FString DumpDebugInfoRootPath;      // 调试输出根目录
      FString DumpDebugInfoPath;          // 调试输出路径
      FString DebugGroupName;             // 调试组名（材质名/Global）
      FString DebugExtension;             // 调试扩展名
      FString DebugDescription;           // 配置描述

      // === 缓存相关 ===
      FShaderCompilerInputHash Hash;     // 输入 Hash（缓存键）

      // === 编译环境 ===
      FShaderCompilerEnvironment Environment;            // 局部环境
      TRefCountPtr<FSharedShaderCompilerEnvironment> SharedEnvironment; // 共享环境

      // === Uniform Buffer ===
      const FShaderParametersMetadata* RootParametersStructure;

      // === 额外设置 ===
      FExtraShaderCompilerSettings ExtraSettings;

      // === 压缩 ===
      FOodleDataCompression::ECompressor OodleCompressor;
      FOodleDataCompression::ECompressionLevel OodleLevel;

      // === 标志位 ===
      bool bCompilingForShaderPipeline;  // 是否为 pipeline 编译
      bool bIncludeUsedOutputs;          // 是否包含已使用的输出
      bool bBindlessEnabled;             // 是否启用 bindless

      // === 工具方法 ===
      bool DumpDebugInfoEnabled() const;
      bool NeedsOriginalShaderSource() const;
      FString GenerateShaderName() const;
      FString GenerateDebugInfo() const;
      void GatherSharedInputs(...);
      void SerializeSharedInputs(...);
  };

  ---
  4. 编译输出：FShaderCompilerOutput

  ShaderCompilerCore.h:491-640

  struct FShaderCompilerOutput {
      // === 编译结果 ===
      FShaderParameterMap ParameterMap;     // Parameter 映射
      TArray<FShaderCompilerError> Errors;  // 错误列表
      FShaderTarget Target;                 // 目标平台
      FShaderCode ShaderCode;               // 编译后的代码（字节码）
      FSHAHash OutputHash;                 // 输出 Hash
      FShaderCompilerInputHash ValidateInputHash; // 验证输入 Hash

      // === 统计信息 ===
      uint32 NumInstructions;              // 指令数
      uint32 NumTextureSamplers;           // 纹理采样器数
      double CompileTime;                  // 编译耗时
      double PreprocessTime;               // 预处理耗时
      bool bSucceeded;                     // 是否成功
      bool bSupportsQueryingUsedAttributes;
      bool bSerializingForCache;

      // === 验证数据 ===
      TArray<FShaderCodeValidationStride> ParametersStrideToValidate;
      TArray<FShaderCodeValidationType> ParametersSRVTypeToValidate;
      TArray<FShaderCodeValidationType> ParametersUAVTypeToValidate;
      TArray<FShaderCodeValidationUBSize> ParametersUBSizeToValidate;

      // === 诊断数据 ===
      TArray<FShaderDiagnosticData> ShaderDiagnosticDatas;

      // === 修改后的源代码（可选） ===
      FString ModifiedShaderSource;
      FString ModifiedEntryPointName;

      // === 统计信息 ===
      TArray<FGenericShaderStat> ShaderStatistics;

      // === 方法 ===
      void GenerateOutputHash();            // 生成输出 Hash
      void CompressOutput(...);             // 压缩输出
      void SerializeShaderCodeValidation();
      void SerializeShaderDiagnosticData();
      void AddStatistic<...>(...);

      // === 序列化 ===
      friend FArchive& operator<<(FArchive& Ar, FShaderCompilerOutput& Output);
  };

  ---
  5. 编译作业状态机

  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │                       EShaderCompileJobStatus (作业状态)                               │
  │                       ShaderCompilerJobTypes.h:91-131                                 │
  └─────────────────────────────────────────────────────────────────────────────────────┘

  状态转换:
  [Unset] ──▶ [Ready] ──▶ [PendingDDC] ──▶ [Queued] ──▶ [PendingLocalExecution]
                │              │                │               │
                │              │                │               │
                │              ▼                ▼               ▼
                │        [CompleteFoundInDDC] [CompleteFoundInCache] [CompleteLocalExecution]
                │              │                │               │
                │              └────────────────┴───────────────┘
                │
                └─▶ [Skipped] / [Cancelled] / [PendingDistributedExecution]
                                              │
                                              └─▶ [CompleteDistributedExecution]

  WasCompilationSkipped() 判断:
  ├─ GetIsDuplicate() == true
  ├─ Status == Skipped
  ├─ Status == CompleteFoundInCache
  └─ Status == CompleteFoundInDDC

  ---
  6. 编译作业的生命周期

  创建阶段:
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │  BeginCompileShader() / BeginCompileShaderPipeline()                                  │
  │  │                                                                                 │
  │  ├─ 创建 FShaderCompileJob (Single) 或 FShaderPipelineCompileJob (Pipeline)         │
  │  │                                                                                 │
  │  ├─ 设置 Key (ShaderType/VFType/PermutationId 或 Pipeline/VFType/PermutationId)     │
  │  │                                                                                 │
  │  ├─ 设置 bIsGlobalShader / bIsDefaultMaterial / bBypassCache                        │
  │  │                                                                                 │
  │  ├─ GlobalBeginCompileShader() 填充 Input                                          │
  │  │   ├─ 基础信息 (Target, SourceFilename, EntryPointName)                          │
  │  │   ├─ 平台宏定义 (PIXELSHADER, FORWARD_SHADING, SUBSTRATE_ENABLED...)           │
  │  │   ├─ 编译器 Flags (CFLAG_Debug, CFLAG_HLSL2021, CFLAG_ForceDXC...)             │
  │  │   └─ Uniform Buffer Includes                                                    │
  │  │                                                                                 │
  │  └─ 调用 UpdateInputHash() 生成 InputHash                                          │
  └─────────────────────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
  提交阶段:
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │  GShaderCompilingManager::SubmitJobs()                                               │
  │  │                                                                                 │
  │  ├─ 检查 JobCache 是否已有相同 InputHash 的 Job                                    │
  │  │                                                                                 │
  │  ├─ 如果存在且不是 pipeline → 设置 IsDuplicate=true, 复用 JobCacheRef             │
  │  │                                                                                 │
  │  ├─ 否则:                                                                          │
  │  │   ├─ 设置状态为 PendingDDC 或 Queued                                          │
  │  │   ├─ 添加到 PendingShaderMap                                                  │
  │  │   └─ 发送给 Worker (本地或分布式)                                              │
  │  │                                                                                 │
  │  └─ 对于 Pipeline:                                                                │
  │      ├─ 如果 bShouldOptimizeUnusedOutputs=true → 创建 Pipeline Job + 多个 Stage   │
  │      └─ 否 → 复用已有 Single Job, 设置 SharingPipelines                           │
  └─────────────────────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
  执行阶段:
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │  ShaderCompileWorker (SCW) 进程                                                    │
  │  │                                                                                 │
  │  ├─ 反序列化 Input                                                                │
  │  │                                                                                 │
  │  ├─ 调用 ShaderFormat::CompileShader()                                            │
  │  │   ├─ 预处理 (PreprocessShader)                                                  │
  │  │   ├─ 调用编译器 (FXC/DXC/Metal/glslang)                                       │
  │  │   ├─ 后处理 (生成参数映射、优化等)                                             │
  │  │   └─ 填充 Output                                                               │
  │  │                                                                                 │
  │  └─ 序列化 Output 返回                                                            │
  └─────────────────────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
  完成阶段:
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │  ProcessCompilationResults() / ProcessSingleJob()                                  │
  │  │                                                                                 │
  │  ├─ 检查 bSucceeded                                                               │
  │  │                                                                                 │
  │  ├─ 调用 FShaderType::FinishCompileShader() 创建 FShader 对象                   │
  │  │                                                                                 │
  │  ├─ 将 FShader 添加到 ShaderMap                                                  │
  │  │                                                                                 │
  │  ├─ 调用 Job->OnComplete(Ctx)                                                     │
  │  │                                                                                 │
  │  ├─ 更新 JobCache                                                               │
  │  │                                                                                 │
  │  └─ 释放 Job                                                                     │
  └─────────────────────────────────────────────────────────────────────────────────────┘

  ---
  7. Pipeline Job 的特殊处理

  Pipeline Job 结构:
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │  FShaderPipelineCompileJob                                                           │
  │  ├─ Key: FShaderPipelineCompileJobKey                                               │
  │  │   ├─ ShaderPipeline (如 StandardVelocityPipeline)                                │
  │  │   └─ VFType (MeshMaterial 时有值)                                               │
  │  │                                                                                 │
  │  └─ StageJobs: TArray<TRefCountPtr<FShaderCompileJob>>                             │
  │      └─ 每个 Stage 对应一个 Single Job                                            │
  │          ├─ Stage 0 (如 Pixel Shader)                                               │
  │          ├─ Stage 1 (如 Vertex Shader)                                              │
  │          └─ ...                                                                     │
  │                                                                                 │
  │  编译流程:                                                                       │
  │  1. BeginCompileShaderPipeline() 创建 Pipeline Job                                 │
  │  2. 为每个 Stage 创建 Single Job                                                   │
  │  3. 每个 Stage Job 包含该 Stage 的 Input/Output                                    │
  │  4. Pipeline Job 只是容器,实际编译在 Stage Jobs 中执行                            │
  │  5. OnComplete 时合并所有 Stage 的 FShader                                        │
  └─────────────────────────────────────────────────────────────────────────────────────┘

  共享 Pipeline 模式:
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │  bShouldOptimizeUnusedOutputs = false                                             │
  │  │                                                                                 │
  │  ├─ Single Job 先编译                                                             │
  │  │                                                                                 │
  │  ├─ Pipeline 引用该 Job:                                                         │
  │  │   Job->SharingPipelines.Add(VFType, Pipeline)                                 │
  │  │                                                                                 │
  │  └─ 运行时通过 Pipeline 字段区分使用                                             │
  └─────────────────────────────────────────────────────────────────────────────────────┘

  ---
  8. 编译作业类型对比表

  ┌──────────────┬─────────────────────────────────────┬──────────────────────────────────────────────────────────────────────┐
  │     维度     │     FShaderCompileJob (Single)      │                 FShaderPipelineCompileJob (Pipeline)                 │
  ├──────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
  │ Key          │ FShaderCompileJobKey                │ FShaderPipelineCompileJobKey                                         │
  ├──────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
  │ Key 包含     │ ShaderType + VFType + PermutationId │ ShaderPipeline + VFType + PermutationId                              │
  ├──────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
  │ Input/Output │ 单个 shader 的 Input/Output         │ 容器，无独立 Input/Output                                            │
  ├──────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
  │ StageJobs    │ 无                                  │ 多个 Stage 的 FShaderCompileJob                                      │
  ├──────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
  │ 编译单元     │ 单个 Shader Stage                   │ 多个 Stage (VS+PS, VS+GS+PS 等)                                      │
  ├──────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
  │ 优化策略     │ 独立优化                            │ 跨 Stage 优化 interpolator（如果 bShouldOptimizeUnusedOutputs=true） │
  ├──────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
  │ OnComplete   │ 创建单个 FShader                    │ 创建多个 FShader 并组合成 FShaderPipeline                            │
  ├──────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
  │ 用途         │ 大多数 shader                       │ 后处理 pass、Velocity pass 等                                        │
  └──────────────┴─────────────────────────────────────┴──────────────────────────────────────────────────────────────────────┘

  ---
  这就是 Unreal Shader CompileJobs 的完整架构。核心概念是：编译作业是携带 Input 和 Output 的可缓存工作单元，通过 Key 进行去重，通过 JobCache 共享，通过 Pipeline 容器组合多个 Stage。
