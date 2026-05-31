"""Provider registry and exports."""

from .base import AbstractBlockProvider, IncludeDirective
from .cc_provider import CCProvider
from .unreal_provider import UnrealProvider

__all__ = [
    "AbstractBlockProvider",
    "CCProvider",
    "IncludeDirective",
    "UnrealProvider",
    "get_provider",
    "list_providers",
    "register_provider",
]

_REGISTRY: dict[str, type[AbstractBlockProvider]] = {}


def register_provider(name: str, cls: type[AbstractBlockProvider]) -> None:
    """Register a provider class under a short name."""
    _REGISTRY[name] = cls


def get_provider(name: str) -> AbstractBlockProvider:
    """Instantiate and return a provider by name."""
    cls = _REGISTRY.get(name)
    if cls is None:
        raise KeyError(f"Unknown provider '{name}'. Available: {sorted(_REGISTRY)}")
    return cls()


def list_providers() -> dict[str, type[AbstractBlockProvider]]:
    """Return a copy of the provider registry."""
    return dict(_REGISTRY)


# Auto-register built-in providers
register_provider("cc", CCProvider)
register_provider("unreal", UnrealProvider)
