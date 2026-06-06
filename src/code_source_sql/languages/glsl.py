"""GLSL (OpenGL Shading Language) configuration.

Supports struct, uniform blocks, buffer blocks (SSBO), layout() qualifiers,
and standard C-like function syntax. No classes, namespaces, templates, or
semantic annotations.
"""

from __future__ import annotations

import re

from ..configs import LanguageConfig

_NEVER_MATCH = re.compile(r"(?!x)x")


def make_glsl_language() -> LanguageConfig:
    """GLSL language configuration — C-like shader language for OpenGL/Vulkan."""
    return LanguageConfig(
        name="glsl",
        # Only struct — no class or interface in GLSL
        class_re=re.compile(
            r"(?:^|\s)(struct)\s+"
            r"(\w+)"
            r"\s*",
        ),
        # No enums in GLSL
        enum_re=_NEVER_MATCH,
        # No namespaces in GLSL
        namespace_re=_NEVER_MATCH,
        func_name_re=re.compile(r"(\w+)\s*\([^)]*\)\s*$"),
        # No export macros
        export_macro_re=_NEVER_MATCH,
        # No calling conventions
        calling_conv_re=_NEVER_MATCH,
        # Strip layout(...) qualifiers before classification
        attribute_re=re.compile(
            r"\blayout\s*\([^)]*\)\s*"
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
        # Includes precision qualifiers
        trailing_mods_re=re.compile(
            r"\s*(?:const|highp|mediump|lowp)\s*[;{]*\s*$"
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
        uses_colon_inheritance=False,
        # Edge extraction
        scope_operator="::",
        base_keyword="",
        static_call_re=None,
        super_call_re=None,
        # PascalCase user-defined struct types
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(
            r"(?:const\s+)?([A-Z][A-Za-z0-9_]+)\s+\w+"
        ),
        basic_skip_types=frozenset({
            # Scalar types
            "float", "double", "int", "uint", "bool", "void",
            # Vector types
            "vec2", "vec3", "vec4",
            "ivec2", "ivec3", "ivec4",
            "uvec2", "uvec3", "uvec4",
            "bvec2", "bvec3", "bvec4",
            "dvec2", "dvec3", "dvec4",
            # Matrix types
            "mat2", "mat3", "mat4",
            "mat2x2", "mat2x3", "mat2x4",
            "mat3x2", "mat3x3", "mat3x4",
            "mat4x2", "mat4x3", "mat4x4",
            "dmat2", "dmat3", "dmat4",
            # Sampler types
            "sampler2D", "sampler3D", "samplerCube",
            "sampler2DShadow", "samplerCubeShadow",
            "sampler2DArray", "sampler2DArrayShadow",
            "sampler1D", "sampler1DShadow",
            "samplerBuffer", "sampler2DRect",
            "sampler2DMS", "sampler2DMSArray",
            "isampler2D", "isampler3D", "isamplerCube",
            "usampler2D", "usampler3D", "usamplerCube",
            # Image types
            "image2D", "image3D", "imageCube", "imageBuffer",
            "iimage2D", "uimage2D",
            # Atomic types
            "atomic_uint",
            # Storage/precision qualifiers (noise when used as type-like tokens)
            "in", "out", "inout", "uniform", "const",
            "attribute", "varying",
            "highp", "mediump", "lowp",
            "readonly", "writeonly", "coherent",
        }),
        # Block classification helpers
        block_keyword_re=re.compile(
            r"\b(?:struct|uniform|buffer)\b"
        ),
        # No lambdas
        lambda_re=None,
        # uniform/buffer blocks recognized as namespace-like blocks
        # attribute_re already stripped layout(...), leaving clean "uniform Name"
        namespace_sig_re=re.compile(
            r"(?:uniform|buffer)\s+(\w+)\s*$"
        ),
        init_list_re=None,
        # View / summary helpers
        access_spec_names=frozenset(),
        view_structural_kws=("struct ", "uniform ", "buffer "),
        view_modifier_kws=("const ", "static "),
        local_var_modifiers="const|uniform|volatile|highp|mediump|lowp|readonly|writeonly|coherent",
        # Bracket scanner hints
        verbatim_string_prefix=None,
        raw_string_char=None,
        # No range-based for in GLSL
        range_for_re=None,
        # Comment syntax (same as C)
        line_comment="//",
        block_comment_pair=("/*", "*/"),
        # String syntax — only double-quoted strings in GLSL
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
        # No semantic annotations in GLSL — standard C function signature end
        func_sig_end_re=re.compile(r"\)\s*$"),
    )
