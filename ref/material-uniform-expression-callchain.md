# Material Uniform Expression 值计算调用链与引用

## 整体架构

```
┌──────────────────────────────────────────────────────────────────┐
│ Layer 4: 渲染管线触发                                            │
│  DrawMesh / AddMesh / Commit / RayTracing →                      │
│  UpdateUniformExpressionCacheIfNeeded()                           │
├──────────────────────────────────────────────────────────────────┤
│ Layer 3: 缓存入口                                                │
│  CacheUniformExpressions() → UpdateDeferredCachedUniformExpressions()│
│  → EvaluateUniformExpressions()                                   │
├──────────────────────────────────────────────────────────────────┤
│ Layer 2: 求值核心 (FillUniformBuffer)                             │
│  路径A: 直接参数求值 → UniformParameterEvaluations                │
│  路径B: Preshader字节码执行 → EvaluatePreshader()                 │
├──────────────────────────────────────────────────────────────────┤
│ Layer 1: 表达式基类                                              │
│  FMaterialUniformExpression → GetNumberValue() / WriteNumberOpcodes()│
└──────────────────────────────────────────────────────────────────┘
```

## 完整调用链

### 1. 渲染管线触发（调用方）

`UpdateUniformExpressionCacheIfNeeded` 在以下场景被调用：

| 调用方 | 文件 | 场景 |
|--------|------|------|
| `FViewElementPDI::DrawMesh` | `DynamicPrimitiveDrawing.inl:265` | 动态绘制元素 |
| `FMeshElementCollector::Commit` | `SceneManagement.cpp:548` | 静态/动态网格收集 |
| `FMeshElementCollector::AddMesh` | `SceneManagement.cpp:624` | 添加mesh到收集器 |
| `RayTracing` | `RayTracing.cpp:1999` | 光线追踪 |
| `MaterialCacheMeshProcessor` | `MaterialCacheMeshProcessor.cpp:158` | Material Cache |
| `FRenderer` | `Renderer.cpp:379` | 渲染器主循环 |
| Slate UI | `SlateRHIRenderingPolicy.cpp:1096` | UI渲染 |
| Landscape | `LandscapePhysicalMaterial.cpp:260` | 地形物理材质 |

### 2. 缓存入口 → 求值

```
GameThread: CacheUniformExpressions_GameThread()
  └─ ENQUEUE_RENDER_COMMAND → CacheUniformExpressions(RHICmdList, bRecreate)
       ├─ InitResource(RHICmdList)          // 注册为渲染资源
       ├─ StartCacheUniformExpressions()    // 设置缓存标志
       ├─ DeferredUniformExpressionCacheRequests.Add(this)  // 延迟队列
       ├─ InvalidateUniformExpressionCache(bRecreateUniformBuffer)
       └─ UpdateDeferredCachedUniformExpressions(RHICmdList)
            ├─ 构建 FMaterialRenderContext(MaterialProxy, Material, nullptr)
            ├─ 对每个 FeatureLevel:
            │    └─ EvaluateUniformExpressions(RHICmdList, Cache[FL], Context, Updater)
            └─ FinishCacheUniformExpressions()
```

**懒更新路径**（渲染时按需）：
```
UpdateUniformExpressionCacheIfNeeded(RHICmdList, FeatureLevel)
  ├─ GetMaterialNoFallback(FeatureLevel)
  ├─ 比较 CachedUniformExpressionShaderMap != CurrentShaderMap?
  └─ 若需更新: EvaluateUniformExpressions(RHICmdList, Cache[FL], Context, nullptr)
```

### 3. EvaluateUniformExpressions（核心入口）

`MaterialRenderProxy.cpp:439`

```
FMaterialRenderProxy::EvaluateUniformExpressions()
  ├─ ShaderMap = Context.Material.GetRenderingThreadShaderMap()
  ├─ UniformExpressionSet = ShaderMap->GetUniformExpressionSet()
  │
  ├─ VT Stack 分配 (AllocateVTStack / GetPreallocatedVTStack)
  ├─ MaterialCacheTag 订阅
  │
  ├─ [异步路径] Updater→Add(Cache, UniformExpressionSet, Layout, Context)
  │   └─ 稍后由 FUniformExpressionCacheAsyncUpdater::Update() 批量执行
  │
  └─ [同步路径] 直接调用:
      ├─ FMemStack 分配 TempBuffer
      └─ UniformExpressionSet.FillUniformBuffer(Context, Cache, Layout, TempBuffer, Size)
           ├─ RHI UpdateUniformBuffer 或 RHICreateUniformBuffer
           └─ EvaluateParameterCollections()
```

