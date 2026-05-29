---
name: unreal-source-module-structure
description: UE源码目录结构与MCP索引module_name的映射规则，从数据库查询验证得出
metadata: 
  node_type: memory
  type: reference
  originSessionId: 20d974ac-658b-41a8-b7f2-2f5656a0f937
---

# UE 源码目录结构与 MCP module_name 映射

基于实际数据库查询验证。`module_name` 字段对应 `Engine/Source/` 下的**顶层目录名**，不是子模块名。

## module_name 推导规则

```
文件路径                                              → module_name
Engine/Source/Runtime/*      (Engine,Renderer,Core...) → "Runtime"
Engine/Source/Editor/*        (所有编辑器子系统)        → "Editor"
Engine/Source/Developer/*     (所有开发者工具)          → "Developer"
Engine/Source/Programs/*      (所有独立程序)            → "Programs"
Engine/Plugins/*/Source/<ModuleName>/                  → "<ModuleName>" (Build.cs模块名)
```

## 验证数据

| 文件 | module_name |
|------|-------------|
| `Engine/Source/Runtime/Engine/Private/Materials/MaterialRenderProxy.cpp` | `Runtime` |
| `Engine/Source/Runtime/Engine/Private/Materials/MaterialUniformExpressions.cpp` | `Runtime` |
| `Engine/Source/Runtime/Renderer/Public/MaterialShader.h` | `Runtime` |
| `Engine/Source/Editor/DataLayerEditor/...` | `Editor` |
| `Engine/Source/Developer/NaniteBuilder/...` | `Developer` |
| `Engine/Source/Programs/SubmitTool/...` | `Programs` |
| `Engine/Plugins/FX/Niagara/Source/NiagaraCore/...` | `NiagaraCore` |

## 使用方式

```python
# search_code_source module 参数:
#   核心运行时 → module="Runtime"  （不是 "Engine", "Renderer", "Core"）
#   编辑器     → module="Editor"
#   开发者工具 → module="Developer"
#   插件       → 具体模块名，如 module="NiagaraCore"

# find_callers scope 参数同理:
find_callers("Execute", scope="Runtime")  # 不是 scope="Renderer"
```

## 常见错误

| 错误 | 原因 |
|------|------|
| `module="Engine"` | "Engine" 是 Runtime 下的子目录，不是 module_name |
| `module="Renderer"` | "Renderer" 是 Runtime 下的子目录，不是 module_name |
| `module="Core"` | "Core" 是 Runtime 下的子目录，不是 module_name |
