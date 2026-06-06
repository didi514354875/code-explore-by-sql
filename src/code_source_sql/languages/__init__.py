"""Language factory registry — imports all language factories and registers them."""

from __future__ import annotations

from ..configs import register_language
from .c import make_c_language
from .cpp import make_cpp_language
from .csharp import make_csharp_language
from .glsl import make_glsl_language
from .go import make_go_language
from .hlsl import make_hlsl_language
from .java import make_java_language
from .javascript import make_javascript_language, make_typescript_language
from .kotlin import make_kotlin_language
from .python import make_python_language
from .rust import make_rust_language
from .swift import make_swift_language

register_language("cpp", make_cpp_language)
register_language("csharp", make_csharp_language)
register_language("c", make_c_language)
register_language("java", make_java_language)
register_language("glsl", make_glsl_language)
register_language("go", make_go_language)
register_language("hlsl", make_hlsl_language)
register_language("rust", make_rust_language)
register_language("javascript", make_javascript_language)
register_language("typescript", make_typescript_language)
register_language("kotlin", make_kotlin_language)
register_language("swift", make_swift_language)
register_language("python", make_python_language)
