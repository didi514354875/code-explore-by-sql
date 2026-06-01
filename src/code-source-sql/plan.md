这份方案是经过深度工程权衡后的最终版本。我们将其命名为 **“面向大模型 Agent 的 UE 极简语义检索架构 (Semantic-Augmented Minimalist Search Architecture)”**。

它的核心哲学是：**用极其廉价的 FTS5 + 正则，提取 100% 确定的静态边界；把所有模糊的、容易引发“笛卡尔积爆炸”的动态指针推导，交由 Agent 的大脑（LLM）通过上下文去完成。**

以下是可直接落地的完整架构设计与执行手册：

---

### 一、 核心存储架构 (三表归一)

底层采用 SQLite，最大程度利用 FTS5 的全文检索能力，放弃臃肿的代码块分离存储，改为**“按文件存储，按行号切片”**。

#### 1. `File_Content_FTS` (底层文本表 & 全文索引)
*   **用途**：存储原始文件，充当 Agent 的“物理文件系统”。
*   **字段**：`file_id` (PK), `module_name` (如 Engine), `file_path`, `content` (全文本，建立 FTS5 索引)。

#### 2. `Symbol_Index` (确定的符号目录)
*   **用途**：记录所有代码实体的坐标和元数据，是 Agent 精准空降的“坐标系”。
*   **字段**：
    *   `qualified_name` (PK/核心键，如 `ACharacter::TakeDamage`, `EPhase::Type`)
    *   `block_type` (`class`, `method`, `enum`, `delegate_def`, `macro_def`)
    *   `file_id`, `start_line`, `end_line` (切片范围，必须包含头上顶着的 UE 宏)
    *   `ue_meta` (JSON 格式，如 `{"UFUNCTION": ["Server", "Reliable"]}`)

#### 3. `Strict_Edges` (确定性静态图谱)
*   **用途**：彻底抛弃 2600万行的全量调用图，只存**毫无歧义、极具价值**的骨架引用（预计压缩至 200万行以内）。
*   **字段**：`source_qn` (发起方), `target_qn` (目标方), `edge_type`。
*   **允许的 edge_type**：
    *   `inheritance`: 继承关系 (`class A : public B`)
    *   `type_dependency`: 强类型依赖 (函数签名中的类型、模板参数)
    *   `static_call`: 显式域调用 (`Super::BeginPlay`, `UGameplayStatics::...`)
    *   `rpc_routing`: UE 宏确定的隐式路由 (如 `ServerFunc` 指向 `ServerFunc_Implementation`)

---

### 二、 源码解析与清洗管线 (Pipeline Rules)

这是防止垃圾数据入库的生命线。解析器扫描 C++ 文件时，必须严格执行以下规则：

#### 🔴 1. 拦截黑名单 (Zero Noise)
*   **丢弃控制流**：禁止将 `if`, `for`, `switch`, `while`, `catch` 识别为 block。
*   **丢弃 UE 噪音宏**：忽略 `GENERATED_BODY()`, `GENERATED_UCLASS_BODY()` 等无逻辑占位符。
*   **基础类型免检**：遇到 `TArray`, `FString`, `int`, `FName` 等底层基元，**不生成引用边**。

#### 🟢 2. 强制 Qualified Name 归一化 (Zero Ambiguity)
*   类外定义：`void ACharacter::Jump()` -> `ACharacter::Jump`
*   类内内联：`class A { void Jump(){} }` -> 强制拼装为 `A::Jump`
*   旧版枚举：`namespace EPhase { enum Type { ... } }` -> 强制拼装为 `EPhase::Type`

#### 🔵 3. UE 宏系统整合 (Macro Awareness)
*   **向上嗅探**：当找到类/函数定义的起始行时，向上扫描 1-3 行，若有 `UCLASS(...)` 或 `UFUNCTION(...)`，将其纳入 `start_line` 范围，并提取括号内的标记存入 `ue_meta`。
*   **隐式路由推导**：如果 `ue_meta` 包含 `Server/Client/NetMulticast/BlueprintNativeEvent`，强制在 `Strict_Edges` 中写入一条指向其 `_Implementation` 的边。

#### ❌ 4. 绝对禁止的操作 (Anti-Cartesian Product)
*   **禁止提取泛化调用**：遇到 `MovementComp->Update()` 或 `Obj.Init()`，**绝对禁止提取 `Update` 作为引用边**。这段逻辑只作为文本保存在代码块中，留给 Agent 去阅读。

---

