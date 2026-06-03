"""Layered configuration for code source analysis.

Three layers:
  Language  — syntax rules selected by file extension (C/C++ vs C#)
  Framework — application framework rules (Unreal, Unity, etc.)
  Project   — user-configurable settings (extensions, excludes, module inference)

Any language can combine with any framework (e.g., Unreal uses C# for build system code).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Callable


# ── Language Layer ────────────────────────────────────────────────────────

@dataclass(frozen=True)
class LanguageConfig:
    """Language-specific syntax rules, selected by file extension."""

    name: str  # "cpp", "csharp", etc.

    # Block classification regexes
    class_re: re.Pattern
    enum_re: re.Pattern
    namespace_re: re.Pattern
    func_name_re: re.Pattern
    export_macro_re: re.Pattern
    calling_conv_re: re.Pattern
    attribute_re: re.Pattern
    template_re: re.Pattern
    dtor_re: re.Pattern

    # Stripping / normalisation
    control_flow_re: re.Pattern
    control_flow_names: frozenset[str]
    trailing_mods_re: re.Pattern
    access_spec_re: re.Pattern

    # Comment / noise
    macro_like_re: re.Pattern
    define_re: re.Pattern
    extern_c_re: re.Pattern
    operator_re: re.Pattern | None

    # Whether this language uses brace-based block scoping
    uses_braces: bool = True

    # Whether namespaces affect qualified names
    uses_namespaces: bool = True

    # Whether colon inheritance is used (class Foo : public Bar)
    uses_colon_inheritance: bool = True

    # ── Edge extraction (consumed by edge_extractor.py) ──────────────

    # Scope operator string: "::" for C++, "." for C#
    scope_operator: str = "::"

    # Base/super keyword: "Super" for UE C++, "base" for C#
    base_keyword: str = "Super"

    # Static call pattern: captures (ClassName, MethodName)
    static_call_re: re.Pattern | None = None

    # Super/base call pattern: captures (MethodName)
    super_call_re: re.Pattern | None = None

    # Type name pattern for dependency extraction
    type_re: re.Pattern | None = None

    # Parameter type extraction from function signatures
    param_type_re: re.Pattern | None = None

    # Language-level primitive/standard types that should never generate edges
    basic_skip_types: frozenset[str] = field(default_factory=frozenset)

    # ── Block classification helpers (consumed by symbol_analyzer.py) ─

    # Combined keyword regex for namespace|class|struct|enum detection
    block_keyword_re: re.Pattern | None = None

    # Lambda expression detection regex (None if language has no lambdas)
    lambda_re: re.Pattern | None = None

    # Namespace signature regex for _classify_block (captures namespace name)
    namespace_sig_re: re.Pattern | None = None

    # Constructor initializer list pattern: "):" or similar
    init_list_re: re.Pattern | None = None

    # ── View / summary helpers (consumed by code_block_summary.py) ────

    # Access specifier names for view filtering (e.g. {"public:", "private:", "protected:"})
    access_spec_names: frozenset[str] = field(default_factory=frozenset)

    # Structural keywords for signature view detection (e.g. {"class ", "struct ", "enum ", "namespace "})
    view_structural_kws: tuple[str, ...] = ()

    # Modifier keywords for signature view (e.g. {"virtual ", "static ", "override", "FORCEINLINE"})
    view_modifier_kws: tuple[str, ...] = ()

    # Local variable type modifiers (e.g. "const|static|mutable|constexpr|volatile")
    local_var_modifiers: str = ""

    # ── Bracket scanner hints ────────────────────────────────────────

    # Character prefix for verbatim strings (None if not supported, '@' for C#)
    verbatim_string_prefix: str | None = None

    # Character that starts a raw string literal (None if unsupported)
    # C++: "R" → R"delim(...)delim", C#: None
    raw_string_char: str | None = None

    # ── Function body summary hints ──────────────────────────────────

    # Range-based for loop pattern for function body summary (None if unsupported)
    # C++: for (Type name : container), C#: foreach (Type name in collection)
    range_for_re: re.Pattern | None = None


# ── Framework Layer ───────────────────────────────────────────────────────

@dataclass(frozen=True)
class FrameworkConfig:
    """Application-framework-specific rules, overlaid on any language."""

    name: str  # "unreal", "unity", "generic", etc.

    # Types that should never generate reference edges
    skip_types: frozenset[str] = field(default_factory=frozenset)

    # Noise type names — matched but never real types
    noise_type_names: frozenset[str] = field(default_factory=frozenset)

    # UE-style decoration macros (UCLASS, UFUNCTION, etc.)
    decoration_macro_re: re.Pattern | None = None
    decoration_macro_names: frozenset[str] = field(default_factory=frozenset)

    # Noise macros to skip during declaration gathering
    noise_macro_re: re.Pattern | None = None

    # Declaration macros for extra symbols (DECLARE_DELEGATE, etc.)
    declare_macro_re: re.Pattern | None = None

    # Framework-specific generated body macros to skip
    generated_body_re: re.Pattern | None = None

    # Type prefix letters for fuzzy resolution (e.g., UE's A/U/F/E/I)
    # (Obsolete — use resolve_type_prefixes callback instead)
    type_prefixes: tuple[str, ...] = ()

    # RPC specifiers for framework-specific edges (obsolete — use extract_framework_edges)
    rpc_specifiers: frozenset[str] = field(default_factory=frozenset)
    blueprint_native_event: str = ""

    # Static call noise targets to skip
    # (Obsolete — no longer read from framework layer)

    # Parameter name that triggers _Validate suffix in RPC routing formatting
    # (Obsolete — use extract_framework_edges callback instead)
    rpc_validation_param: str = ""

    # Whether to extract decoration metadata from decoration macros
    extract_decoration_meta: bool = False

    # Whether to sniff decoration macros above blocks
    sniff_decoration_above: bool = False

    # Extra symbol types to extract (delegate_def, macro_def, etc.)
    extra_symbol_types: frozenset[str] = field(default_factory=frozenset)

    # ── Framework behavior callbacks ──────────────────────────────────
    # These allow framework-specific algorithm logic to live in
    # the framework layer instead of inline in processing modules.
    # Processing modules call these callbacks; generic framework = None.

    # Extract framework-specific edges from decoration metadata.
    # Takes (qualified_name: str, decoration_meta: dict) -> [(target_qn, edge_type)]
    extract_framework_edges: Callable[[str, dict], list[tuple[str, str]]] | None = None

    # Parse delegate/type name from a declaration macro line.
    # Takes (stripped_line: str) -> name or None
    parse_delegate_name: Callable[[str], str | None] | None = None

    # Filter macro names that should be excluded from symbol extraction.
    # Takes (macro_name: str) -> True = skip this macro
    macro_name_filter: Callable[[str], bool] | None = None

    # Format decoration metadata into display parts for [Meta] header.
    # Takes (meta: dict) -> [display_string, ...]
    format_meta_display: Callable[[dict], list[str]] | None = None

    # Generate candidate QNs by prepending type prefixes.
    # Takes (qualified_name: str) -> [candidate_qn, ...]
    resolve_type_prefixes: Callable[[str], list[str]] | None = None


# ── Project Layer ─────────────────────────────────────────────────────────

@dataclass(frozen=True)
class ProjectConfig:
    """User-configurable project settings."""

    # File extensions to index, mapped to language name
    extension_to_language: dict[str, str] = field(default_factory=dict)

    # Directories to exclude from indexing
    exclude_parts: frozenset[str] = field(default_factory=frozenset)

    # Path component marking source root
    source_marker: str = "Source"

    # Category dirs to skip after source marker
    categories: frozenset[str] = field(default_factory=frozenset)

    # Invalid module name components
    invalid_module_names: frozenset[str] = field(default_factory=frozenset)

    # Framework to apply (by name or config instance)
    framework_name: str = "generic"


# ── Defaults ──────────────────────────────────────────────────────────────

def make_cpp_language() -> LanguageConfig:
    """C/C++ language configuration."""
    return LanguageConfig(
        name="cpp",
        class_re=re.compile(
            r"(?:^|\s)(class|struct)\s+"
            r"(?:(?:[A-Z][A-Z0-9_]*_API|[A-Z][A-Z0-9_]*(?:\s*\([^)]*\))?)\s+)*"
            r"(\w+)"
            r"\s*(?::\s*(?:public|protected|private)\s+(\w+))?",
        ),
        enum_re=re.compile(r"\benum\s+(?:(?:class|struct)\s+)?(\w+)"),
        namespace_re=re.compile(r"\bnamespace\s+(\w+)"),
        func_name_re=re.compile(r"(\w+(?:\s*::\s*\w+)*)\s*\([^)]*\)\s*$"),
        export_macro_re=re.compile(r"\b[A-Z][A-Z0-9_]*_API\b"),
        calling_conv_re=re.compile(
            r"\b(?:__cdecl|__stdcall|__fastcall|__thiscall|__vectorcall|WINAPI|CALLBACK|"
            r"STDMETHODCALLTYPE|FORCEINLINE|FORCENOINLINE|FORCEINLINE_DEBUGGABLE|inline)\b"
        ),
        attribute_re=re.compile(
            r"\b(?:__declspec|__attribute__|alignas)\s*\([^)]*(?:\)[^)]*)?\)|\[\[[^\]]*\]\]"
        ),
        template_re=re.compile(r"\btemplate\s*<[^<>]*>"),
        dtor_re=re.compile(r"~(\w+)\s*\("),
        control_flow_re=re.compile(r"\b(if|else\s+if|else|while|for|do|switch|catch|try)\b"),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "do", "switch", "catch", "try",
            "return", "delete", "goto", "break", "continue", "throw",
            "co_await", "co_yield", "co_return",
        }),
        trailing_mods_re=re.compile(
            r"\s*(?:const|override|final|noexcept|mutable|constexpr|inline|static)\s*[;{]*\s*$"
        ),
        access_spec_re=re.compile(r"^(?:public|private|protected)\s*:\s*(?://.*)?$"),
        macro_like_re=re.compile(r"^[A-Z][A-Z0-9_]*\s*(?:\([^{};]*\))?\s*$"),
        define_re=re.compile(r"#\s*define\s+"),
        extern_c_re=re.compile(r'\bextern\s+"C"'),
        operator_re=re.compile(r"\boperator\b"),
        uses_braces=True,
        uses_namespaces=True,
        uses_colon_inheritance=True,
        # Edge extraction
        scope_operator="::",
        base_keyword="Super",
        static_call_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)::([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        super_call_re=re.compile(r"\bSuper::([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(
            r"(?:const\s+)?([A-Z][A-Za-z0-9_]+)\s*(?:\*+|&)?\s+\w+"
        ),
        basic_skip_types=frozenset({
            "int8", "int16", "int32", "int64",
            "uint8", "uint16", "uint32", "uint64",
            "float", "double", "bool", "void", "int", "char", "long", "short",
            "unsigned", "size_t", "auto", "nullptr_t",
        }),
        # Block classification helpers
        block_keyword_re=re.compile(r"\b(?:namespace|class|struct|enum)\b"),
        lambda_re=re.compile(r"\[.*\]\s*[\(]"),
        namespace_sig_re=re.compile(r"(?:inline\s+)?namespace\s+(\w+)?\s*$"),
        init_list_re=re.compile(r"\)\s*:"),
        # View / summary helpers
        access_spec_names=frozenset({"public:", "protected:", "private:"}),
        view_structural_kws=("class ", "struct ", "enum ", "namespace "),
        view_modifier_kws=("virtual ", "static ", "override", "FORCEINLINE"),
        local_var_modifiers="const|static|mutable|constexpr|volatile",
        # Bracket scanner hints
        verbatim_string_prefix=None,
        raw_string_char="R",
        # Function body summary hints
        range_for_re=re.compile(
            r"for\s*\(\s*(?:const\s+)?(\w+(?:\s*<[^>]*>)?)\s*[*&]?\s+(\w+)\s*:\s*(\w+)"
        ),
    )


def make_csharp_language() -> LanguageConfig:
    """C# language configuration."""
    return LanguageConfig(
        name="csharp",
        class_re=re.compile(
            r"(?:^|\s)(class|struct|interface|record)"
            r"(?:\s+(?:class|struct))?"  # C# compound: record struct, record class, interface class
            r"\s+"
            r"(\w+)"
            r"\s*(?::\s*(\w+))?",
        ),
        enum_re=re.compile(r"\benum\s+(\w+)"),
        namespace_re=re.compile(r"\bnamespace\s+([\w.]+)"),
        func_name_re=re.compile(r"(\w+)\s*\([^)]*\)\s*$"),
        export_macro_re=re.compile(r"(?!x)x"),  # never matches — no export macros in C#
        calling_conv_re=re.compile(r"(?!x)x"),
        attribute_re=re.compile(r"\[[^\]]*\]"),
        template_re=re.compile(r"<[^<>]*>"),
        dtor_re=re.compile(r"(?!x)x"),  # C# uses Dispose pattern, not ~
        control_flow_re=re.compile(r"\b(if|else\s+if|else|while|for|foreach|do|switch|catch|try|using|lock)\b"),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "foreach", "do", "switch", "catch", "try",
            "return", "break", "continue", "throw", "using", "lock", "yield",
            "async", "await", "new", "this", "base", "typeof", "sizeof", "nameof",
            "default", "checked", "unchecked", "delegate",
        }),
        trailing_mods_re=re.compile(r"\s*(?:override|virtual|abstract|sealed|static|async)\s*[;{]*\s*$"),
        access_spec_re=re.compile(r"^(?!x)x"),  # C# has no standalone access-spec lines
        macro_like_re=re.compile(r"(?!x)x"),  # no macros in C#
        define_re=re.compile(r"(?!x)x"),
        extern_c_re=re.compile(r"(?!x)x"),
        operator_re=None,
        uses_braces=True,
        uses_namespaces=True,
        uses_colon_inheritance=True,
        # Edge extraction
        scope_operator=".",
        base_keyword="base",
        static_call_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        super_call_re=re.compile(r"\bbase\.([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(
            r"([A-Z][A-Za-z0-9_]+)\s+\w+"
        ),
        basic_skip_types=frozenset({
            "int", "uint", "long", "ulong", "short", "ushort",
            "byte", "sbyte", "float", "double", "decimal",
            "bool", "string", "object", "void", "char",
            "var", "dynamic", "nint", "nuint",
        }),
        # Block classification helpers
        block_keyword_re=re.compile(r"\b(?:namespace|class|struct|interface|record|enum)\b"),
        lambda_re=re.compile(r"(?:\w+\s*=>|delegate\s*\()"),  # C# lambdas: x => ... or delegate(...)
        namespace_sig_re=re.compile(r"namespace\s+([\w.]+)\s*$"),
        init_list_re=None,  # C# uses constructor chaining, not initializer lists
        # View / summary helpers
        access_spec_names=frozenset({"public", "private", "protected", "internal", "protected internal", "private protected"}),
        view_structural_kws=("class ", "struct ", "interface ", "record ", "enum ", "namespace "),
        view_modifier_kws=("virtual ", "static ", "override", "abstract ", "sealed ", "async "),
        local_var_modifiers="const|static|volatile|readonly|ref|out",
        # Bracket scanner hints
        verbatim_string_prefix="@",
        raw_string_char=None,
        # Function body summary hints
        range_for_re=re.compile(
            r"foreach\s*\(\s*(\w+(?:\s*<[^>]*>)?)\s+(\w+)\s+in\s+(\w+)"
        ),
    )


def make_generic_framework() -> FrameworkConfig:
    """Generic framework — no framework-specific rules."""
    return FrameworkConfig(name="generic")


def make_unreal_project(
    framework: FrameworkConfig | None = None,
    extra_extensions: dict[str, str] | None = None,
) -> ProjectConfig:
    """Default Unreal Engine project configuration."""
    ext_map: dict[str, str] = {
        ".h": "cpp", ".hpp": "cpp", ".hh": "cpp", ".inl": "cpp",
        ".cpp": "cpp", ".cc": "cpp", ".cxx": "cpp",
        ".cs": "csharp",
        ".usf": "cpp", ".ush": "cpp", ".hlsl": "cpp",
    }
    if extra_extensions:
        ext_map.update(extra_extensions)

    return ProjectConfig(
        extension_to_language=ext_map,
        exclude_parts=frozenset({
            ".git", ".vs", "Binaries", "Build", "DerivedDataCache",
            "Intermediate", "Saved", "ThirdParty",
        }),
        source_marker="Source",
        categories=frozenset(),
        invalid_module_names=frozenset({
            "Private", "Public", "Classes", "Inc", "Src", "Source",
            "Include", "Internal", "Tests", "Test",
        }),
        framework_name=framework.name if framework else "generic",
    )
