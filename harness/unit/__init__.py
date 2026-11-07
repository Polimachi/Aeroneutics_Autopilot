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
from .static_guard import (
    Lua52SyntaxChecker,
    StaticViolation,
    scan_lua_source,
    scan_target_files,
    strip_lua_comments_and_strings,
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
    "Lua52SyntaxChecker",
    "StaticViolation",
    "scan_lua_source",
    "scan_target_files",
    "strip_lua_comments_and_strings",
]