### 三、 Agent 交互层：动态切片与系统注入 (The Core Magic)

当 Agent 请求查看某个符号时，系统后台进行以下操作，组装出包含“外挂大脑”的代码块喂给 Agent：

1.  **定位切片**：查 `Symbol_Index`，通过行号从 `File_Content_FTS` 中切出完整代码。
2.  **获取边与元数据**：查 `Strict_Edges` 获取其确定的依赖关系。
3.  **组装返回**：在代码块顶部注入一段 `[System Hint]`。

**返回给 Agent 的标准格式示例**：
```cpp
// =====================================================================
// [System Hint]
// Qualified Name: AMyCharacter::ServerEquipWeapon
// File: Runtime/ProjectX/Private/MyCharacter.cpp
// 
// [UE Metadata]: UFUNCTION(Server, Reliable, WithValidation) -> 真实逻辑在 _Implementation 中。
// 
// [Static Relations]:
// - RPC Target: AMyCharacter::ServerEquipWeapon_Implementation
// - RPC Validator: AMyCharacter::ServerEquipWeapon_Validate
// - Type Dependencies: UWeaponComponent, FWeaponData
// 
// [Action Guide]:
// 若遇到指针调用(如 Comp->Init()), 请结合 Type Dependencies 使用 Read_Symbol(ClassName::MethodName) 推导检索。
// =====================================================================
UFUNCTION(Server, Reliable, WithValidation)
void AMyCharacter::ServerEquipWeapon(UWeaponComponent* WeaponComp, FWeaponData Data)
{
    // 通常这里的代码很少，核心逻辑在 Implementation
    WeaponComp->PrepareWeapon(Data); 
}
```

---

### 四、 Agent 工具链与 Prompt 设计

给 Agent 提供极简的两个工具，并在 System Prompt 中注入“UE 探案手册”。

#### 🛠️ Tool 1: `Read_Symbol(qualified_name: str)`
*   **机制**：Agent 核心武器。精准查询上述带有 `[System Hint]` 的代码块。
*   **约束**：强制 Agent 必须传入带有作用域的名称（如 `UWeaponComponent::PrepareWeapon`）。

#### 🛠️ Tool 2: `Search_FTS(keyword: str, path_filter: str = "")`
*   **机制**：全文检索工具，返回命中行及其前后 2 行上下文（Grep 模式，极低 Token 消耗）。
*   **约束**：专门用于找“胶水代码”（Gap），如寻找 `OnDeath.AddDynamic`，或寻找某个无作用域前缀的宏调用。

#### 🧠 Agent System Prompt (行为准则注入)
```text
你是一个资深的 Unreal Engine C++ 工程师，你正在使用一套启发式的极简代码检索引擎。

【搜索法则】
1. 你的第一层推理逻辑是 `Qualified Name (类名::方法名)`。遇到孤立的 `->Update()`，绝不搜索 "Update"，而是观察当前代码上下文的变量类型，或查看顶部的 [Type Dependencies] 提示，推断出它是 `UMyClass`，然后调用 `Read_Symbol("UMyClass::Update")`。
2. 认真阅读代码块顶部的 `[System Hint]`。那里已经为你指明了继承关系和 UE 宏（RPC / BlueprintNativeEvent）的真实路由实现，遇到它们，直接跟随系统提示跳转。
3. 当你追踪 UE 的 Delegate/Event 绑定时，它们属于“胶水代码”。请使用 `Search_FTS("AddDynamic" 或 "Bind")` 配合函数名进行交叉排查。
4. 如果搜索结果过多，系统可能会拒绝返回代码。此时请在参数中加入 `path_filter` (如 Engine, Plugins) 来过滤三方库噪声。
```

---

### 方案总结 (The Verdict)

这个最终方案是一个**高度工程化**的妥协艺术品：
1. **解决数据膨胀**：通过“免检名单”和“放弃泛化调用图”，2600万行引用变废为宝，压缩至极小。
2. **解决 UE 宏污染**：将宏从干扰项变成了 Agent 破局的“路标元数据（Metadata）”。
3. **最极致的 Token 效率**：按文件存储，按需切片，Grep 模式寻迹。Agent 只看它该看的行数。

它放弃了让编译器静态算出一切的幻想，而是**构建了一个坚固的、充满路标的迷宫骨架**，把手电筒交给了大模型，让 Agent 用它的逻辑推导能力走完最后的一米。这在当前的 AI 技术栈中，是应对 Unreal Engine 这种超巨型项目的最优解。