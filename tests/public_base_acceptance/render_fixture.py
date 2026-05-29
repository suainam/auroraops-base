#!/usr/bin/env python3
"""Render private acceptance fixtures for auroraops-base validation."""

from __future__ import annotations

import argparse
from pathlib import Path
from string import Template
import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
TEMPLATE_ROOT = REPO_ROOT / "tests" / "fixtures" / "public_base_acceptance"


DEFAULTS = {
    "host_alias": "vps",
    "ansible_host": "203.0.113.10",
    "ansible_user": "root",
    "ansible_port": "22",
    "ssh_port": "22",
    "sudo_password": "CHANGEME_PASSWORD",
    "bootstrap_ssh_password": "CHANGEME_PASSWORD",
    "private_key_file": "~/.ssh/id_rsa",
    "base_admin_user": "admin",
    "proxy_enabled": "false",
    "proxy_http": "",
    "proxy_https": "",
    "ansible_python_interpreter": "/usr/bin/python3",
}


def load_host_vars_context(host_vars_path: Path, host_alias_override: str | None = None) -> dict[str, str]:
    raw = yaml.safe_load(host_vars_path.read_text(encoding="utf-8")) or {}
    host_alias = host_alias_override or raw.get("hostname") or host_vars_path.stem

    context = {
        "host_alias": str(host_alias),
        "ansible_host": str(raw.get("ansible_host", DEFAULTS["ansible_host"])),
        "ansible_user": str(raw.get("ansible_user", DEFAULTS["ansible_user"])),
        "ansible_port": str(raw.get("ansible_port", DEFAULTS["ansible_port"])),
        "ssh_port": str(raw.get("ssh_port", raw.get("ansible_port", DEFAULTS["ssh_port"]))),
        "sudo_password": str(raw.get("ansible_become_password", DEFAULTS["sudo_password"])),
        "bootstrap_ssh_password": str(raw.get("bootstrap_ssh_password", raw.get("ansible_become_password", DEFAULTS["bootstrap_ssh_password"]))),
        "private_key_file": str(raw.get("ansible_ssh_private_key_file", raw.get("ansible_private_key_file", DEFAULTS["private_key_file"]))),
        "base_admin_user": str(raw.get("admin_user", DEFAULTS["base_admin_user"])),
        "proxy_enabled": str(raw.get("proxy_enabled", DEFAULTS["proxy_enabled"])).lower(),
        "proxy_http": str(raw.get("proxy_http", DEFAULTS["proxy_http"])),
        "proxy_https": str(raw.get("proxy_https", DEFAULTS["proxy_https"])),
        "ansible_python_interpreter": str(raw.get("ansible_python_interpreter", DEFAULTS["ansible_python_interpreter"])),
    }
    return context


def render_text(template_path: Path, context: dict[str, str]) -> str:
    return Template(template_path.read_text(encoding="utf-8")).substitute(context)


def render_tree(destination: Path, context: dict[str, str]) -> None:
    destination.mkdir(parents=True, exist_ok=True)

    managed_targets: list[Path] = []
    for template_path in TEMPLATE_ROOT.rglob("*"):
        if not template_path.is_file():
            continue
        rel = template_path.relative_to(TEMPLATE_ROOT)
        if rel.parts[:1] == ("host_vars",) and rel.name == "host.yml.j2":
            target = destination / "inventories" / "host_vars" / f"{context['host_alias']}.yml"
        else:
            target = destination / rel.with_suffix("") if rel.suffix == ".j2" else destination / rel
        managed_targets.append(target)

    for target in managed_targets:
        if target.exists():
            target.unlink()

    for template_path in TEMPLATE_ROOT.rglob("*"):
        if not template_path.is_file():
            continue
        rel = template_path.relative_to(TEMPLATE_ROOT)
        if rel.parts[:1] == ("host_vars",) and rel.name == "host.yml.j2":
            target = destination / "inventories" / "host_vars" / f"{context['host_alias']}.yml"
        else:
            target = destination / rel.with_suffix("") if rel.suffix == ".j2" else destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render_text(template_path, context), encoding="utf-8")


def build_context(args: argparse.Namespace) -> dict[str, str]:
    context = dict(DEFAULTS)
    if args.source_host_vars is not None:
        context.update(load_host_vars_context(Path(args.source_host_vars).expanduser().resolve(), args.host_alias))
    for key, value in vars(args).items():
        if value is None:
            continue
        if key == "source_host_vars":
            continue
        context[key] = str(value)

    context["proxy_enabled"] = "true" if str(context["proxy_enabled"]).lower() in {"1", "true", "yes"} else "false"
    return context


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, help="Output directory for rendered fixtures")
    parser.add_argument("--source-host-vars")
    parser.add_argument("--host-alias")
    parser.add_argument("--ansible-host")
    parser.add_argument("--ansible-user")
    parser.add_argument("--ansible-port")
    parser.add_argument("--ssh-port")
    parser.add_argument("--private-key-file")
    parser.add_argument("--sudo-password")
    parser.add_argument("--bootstrap-ssh-password")
    parser.add_argument("--base-admin-user")
    parser.add_argument("--proxy-enabled")
    parser.add_argument("--proxy-http")
    parser.add_argument("--proxy-https")
    parser.add_argument("--ansible-python-interpreter")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = Path(args.output).expanduser().resolve()
    context = build_context(args)
    render_tree(output, context)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
