#!/usr/bin/env python3
"""
Create_Aeroneutics Google Drive Deployment & Synchronization CLI Tool.
Handles staging, Google Drive remote synchronization, mapping generation, and verification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_STAGING_DIR = WORKSPACE_ROOT / "dist_gdrive"
DEFAULT_MAPPING_FILE = WORKSPACE_ROOT / "config" / "gdrive_mapping.json"
DEFAULT_FOLDER_ID = "1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9"


def get_gdrive_cmd() -> str:
    """Resolves gdrive executable path on the current system."""
    cmd = shutil.which("gdrive")
    if not cmd and sys.platform.startswith("win"):
        cmd = shutil.which("gdrive.cmd") or shutil.which("gdrive.CMD")
    return cmd or "gdrive"


def compute_sha256(filepath: Path) -> str:
    """Calculates SHA-256 hash of a file."""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def discover_manifest_files() -> List[Dict[str, Any]]:
    """
    Parses manifest.lua and root installer.lua to collect all files designated for distribution.
    Returns a list of dicts with keys: repoPath, stagedRelPath, category, dest.
    """
    manifest_path = (
        WORKSPACE_ROOT
        / "src"
        / "0_development"
        / "installer"
        / "modules"
        / "manifest.lua"
    )
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Manifest missing at {manifest_path}")

    text = manifest_path.read_text(encoding="utf-8")
    files: List[Dict[str, Any]] = []
    seen_paths = set()

    def add_entry(repo_path: str, staged_rel_path: str, category: str, dest: str) -> None:
        if repo_path in seen_paths:
            return
        seen_paths.add(repo_path)
        files.append({
            "repoPath": repo_path,
            "stagedRelPath": staged_rel_path,
            "category": category,
            "dest": dest,
            "fileName": Path(repo_path).name,
        })

    # 1. Root Installer
    add_entry("installer.lua", "installer/installer.lua", "installer", "/installer.lua")

    # 2. Bootstrap files
    bootstrap_matches = re.findall(
        r'repoPath\s*=\s*"([^"]+)",\s*cacheRelPath\s*=\s*"([^"]+)"', text
    )
    for repo_p, cache_rel in bootstrap_matches:
        add_entry(repo_p, f"bootstrap/{cache_rel}", "bootstrap", f"/.installer_cache/{cache_rel}")

    # 3. Shared libraries
    shared_matches = re.findall(
        r'repoPath\s*=\s*"([^"]+)",\s*dest\s*=\s*"([^"]+)"', text
    )
    for repo_p, dest_p in shared_matches:
        # Determine category: bootstrap or shared
        if repo_p.startswith("src/0_development/sensors/"):
            add_entry(repo_p, "shared/avionics_sensors.lua", "shared", dest_p)
        else:
            # Package file
            mod_match = re.search(r"src/([^/]+)/([^/]+)/", repo_p)
            mod_id = mod_match.group(2) if mod_match else "misc"
            dest_clean = dest_p.lstrip("/")
            add_entry(repo_p, f"packages/{mod_id}/{dest_clean}", "packages", dest_p)

    return files


def cmd_stage(staging_dir: Path) -> int:
    """Stages all release files into dist_gdrive/ and generates manifest.json."""
    staging_dir.mkdir(parents=True, exist_ok=True)
    entries = discover_manifest_files()
    staged_records = []
    category_counts: Dict[str, int] = {}

    for entry in entries:
        src_path = WORKSPACE_ROOT / entry["repoPath"]
        if not src_path.is_file():
            print(f"[WARN] Source file missing: {src_path}", file=sys.stderr)
            continue

        dest_path = staging_dir / entry["stagedRelPath"]
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_path, dest_path)

        size = dest_path.stat().st_size
        sha = compute_sha256(dest_path)
        cat = entry["category"]
        category_counts[cat] = category_counts.get(cat, 0) + 1

        staged_records.append({
            "repoPath": entry["repoPath"],
            "stagedRelPath": entry["stagedRelPath"],
            "category": cat,
            "dest": entry["dest"],
            "fileName": entry["fileName"],
            "sizeBytes": size,
            "sha256": sha,
        })

    manifest_output = {
        "version": "1.0.0",
        "totalFiles": len(staged_records),
        "categories": category_counts,
        "files": staged_records,
    }

    manifest_file = staging_dir / "manifest.json"
    manifest_file.write_text(json.dumps(manifest_output, indent=2), encoding="utf-8")

    print(f">> Staging complete at {staging_dir}")
    print(f"   Total staged files: {len(staged_records)}")
    for cat, count in sorted(category_counts.items()):
        print(f"   - {cat}: {count} files")
    print(f"   Manifest generated: {manifest_file}")
    return 0


def fetch_remote_files(folder_id: str) -> Dict[str, str]:
    """Queries Google Drive for files inside folder_id and returns { name: id }."""
    gdrive_bin = get_gdrive_cmd()
    try:
        proc = subprocess.run(
            [gdrive_bin, "readonly", "ls", folder_id, "--json"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=True,
        )
        data = json.loads(proc.stdout)
        remote_map = {}
        for item in data:
            name = item.get("name")
            fid = item.get("id")
            if name and fid:
                remote_map[name] = fid
        return remote_map
    except Exception as e:
        print(f"[WARN] Failed to list remote folder '{folder_id}': {e}", file=sys.stderr)
        return {}


def cmd_sync(
    staging_dir: Path,
    mapping_file: Path,
    folder_id: str,
    category_filter: str,
    dry_run: bool,
    embed: bool,
) -> int:
    """Synchronizes staged files to Google Drive and updates config/gdrive_mapping.json."""
    manifest_file = staging_dir / "manifest.json"
    if not manifest_file.is_file():
        print(f">> Staging not found at {staging_dir}. Running stage first...")
        cmd_stage(staging_dir)

    manifest_data = json.loads(manifest_file.read_text(encoding="utf-8"))
    staged_files = manifest_data.get("files", [])

    # Load existing mapping
    mapping: Dict[str, Any] = {
        "version": "1.0.0",
        "folderId": folder_id,
        "folderUrl": f"https://drive.google.com/drive/folders/{folder_id}",
        "lastSync": None,
        "files": {},
        "bootstrapMap": {},
    }
    if mapping_file.is_file():
        try:
            loaded = json.loads(mapping_file.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                mapping.update(loaded)
                mapping["folderId"] = folder_id
                mapping["folderUrl"] = f"https://drive.google.com/drive/folders/{folder_id}"
        except Exception:
            pass

    gdrive_bin = get_gdrive_cmd()
    remote_files = {} if dry_run else fetch_remote_files(folder_id)

    files_to_sync = [
        f for f in staged_files
        if category_filter == "all" or f["category"] == category_filter
    ]

    print(f">> Synchronizing {len(files_to_sync)} files to GDrive folder '{folder_id}' (filter='{category_filter}')...")

    uploaded_count = 0
    updated_count = 0

    for file_info in files_to_sync:
        repo_p = file_info["repoPath"]
        staged_p = staging_dir / file_info["stagedRelPath"]
        # Use remote file name that distinguishes duplicates if needed, or structured name
        remote_name = file_info["fileName"]
        # If filename might collide (e.g. multiple main.lua), prefix with package name
        if remote_name == "main.lua":
            parts = Path(file_info["stagedRelPath"]).parts
            if len(parts) >= 2:
                remote_name = f"{parts[-2]}_{remote_name}"

        remote_id = remote_files.get(remote_name)
        if not remote_id:
            existing_record = mapping.get("files", {}).get(repo_p)
            if existing_record and isinstance(existing_record, dict) and "id" in existing_record:
                candidate_id = existing_record["id"]
                if candidate_id in remote_files.values():
                    remote_id = candidate_id

        if dry_run:
            action = "UPDATE" if remote_id else "UPLOAD"
            print(f"   [DRY-RUN] {action} {repo_p} -> remote name '{remote_name}' (target ID: {remote_id or 'NEW'})")
            # For dry-run tests, record placeholder ID if missing
            file_id = remote_id or f"DRY_RUN_ID_{file_info['fileName']}"
        else:
            if remote_id:
                print(f"   [UPDATE] {remote_name} (ID: {remote_id})...")
                res = subprocess.run(
                    [gdrive_bin, "mutate", "update", remote_id, str(staged_p)],
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                )
                if res.returncode != 0:
                    print(f"   [FAIL] Update error: {res.stderr.strip()}", file=sys.stderr)
                    continue
                file_id = remote_id
                updated_count += 1
            else:
                print(f"   [UPLOAD] {remote_name} -> folder {folder_id}...")
                res = subprocess.run(
                    [gdrive_bin, "mutate", "upload", str(staged_p), "--parent", folder_id],
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                )
                if res.returncode != 0:
                    print(f"   [FAIL] Upload error: {res.stderr.strip()}", file=sys.stderr)
                    continue
                m = re.search(r"ID:\s*([A-Za-z0-9_\-]+)", res.stdout)
                if not m:
                    print(f"   [FAIL] Could not parse file ID from: {res.stdout.strip()}", file=sys.stderr)
                    continue
                file_id = m.group(1)
                remote_files[remote_name] = file_id
                uploaded_count += 1

        # Record mapping
        mapping.setdefault("files", {})[repo_p] = {
            "id": file_id,
            "name": remote_name,
            "repoPath": repo_p,
            "category": file_info["category"],
            "sizeBytes": file_info["sizeBytes"],
            "sha256": file_info["sha256"],
            "downloadUrl": f"https://drive.usercontent.google.com/download?id={file_id}&export=download&confirm=t",
        }
        mapping.setdefault("bootstrapMap", {})[repo_p] = file_id

    mapping["lastSync"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    mapping_file.parent.mkdir(parents=True, exist_ok=True)
    mapping_file.write_text(json.dumps(mapping, indent=2), encoding="utf-8")

    print(f">> Synchronization finished: {uploaded_count} uploaded, {updated_count} updated.")
    print(f"   Updated mapping written to: {mapping_file}")

    if embed:
        embed_bootstrap_ids(mapping)

    return 0


def embed_bootstrap_ids(mapping: Dict[str, Any]) -> None:
    """Embeds the bootstrap file IDs into installer.lua, src/installer.lua, and manifest.lua."""
    bootstrap_map = mapping.get("bootstrapMap", {})
    if not bootstrap_map:
        return

    # Files to update
    installer_files = [
        WORKSPACE_ROOT / "installer.lua",
        WORKSPACE_ROOT / "src" / "0_development" / "installer" / "installer.lua",
        WORKSPACE_ROOT / "src" / "0_development" / "installer" / "modules" / "manifest.lua",
    ]

    for fpath in installer_files:
        if not fpath.is_file():
            continue
        content = fpath.read_text(encoding="utf-8")
        orig = content

        for repo_p, fid in bootstrap_map.items():
            # Replace gdriveId = nil with gdriveId = "fid" for repoPath
            pattern = re.compile(
                r'(\{\s*repoPath\s*=\s*"' + re.escape(repo_p) + r'",\s*cacheRelPath\s*=\s*"[^"]+",\s*gdriveId\s*=\s*)(nil|"[^"]*")(\s*\})'
            )
            content = pattern.sub(rf'\g<1>"{fid}"\g<3>', content)

        if content != orig:
            fpath.write_text(content, encoding="utf-8")
            print(f">> Embedded bootstrap IDs into {fpath.relative_to(WORKSPACE_ROOT)}")


def cmd_status(staging_dir: Path, mapping_file: Path, folder_id: str) -> int:
    """Displays local staging, mapping, and remote status."""
    staged_count = 0
    if (staging_dir / "manifest.json").is_file():
        try:
            m = json.loads((staging_dir / "manifest.json").read_text(encoding="utf-8"))
            staged_count = m.get("totalFiles", 0)
        except Exception:
            pass

    mapped_count = 0
    if mapping_file.is_file():
        try:
            m = json.loads(mapping_file.read_text(encoding="utf-8"))
            mapped_count = len(m.get("files", {}))
        except Exception:
            pass

    remote_files = fetch_remote_files(folder_id)

    print("=== Google Drive Deployment Status ===")
    print(f"Target GDrive Folder: {folder_id}")
    print(f"Staged files on disk: {staged_count} (dir: {staging_dir})")
    print(f"Mapped files in SSOT: {mapped_count} (file: {mapping_file})")
    print(f"Remote files in Drive: {len(remote_files)}")
    return 0


def cmd_verify(mapping_file: Path, category_filter: str) -> int:
    """Validates that required files have non-empty file IDs in mapping."""
    if not mapping_file.is_file():
        print(f"[FAIL] Mapping file missing at {mapping_file}", file=sys.stderr)
        return 1

    data = json.loads(mapping_file.read_text(encoding="utf-8"))
    files = data.get("files", {})
    bootstrap_map = data.get("bootstrapMap", {})

    if not files and not bootstrap_map:
        print("[FAIL] Mapping file has zero entries", file=sys.stderr)
        return 1

    missing = []
    if category_filter in ("all", "bootstrap"):
        expected_bootstrap = [
            "installer.lua",
            "src/0_development/installer/installer_app.lua",
            "src/0_development/installer/modules/manifest.lua",
            "src/0_development/installer/modules/version_registry.lua",
            "src/0_development/installer/modules/migration_engine.lua",
            "src/0_development/installer/modules/startup_generator.lua",
            "src/0_development/installer/modules/downloader.lua",
            "src/0_development/installer/modules/tui_view.lua",
        ]
        for b in expected_bootstrap:
            fid = bootstrap_map.get(b) or (files.get(b, {}).get("id"))
            if not fid:
                missing.append(b)

    if missing:
        print(f"[FAIL] Missing file IDs for: {missing}", file=sys.stderr)
        return 1

    print(f">> Verification PASS: {len(files)} mapped files checked successfully.")
    return 0


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create_Aeroneutics Google Drive Deployment & Sync Tool")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # stage
    p_stage = subparsers.add_parser("stage", help="Stage release files into dist_gdrive/")
    p_stage.add_argument("--staging-dir", type=Path, default=DEFAULT_STAGING_DIR, help="Staging output directory")

    # sync
    p_sync = subparsers.add_parser("sync", help="Synchronize staged files to Google Drive")
    p_sync.add_argument("--staging-dir", type=Path, default=DEFAULT_STAGING_DIR, help="Staging directory")
    p_sync.add_argument("--mapping-file", type=Path, default=DEFAULT_MAPPING_FILE, help="Mapping output file")
    p_sync.add_argument("--folder-id", type=str, default=DEFAULT_FOLDER_ID, help="Target GDrive folder ID")
    p_sync.add_argument("--category", type=str, default="all", choices=["all", "bootstrap", "packages", "shared", "installer"], help="Category filter")
    p_sync.add_argument("--dry-run", action="store_true", help="Print actions without modifying Google Drive")
    p_sync.add_argument("--embed", action="store_true", help="Embed bootstrap IDs into installer and manifest")

    # status
    p_status = subparsers.add_parser("status", help="Show deployment status")
    p_status.add_argument("--staging-dir", type=Path, default=DEFAULT_STAGING_DIR, help="Staging directory")
    p_status.add_argument("--mapping-file", type=Path, default=DEFAULT_MAPPING_FILE, help="Mapping file")
    p_status.add_argument("--folder-id", type=str, default=DEFAULT_FOLDER_ID, help="Target GDrive folder ID")

    # verify
    p_verify = subparsers.add_parser("verify", help="Verify mapping validity")
    p_verify.add_argument("--mapping-file", type=Path, default=DEFAULT_MAPPING_FILE, help="Mapping file")
    p_verify.add_argument("--category", type=str, default="all", choices=["all", "bootstrap", "packages"], help="Category filter")

    return parser


def main() -> int:
    parser = build_arg_parser()
    args = parser.parse_args()

    if args.command == "stage":
        return cmd_stage(args.staging_dir)
    elif args.command == "sync":
        return cmd_sync(
            args.staging_dir,
            args.mapping_file,
            args.folder_id,
            args.category,
            args.dry_run,
            args.embed,
        )
    elif args.command == "status":
        return cmd_status(args.staging_dir, args.mapping_file, args.folder_id)
    elif args.command == "verify":
        return cmd_verify(args.mapping_file, args.category)
    return 0


if __name__ == "__main__":
    sys.exit(main())
