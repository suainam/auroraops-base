from __future__ import annotations

import re
from pathlib import Path

from jinja2 import Environment
from jinja2.nativetypes import NativeEnvironment

TASKS = Path(__file__).resolve().parents[1] / "collections/ansible_collections/vps/common/tasks"
TASK = TASKS / "manage_optional_logrotate.yml"
VERIFY_TASK = TASKS / "verify_optional_logrotate.yml"

# The managed namespace every destructive path must live under.
MANAGED_PREFIX = "/etc/logrotate.d/auroraops-"


def ansible_environment() -> Environment:
    """Jinja2 environment with Ansible's `match` test (re.match semantics).

    NativeEnvironment is required so expressions evaluate to real Python types.
    A plain Environment renders booleans as the *strings* "True"/"False", which
    would make `bool("False")` truthy and silently pass every guard.
    """
    env = NativeEnvironment()
    env.tests["match"] = lambda value, pattern: bool(re.match(pattern, str(value)))
    return env


def render(expression: str, **context: object) -> bool:
    """Evaluate a Jinja guard expression the way Ansible's `assert` would."""
    template = ansible_environment().from_string(f"{{{{ {expression} }}}}")
    return bool(template.render(**context))


def managed_prefix_pattern() -> str:
    """Extract the managed-namespace regex straight from the task file.

    Reading the real pattern (instead of copying it) means the test cannot pass
    while the shipped guard is wrong. Both the config-path guard and the
    legacy-path guard must use the same namespace.
    """
    text = TASK.read_text(encoding="utf-8")
    config_path = re.search(r"optional_logrotate_config_path is match\('([^']+)'\)", text)
    legacy = re.search(r"select\('match', '([^']+)'\)", text)
    assert config_path, "manage_optional_logrotate.yml must guard the config path with match()"
    assert legacy, "manage_optional_logrotate.yml must guard legacy paths with match()"
    assert config_path.group(1) == legacy.group(1), (
        "config path and legacy path guards must confine to the same namespace"
    )
    return config_path.group(1)


def legacy_guard_expression() -> str:
    """The legacy-path guard, with the pattern bound from the real task file."""
    return (
        "(optional_logrotate_legacy_paths | default([]))"
        " | select('match', pattern) | list | length"
        " == (optional_logrotate_legacy_paths | default([])) | length"
    )


def config_path_guard(path: str) -> bool:
    """Evaluate the task file's own config-path guard against a candidate path."""
    return render(
        "optional_logrotate_config_path is match(pattern)",
        optional_logrotate_config_path=path,
        pattern=managed_prefix_pattern(),
    )


def test_optional_logrotate_confines_deletion_to_managed_prefix() -> None:
    text = TASK.read_text(encoding="utf-8")

    # Deletion exists, but only behind an assertion that confines the path.
    assert "state: absent" in text
    assert "ansible.builtin.copy:" in text
    assert "logrotate" in text and "--debug" in text
    # No raw shell deletion.
    assert "command: rm" not in text and "shell: rm" not in text


def test_optional_logrotate_config_path_guard_accepts_only_managed_paths() -> None:
    """Executable proof of the deletion-safety guard, not a string match."""
    # Managed paths are accepted.
    assert config_path_guard(f"{MANAGED_PREFIX}singbox") is True
    assert config_path_guard(f"{MANAGED_PREFIX}sub-store") is True

    # System-critical and hand-maintained paths are rejected.
    assert config_path_guard("/etc/logrotate.conf") is False
    assert config_path_guard("/etc/logrotate.d") is False
    assert config_path_guard("/etc/logrotate.d/hand-written") is False
    assert config_path_guard("/etc/cron.d/auroraops-evil") is False
    assert config_path_guard("/var/log/auroraops-anything") is False
    assert config_path_guard("relative/path") is False


def test_optional_logrotate_legacy_path_guard_rejects_unmanaged_paths() -> None:
    """A caller cannot smuggle an unmanaged legacy path into the delete loop."""
    expression = legacy_guard_expression()
    pattern = managed_prefix_pattern()

    managed = [f"{MANAGED_PREFIX}legacy-one", f"{MANAGED_PREFIX}legacy-two"]
    assert render(expression, pattern=pattern, optional_logrotate_legacy_paths=managed) is True

    for smuggled in (
        ["/etc/logrotate.conf"],
        ["/etc/logrotate.d"],
        [f"{MANAGED_PREFIX}ok", "/etc/logrotate.conf"],
    ):
        assert (
            render(expression, pattern=pattern, optional_logrotate_legacy_paths=smuggled)
            is False
        ), f"guard must reject smuggled path(s) {smuggled}"

    assert render(expression, pattern=pattern, optional_logrotate_legacy_paths=[]) is True


def test_optional_logrotate_verify_is_read_only_and_fail_closed() -> None:
    text = VERIFY_TASK.read_text(encoding="utf-8")

    assert "ansible.builtin.stat:" in text
    assert "optional_logrotate_verify_stat.stat.exists" in text
    assert "optional_logrotate_verify_stat.stat.size | default(0) > 0" in text
    assert "state: absent" not in text
    assert "command: rm" not in text and "shell: rm" not in text