### 4. FillUniformBuffer（双路径求值）

`MaterialUniformExpressions.cpp:1048` — 实际计算 uniform 值的地方：

```
FUniformExpressionSet::FillUniformBuffer()
  │
  ├─ [VT Uniform Data] — 虚拟纹理 PageTable uniform
  │    AllocatedVT->GetPackedPageTableUniform()
  │
  ├─ [Sparse Volume Texture Uniform Data]
  │    RenderResources->GetPackedUniforms()
  │
  ├─ [路径A: 直接参数求值] — UniformParameterEvaluations 循环
  │    for (const FMaterialUniformParameterEvaluation& Eval : UniformParameterEvaluations):
  │      ├─ GetNumericParameter(Eval.ParameterIndex) → Parameter
  │      ├─ 解析参数值 (三级 fallback):
  │      │   1. MaterialRenderProxy->GetParameterShaderValue()  // Proxy 覆盖
  │      │   2. [Editor] TransientOverrides.GetNumericOverride() // 编辑器覆盖
  │      │   3. GetDefaultParameterValue()                       // 编译时默认值
  │      └─ CopyValueToUniformBuffer(Value, Buffer, Offset)      // 写入 Float/Int/Bool/Double
  │
  └─ [路径B: Preshader 字节码执行] — UniformPreshaders 循环
       float* PreshaderBuffer = (float*)BufferCursor;
       for (const FMaterialUniformPreshaderHeader& Preshader : UniformPreshaders):
         ├─ FPreshaderDataContext(UniformPreshaderData, Offset, Size)
         ├─ Result = EvaluatePreshader(this, Context, PreshaderStack, PreshaderContext)
         └─ CopyValueToUniformBuffer(Result, PreshaderBuffer, Field.BufferOffset)
```

### 5. EvaluatePreshader（字节码解释器）

`Preshader.cpp` — 基于栈的字节码虚拟机：

```
EvaluatePreshader(UniformExpressionSet, Context, Stack, Data):
  while (Data.Ptr < DataEnd):
    switch (Opcode):
      ConstantZero / Constant     → 压栈常量
      Parameter                   → 从 UniformExpressionSet 读取参数值压栈
      GetField / SetField         → 结构体字段操作
      PushValue / Assign          → 栈操作
      Add / Sub / Mul / Div       → 算术运算
      Less / Greater / LessEqual  → 比较运算
      Fmod / Floor / Frac / ...   → 数学函数
      Sin / Cos / Sqrt / Pow      → 三角/幂函数
      JumpIfTrue / JumpIfFalse    → 条件跳转
```

### 6. 表达式基类层级

```
FMaterialUniformExpression (MaterialUniformExpressions.h:57)
  ├─ GetNumberValue(Context, OutValue)     — 运行时直接求值（旧路径）
  ├─ WriteNumberOpcodes(PreshaderData)     — 编译时生成 preshader 字节码（新路径）
  ├─ IsConstant()                          — 是否常量表达式
  ├─ GetChildren()                         — 子表达式
  └─ UniformOffset / UniformIndex          — 在 uniform buffer 中的位置

派生类:
  FMaterialUniformExpressionConstant           — 常量值
  FMaterialUniformExpressionGenericConstant    — 泛型常量
  FMaterialUniformExpressionTexture            — 纹理引用
  FMaterialUniformExpressionTextureParameter   — 纹理参数
  FMaterialUniformExpressionExternalTexture    — 外部纹理
  FMaterialUniformExpressionTextureCollection  — 纹理集合
```

### 7. Shader 绑定（消费侧）

求值后的 `UniformExpressionCache.UniformBuffer` 在 shader 绑定时被消费：
- `FMaterialShader::SetParameters()` — 读取 `CachedUniformExpressionShaderMap` 确认缓存有效
- `FMeshMaterialShader` 绑定 uniform buffer 到 shader

## 关键文件索引

| 文件 | 角色 |
|------|------|
| `Materials/MaterialRenderProxy.h/cpp` | 缓存入口 + EvaluateUniformExpressions |
| `Materials/MaterialUniformExpressions.h/cpp` | 表达式基类 + FillUniformBuffer 实现 |
| `Public/MaterialShared.h` | FUniformExpressionSet 定义 |
| `Shader/Preshader.cpp` | EvaluatePreshader 字节码 VM |
| `Shader/PreshaderEvaluate.h` | Preshader API 声明 |
| `Materials/HLSLMaterialTranslator.cpp` | 编译时表达式 → preshader 转换 |
| `Materials/MaterialInstance.cpp` | MI 参数变更时触发 CacheUniformExpressions |
