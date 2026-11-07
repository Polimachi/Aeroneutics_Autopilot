"""
Unit testing framework for Create_Aeroneutics.
"""
from .config import (
    CraftOSPaths,
    PeripheralAttachment,
    UnitTargetConfig,
    discover_codebase_targets,
    resolve_craftos_paths,
)
from .session import (
    CraftOSSessionResult,
    EphemeralCraftOSSession,
    clean_workspace_orphans,
)

__all__ = [
    "CraftOSPaths",
    "PeripheralAttachment",
    "UnitTargetConfig",
    "discover_codebase_targets",
    "resolve_craftos_paths",
    "CraftOSSessionResult",
    "EphemeralCraftOSSession",
    "clean_workspace_orphans",
]
