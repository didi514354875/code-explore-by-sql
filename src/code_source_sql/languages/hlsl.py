"""HLSL (High-Level Shading Language) configuration.

Supports DirectX shader syntax including cbuffer, tbuffer, struct, interface,
class (SM5), function semantic annotations (: SV_TARGET), and register() bindings.
"""

from __future__ import annotations

import re

from ..configs import LanguageConfig

_NEVER_MATCH = re.compile(r"(?!x)x")


def make_hlsl_language() -> LanguageConfig:
    """HLSL language configuration — C-like shader language for DirectX."""
    return LanguageConfig(
        name="hlsl",
        # struct + SM5 interface/class (group 3 = optional inheritance base)
        class_re=re.compile(
            r"(?:^|\s)(struct|interface|class)\s+"
            r"(\w+)"
            r"\s*(?::\s*(\w+))?",
        ),
        enum_re=re.compile(r"\benum\s+(\w+)"),
        # No namespaces in HLSL
        namespace_re=_NEVER_MATCH,
        # Must tolerate trailing : SEMANTIC after closing paren
        func_name_re=re.compile(r"(\w+)\s*\([^)]*\)\s*(?::\s*\w+\s*)?$"),
        # No export macros
        export_macro_re=_NEVER_MATCH,
        # No calling conventions
        calling_conv_re=_NEVER_MATCH,
        # Strip register() and packoffset() binding annotations
        attribute_re=re.compile(
            r"\b(?:register|packoffset)\s*\([^)]*\)"
        ),
        # No templates
        template_re=_NEVER_MATCH,
        # No destructors
        dtor_re=_NEVER_MATCH,
        control_flow_re=re.compile(r"\b(if|else\s+if|else|while|for|do|switch)\b"),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "do", "switch",
            "return", "break", "continue", "discard",
        }),
        trailing_mods_re=re.compile(
            r"\s*(?:const|inline|static)\s*[;{]*\s*$"
        ),
        # No access specifiers
        access_spec_re=_NEVER_MATCH,
        macro_like_re=re.compile(r"^[A-Z][A-Z0-9_]*\s*(?:\([^{};]*\))?\s*$"),
        define_re=re.compile(r"#\s*define\s+"),
        # No extern "C"
        extern_c_re=_NEVER_MATCH,
        # No operator overloading
        operator_re=None,
        uses_braces=True,
        uses_namespaces=False,
        uses_colon_inheritance=True,
        # Edge extraction
        scope_operator="::",
        base_keyword="",
        static_call_re=None,
        super_call_re=None,
        # PascalCase types (Texture2D, SamplerState, user-defined structs)
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(
            r"(?:const\s+)?([A-Z][A-Za-z0-9_]+)\s+(?:\*+|&)?\s*\w+"
        ),
        basic_skip_types=frozenset({
            # Scalar types
            "int", "uint", "float", "half", "double", "bool", "void", "dword",
            # Vector types
            "int2", "int3", "int4", "uint2", "uint3", "uint4",
            "float2", "float3", "float4",
            "half2", "half3", "half4",
            "bool2", "bool3", "bool4",
            "double2", "double3", "double4",
            # Matrix types
            "float2x2", "float2x3", "float2x4",
            "float3x2", "float3x3", "float3x4",
            "float4x2", "float4x3", "float4x4",
            "int2x2", "int3x3", "int4x4",
            # Sampler types
            "SamplerState", "SamplerComparisonState",
            # Texture types
            "Texture1D", "Texture2D", "Texture3D", "TextureCube",
            "Texture1DArray", "Texture2DArray", "TextureCubeArray",
            "Texture2DMS", "Texture2DMSArray",
            "RWTexture1D", "RWTexture2D", "RWTexture3D",
            "RWTexture1DArray", "RWTexture2DArray",
            # Buffer types
            "Buffer", "RWBuffer",
            "StructuredBuffer", "RWStructuredBuffer",
            "ByteAddressBuffer", "RWByteAddressBuffer",
            "AppendStructuredBuffer", "ConsumeStructuredBuffer",
            # Parameter modifiers
            "in", "out", "inout", "uniform",
        }),
        # Block classification helpers
        block_keyword_re=re.compile(
            r"\b(?:cbuffer|tbuffer|struct|interface|class|enum)\b"
        ),
        # No lambdas
        lambda_re=None,
        # cbuffer/tbuffer recognized as namespace-like blocks
        # attribute_re already stripped register(b0), leaving optional trailing ":"
        namespace_sig_re=re.compile(
            r"(?:cbuffer|tbuffer)\s+(\w+)\s*(?::\s*)?$"
        ),
        init_list_re=None,
        # View / summary helpers
        access_spec_names=frozenset(),
        view_structural_kws=("struct ", "cbuffer ", "tbuffer ", "interface ", "class "),
        view_modifier_kws=("static ", "inline "),
        local_var_modifiers="const|static|uniform|volatile",
        # Bracket scanner hints
        verbatim_string_prefix=None,
        raw_string_char=None,
        # No range-based for in HLSL
        range_for_re=None,
        # Comment syntax (same as C)
        line_comment="//",
        block_comment_pair=("/*", "*/"),
        # String syntax — only double-quoted strings in HLSL
        string_delimiters=frozenset({'"'}),
        string_escape_char="\\",
        triple_quote_strings=(),
        # Block style
        uses_indent_blocks=False,
        # Preprocessor
        preprocessor_prefix="#",
        has_preprocessor_macros=True,
        # Statement / block close
        statement_terminator=";",
        block_close_suffix="};",
        summary_comment_prefix="//",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s*\((.{1,80})\)\s*\{?\s*$")),
            ("while", re.compile(r"^\s*while\s*\((.{1,80})\)\s*\{?\s*$")),
            ("if", re.compile(r"^\s*(?:else\s+)?if\s*\((.{1,80})\)\s*\{?\s*$")),
            ("switch", re.compile(r"^\s*switch\s*\((.{1,40})\)\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60});"),
        # Extra syntax hints
        type_indicator_chars="",
        define_line_re=re.compile(r"#\s*define\s+(\w+)(\([^)]*\))?\s*(.*)"),
        has_template_strings=False,
        raw_string_style="cpp",
        # Function signature end — matches ) : SEMANTIC_NAME (HLSL semantic annotations)
        func_sig_end_re=re.compile(r"\)\s*(?::\s*\w+\s*)?$"),
    )
