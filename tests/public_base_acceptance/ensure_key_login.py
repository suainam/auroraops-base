#!/usr/bin/env python3
"""Ensure password bootstrap is upgraded to SSH key login for acceptance hosts."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

import yaml


def load_host_vars(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    data["_path"] = str(path)
    return data


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True)


def ensure_key_login(host_vars: dict) -> int:
    host = str(host_vars["ansible_host"])
    user = str(host_vars["ansible_user"])
    port = str(host_vars.get("ansible_port", 22))
    key_path = Path(str(host_vars["ansible_ssh_private_key_file"])).expanduser()
    pub_key_path = key_path.with_suffix(key_path.suffix + ".pub") if key_path.suffix else Path(str(key_path) + ".pub")
    bootstrap_password = str(host_vars.get("bootstrap_ssh_password", ""))

    if not key_path.exists():
        raise FileNotFoundError(f"private key not found: {key_path}")
    if not pub_key_path.exists():
        raise FileNotFoundError(f"public key not found: {pub_key_path}")

    base_ssh = [
        "ssh",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        "-o",
        "BatchMode=yes",
        "-i",
        str(key_path),
        "-p",
        port,
        f"{user}@{host}",
        "true",
    ]
    key_check = run(base_ssh)
    if key_check.returncode == 0:
        print(f"key login already works for {user}@{host}:{port}")
        return 0

    if not bootstrap_password:
        raise RuntimeError(f"key login failed for {user}@{host}:{port}, and bootstrap_ssh_password is empty")

    copy_cmd = [
        "sshpass",
        "-p",
        bootstrap_password,
        "ssh-copy-id",
        "-i",
        str(pub_key_path),
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        "-p",
        port,
        f"{user}@{host}",
    ]
    copy_result = subprocess.run(copy_cmd, text=True)
    if copy_result.returncode != 0:
        raise RuntimeError(f"ssh-copy-id failed for {user}@{host}:{port}")

    recheck = run(base_ssh)
    if recheck.returncode != 0:
        raise RuntimeError(f"key login still failed for {user}@{host}:{port}: {recheck.stderr.strip()}")

    print(f"key login configured for {user}@{host}:{port}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-vars", required=True, help="Path to rendered or source host_vars file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    host_vars = load_host_vars(Path(args.host_vars).expanduser().resolve())
    return ensure_key_login(host_vars)


if __name__ == "__main__":
    raise SystemExit(main())
