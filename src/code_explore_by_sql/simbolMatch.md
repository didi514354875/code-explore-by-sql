---
  符号匹配全流程总结
  
  一、入口：analyze_file(lines, file_id)

  对每个源文件执行：
  1. bracket_scanner FSM 扫描所有 {...} 块
  2. compute_parent_map 计算每个块的父块
  3. 按 open_line 排序（保证父块先于子块处理）
  4. 对每个块调用 _classify_block 分类
  5. 额外提取无花括号的符号（委托、宏）

  ---
  二、声明收集：_gather_declaration
  
  从 { 所在行向上回溯最多 24 行，收集声明文本。

  跳过规则（不加入 context，不中断）：
  - 空行（平衡归零时中断）
  - GENERATED_BODY / UMETA / UPARAM 等 UE 噪声宏
  - # 开头的预处理器指令（#if/#endif 等）

  中断规则（停止回溯）：
  - 遇到 ;、}、): 结尾的行
  - 遇到 public: / private: / protected:
  - 遇到 namespace/class/struct/enum 关键字 + 括号平衡归零
  - 遇到 函数名( 模式 + 括号平衡归零（但 : / , 开头的成员初始化行不触发此中断）
  - 遇到 template 开头

  快速返回（不回溯）：
  当 { 所在行本身已包含完整声明（如 class X : public Y {），且不以 :/, 开头时直接返回。

  ---
  三、声明清洗：_normalize_decl

  对收集到的文本依次：
  1. 去除块注释 /* */ 和行注释 //
  2. 去除 __attribute__ / __declspec / alignas
  3. 去除调用约定（__cdecl / WINAPI / FORCEINLINE 等）
  4. 去除导出宏（*_API）
  5. 合并空白

  ---
  四、块分类：_classify_block
  
  按优先级依次尝试：

  优先级: 1
  检测模式: #define 在 context 中
  block_type: macro_def
  QN 规则: 无（跳过）
  说明: 不产生有效 QN
  ────────────────────────────────────────
  优先级: 2
  检测模式: 全大写宏模式 ^[A-Z][A-Z0-9_]*...$   
  block_type: —
  QN 规则: 跳过
  说明: 未知宏块
  ────────────────────────────────────────      
  优先级: 3
  检测模式: extern "C"
  block_type: namespace
  QN 规则: 无
  说明: 作为命名空间边界
  ────────────────────────────────────────
  优先级: 4
  检测模式: namespace Xxx
  block_type: namespace
  QN 规则: 支持嵌套 Ns1::Ns2
  说明: inline namespace 也支持
  ────────────────────────────────────────
  优先级: 5
  检测模式: enum (class|struct)? Xxx
  block_type: enum
  QN 规则: Ns::Xxx 或 Xxx
  说明: 支持 enum class 和 enum struct
  ────────────────────────────────────────
  优先级: 6
  检测模式: (class|struct) Xxx (: public Base)?
  block_type: class
  QN 规则: 直接用类名
  说明: 捕获第一个基类
  ────────────────────────────────────────
  优先级: 7
  检测模式: Lambda [...](
  block_type: —
  QN 规则: 跳过
  说明: 捕获 spec test 的 It("...", [this](){})
  ────────────────────────────────────────
  优先级: 8
  检测模式: operator 关键字
  block_type: —
  QN 规则: 跳过
  说明: operator new/delete/() 等
  ────────────────────────────────────────
  优先级: 9
  检测模式: 析构函数 ~Xxx(
  block_type: method/function
  QN 规则: Class::Xxx 或 Xxx
  说明:
  ────────────────────────────────────────
  优先级: 10
  检测模式: _CONTROL_FLOW_RE 匹配
  block_type: —
  QN 规则: 跳过
  说明: if(...) while(...) 等
  ────────────────────────────────────────
  优先级: 11
  检测模式: 全大写宏模式
  block_type: —
  QN 规则: 跳过
  说明: 二次检查
  ────────────────────────────────────────
  优先级: 12
  检测模式: 提取函数名后为控制流关键字
  block_type: —
  QN 规则: 跳过
  说明: 拒绝 for(...) 被误提取为函数名 for
  ────────────────────────────────────────
  优先级: 13
  检测模式: 函数签名 Name(params)
  block_type: method/function
  QN 规则: 见下文
  说明: 剥离构造函数初始化列表后再提取

  函数/方法的 QN 规则：
  - 有 ::（外部定义）：ACharacter::Jump → 直接使用
  - 无 ::（内联定义 + 有 parent_class）：自动拼接 ParentClass::Name
  - 无 :: 且无 parent_class：使用裸名

  构造函数初始化列表处理：
  在函数检测之前，将 Foo(params) : member(val), ... 截断为 Foo(params)，防止 : member(val) 干扰分类。

  ---
  五、UE 宏嗅探：_sniff_ue_macro_above

  在块开括号上方 1-3 行查找：
  - UCLASS(...) / USTRUCT(...) / UENUM(...) / UFUNCTION(...) / UPROPERTY(...) / UINTERFACE(...)
  
  找到后：
  - 将 start_line 上移到宏所在行
  - 解析参数存入 ue_meta（如 {"UFUNCTION": ["Server", "Reliable"]})

  ---
  六、ExtraSymbol（无花括号符号）
  
  ┌──────────────────────────────────────────────┬──────────────┬───────────────────────────────┐
  │                     模式                     │  block_type  │             示例              │
  ├──────────────────────────────────────────────┼──────────────┼───────────────────────────────┤
  │ DECLARE_DELEGATE_RetVal(...) 等 DECLARE_* 宏 │ delegate_def │ 提取第一个大写参数作为名      │
  ├──────────────────────────────────────────────┼──────────────┼───────────────────────────────┤
  │ #define XXX                                  │ macro_def    │ 跳过 _ 开头和 GENERATED_ 开头 │
  └──────────────────────────────────────────────┴──────────────┴───────────────────────────────┘

  ---
  七、边提取：extract_edges
  
  4 种严格边类型：

  edge_type: inheritance
  来源: class X : public Base
  提取规则: _CLASS_RE 提取基类名
  过滤: 跳过 _SKIP_TYPES（AActor/UObject 等）和长度 <3
  ────────────────────────────────────────
  edge_type: type_dependency
  来源: 函数声明参数类型 + 类成员变量类型
  提取规则: _PARAM_TYPE_RE / _TYPE_RE
  过滤: _ALL_SKIP_TYPES = 基础类型 + ~150 个噪声词
  ────────────────────────────────────────
  edge_type: static_call
  来源: ClassName::Method( / Super::Method(
  提取规则: _STATIC_CALL_RE / _SUPER_CALL_RE
  过滤: 跳过 _ALL_SKIP_TYPES + _CONTROL_FLOW；Super:: 解析为 parent_class::Method
  ────────────────────────────────────────
  edge_type: rpc_routing
  来源: UFUNCTION(Server/Client/NetMulticast/BlueprintNativeEvent)
  提取规则: 从 ue_meta 生成
  过滤: 跳过已以 _Implementation/_Validate 结尾的符号

  ---
  八、查询时符号解析：read_symbol
  
  三层降级查找：
  1. 精确匹配：qualified_name = ?
  2. UE 前缀补全：Actor → 尝试 AActor / UActor / FActor / EActor / IActor / TActor
  3. 部分匹配：qualified_name LIKE '%Name%'（如 Jump 匹配 ACharacter::Jump）

  返回带 [System Hint] 头的代码块，包含 QN、文件位置、UE 元数据、静态关系（边）、反向关系（谁引用了我）。

  现状一目了然——全部硬编码在模块顶层常量里，UE 特有、C++ 通用、项目特有的逻辑完全混在一起。没有分层。

  下面是我的分析：

  当前问题

  symbol_analyzer.py          edge_extractor.py           build_db.py
  ┌──────────────────┐     ┌──────────────────┐     ┌────────────────┐
  │ C++ 通用:        │     │ C++ 通用:        │     │ .cs .h .cpp    │ ← C#混入
  │  _CLASS_RE       │     │  _CONTROL_FLOW   │     │ 全部走同一管道  │
  │  _ENUM_RE        │     │  _NOISE_TYPE_    │     └────────────────┘
  │  _CONTROL_FLOW_* │     │                  │
  │                  │     │ UE 特有:         │     无语言判断
  │ UE 特有:         │     │  _RPC_SPECIFIERS │     无框架判断
  │  _UE_DECORATION  │     │  _BLUEPRINT_*    │
  │  _UE_DECLARE     │     │  _SKIP_TYPES     │ ← 基础类型和
  │  _UE_NOISE       │     │    (混合了UE+通用)│    UE类型混在一起
  │  _UE_PREFIXES    │     │                  │
  │  _BASIC_TYPES    │     └──────────────────┘
  │   (不应该在这)   │
  └──────────────────┘

  后果：
  - 加 C# 支持要改 3 个文件，还要动 C++ 的正则
  - 换一个非 UE 项目（纯 C++ / Unity），要删一堆 UE 宏
  - _SKIP_TYPES 里 FVector/AActor 和 int/void 混在一起
  - 无法按文件后缀选择不同的解析策略（.cs 也走 C++ 解析器 → 产生 296 个 [new] 噪声）

  应该的分层

                      ┌─────────────────────────────────┐
                      │         Language Layer           │
                      │  按文件后缀选择解析器             │
                      ├──────────────┬──────────────────┤
                      │   C++ 解析器  │   C# 解析器       │
                      │   .h/.cpp    │   .cs             │
                      └──────┬───────┴──────────────────┘
                             │
                      ┌──────┴──────────────────────────┐
                      │       Framework Layer            │
                      │  按项目配置选择框架规则           │
                      ├──────────────┬──────────────────┤
                      │   UE 规则     │   通用 C++ 规则   │
                      │  UCLASS/UFUNC │  (无框架特殊处理) │
                      │  RPC routing  │                  │
                      │  UE skip types│                  │
                      └──────┬───────┴──────────────────┘
                             │
                      ┌──────┴──────────────────────────┐
                      │       Project Layer              │
                      │  用户可配置                       │
                      ├──────────────────────────────────┤
                      │  SOURCE_EXTENSIONS               │
                      │  EXCLUDE_DIRS                    │
                      │  自定义 skip types                │
                      │  自定义 module 推断规则           │
                      └─────────────────────────────────┘

  每一层应该是独立的、可插拔的配置对象，而不是散落在代码各处的 frozenset。

  要我按这个方向重构吗？核心改动：
  1. 抽出 LanguageConfig / FrameworkConfig 数据类
  2. symbol_analyzer 和 edge_extractor 接受 config 参数而不是读全局常量
  3. build_db 按文件后缀分派到不同的解析管线
  4. UE 规则集中到一个 unreal_rules.py，C# 规则到一个 csharp_rules.py