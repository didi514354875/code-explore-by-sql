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

    # UE-style generated body macros to skip
    generated_body_re: re.Pattern | None = None

    # UE prefix letters for fuzzy resolution
    ue_prefixes: tuple[str, ...] = ()

    # RPC specifiers for rpc_routing edges
    rpc_specifiers: frozenset[str] = field(default_factory=frozenset)
    blueprint_native_event: str = ""

    # Static call noise targets to skip
    noise_call_targets: frozenset[str] = field(default_factory=frozenset)

    # Whether to extract UE metadata from decoration macros
    extract_ue_meta: bool = False

    # Whether to sniff decoration macros above blocks
    sniff_decoration_above: bool = False

    # Extra symbol types to extract (delegate_def, macro_def, etc.)
    extra_symbol_types: frozenset[str] = field(default_factory=frozenset)


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
