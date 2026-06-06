"""Layered configuration for code source analysis.

Three layers:
  Language  — syntax rules selected by file extension (C/C++ vs C#)
  Framework — application framework rules (Unreal, Unity, etc.)
  Project   — user-configurable settings (extensions, excludes, module inference)

Any language can combine with any framework (e.g., Unreal uses C# for build system code).
"""

from __future__ import annotations

import re
from collections.abc import Callable
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

    # Function signature end pattern: matches when a joined declaration looks like
    # a complete function signature. C/C++: ")", ") const". Python: "):".
    func_sig_end_re: re.Pattern = re.compile(r"\)\s*(?:const\s*)?$")

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

    # ── Comment syntax (consumed by bracket_scanner, symbol_analyzer, edge_extractor, code_block_summary) ──

    # Line comment prefix (e.g. "//" for C-family, "#" for Python)
    line_comment: str = "//"

    # Block comment open/close pair, or None if unsupported
    block_comment_pair: tuple[str, str] | None = ("/*", "*/")

    # ── String syntax (consumed by bracket_scanner) ───────────────────

    # Characters that start string literals (e.g. {'"', "'"} for Python, {'"'} for C++ where ' is char)
    string_delimiters: frozenset[str] = frozenset({'"', "'"})

    # Escape character inside strings (None if no escape mechanism)
    string_escape_char: str | None = "\\"

    # Triple-quoted string openers for indent-based languages (e.g. ('"""', "'''") for Python)
    triple_quote_strings: tuple[str, ...] = ()

    # ── Block style (consumed by bracket_scanner) ─────────────────────

    # Whether this language uses indent-based blocks instead of braces
    uses_indent_blocks: bool = False

    # ── Preprocessor (consumed by symbol_analyzer, edge_extractor, code_block_summary) ──

    # Preprocessor directive prefix (e.g. "#" for C/C++, "" if none)
    preprocessor_prefix: str = "#"

    # Whether #define-style macros exist (controls macro_def extraction)
    has_preprocessor_macros: bool = True

    # ── Statement / block close (consumed by code_block_summary) ──────

    # Statement terminator character (e.g. ";" for C-family, "" for Python)
    statement_terminator: str = ";"

    # Closing brace syntax for summary output (e.g. "};" for C++, "}" for most others)
    block_close_suffix: str = "}"

    # Comment prefix for summary lines (e.g. "//" for C-family, "#" for Python)
    summary_comment_prefix: str = "//"

    # ── Config-driven control flow (consumed by code_block_summary) ───

    # Control flow patterns: tuple of (label, compiled_regex) for function body summary
    control_flow_patterns: tuple[tuple[str, re.Pattern], ...] = ()

    # Return keyword regex for function body summary
    return_re: re.Pattern | None = None

    # ── Extra syntax hints ────────────────────────────────────────────

    # Pointer/reference type indicator chars (e.g. "*&" for C/C++, "" for Python/Java)
    type_indicator_chars: str = "*&"

    # Full #define line regex for ExtraSymbol extraction (None if language has no macros)
    define_line_re: re.Pattern | None = None

    # Whether backtick template literal strings exist (JavaScript/TypeScript)
    has_template_strings: bool = False

    # Raw string syntax style: "cpp" for R"delim(...)delim", "rust" for r#"..."#
    raw_string_style: str = "cpp"


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


# ── Framework / Project Defaults ──────────────────────────────────────────

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
        ".usf": "hlsl", ".ush": "hlsl", ".hlsl": "hlsl",
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


def make_generic_project(
    extra_extensions: dict[str, str] | None = None,
) -> ProjectConfig:
    """Generic project configuration supporting all registered languages."""
    ext_map: dict[str, str] = {
        # C/C++
        ".h": "cpp", ".hpp": "cpp", ".hh": "cpp", ".inl": "cpp",
        ".c": "c", ".cpp": "cpp", ".cc": "cpp", ".cxx": "cpp",
        # C#
        ".cs": "csharp",
        # Java
        ".java": "java",
        # Go
        ".go": "go",
        # Rust
        ".rs": "rust",
        # JavaScript/TypeScript
        ".js": "javascript", ".jsx": "javascript", ".mjs": "javascript",
        ".ts": "typescript", ".tsx": "typescript",
        # Kotlin
        ".kt": "kotlin", ".kts": "kotlin",
        # Swift
        ".swift": "swift",
        # Python
        ".py": "python", ".pyi": "python",
        # HLSL
        ".hlsl": "hlsl", ".fx": "hlsl", ".fxh": "hlsl",
        # GLSL
        ".glsl": "glsl", ".vert": "glsl", ".frag": "glsl",
        ".comp": "glsl", ".geom": "glsl", ".tesc": "glsl", ".tese": "glsl",
    }
    if extra_extensions:
        ext_map.update(extra_extensions)

    return ProjectConfig(
        extension_to_language=ext_map,
        exclude_parts=frozenset({".git", ".vs", "node_modules", "__pycache__"}),
        source_marker="",
        categories=frozenset(),
        invalid_module_names=frozenset(),
        framework_name="generic",
    )


# ── Language Registry ──────────────────────────────────────────────────────

_LANGUAGE_FACTORIES: dict[str, Callable[[], LanguageConfig]] = {}


def register_language(name: str, factory: Callable[[], LanguageConfig]) -> None:
    """Register a language factory function."""
    _LANGUAGE_FACTORIES[name] = factory


def get_language(name: str) -> LanguageConfig:
    """Get a LanguageConfig by name, raising ValueError if unknown."""
    if name not in _LANGUAGE_FACTORIES:
        raise ValueError(
            f"Unknown language: {name!r}. Registered: {sorted(_LANGUAGE_FACTORIES.keys())}"
        )
    return _LANGUAGE_FACTORIES[name]()


def registered_languages() -> list[str]:
    """Return sorted list of registered language names."""
    return sorted(_LANGUAGE_FACTORIES.keys())


# Re-export language factory functions from the languages/ subpackage.
# This import triggers registration of all language factories.
from . import languages  # noqa: E402, F401
