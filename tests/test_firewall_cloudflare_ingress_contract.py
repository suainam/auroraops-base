from __future__ import annotations

import ipaddress
from pathlib import Path
import jinja2
import yaml
from ansible.plugins.filter.core import FilterModule as CoreFilterModule
from ansible.plugins.filter.mathstuff import FilterModule as MathFilterModule

REPO = Path(__file__).resolve().parents[1]
ROLE = REPO / "collections/ansible_collections/vps/system/roles/firewall"
DEFAULTS = ROLE / "defaults/main.yml"
RULES = ROLE / "tasks/rules.yml"
VERIFY = ROLE / "tasks/verify.yml"
MAIN = ROLE / "tasks/main.yml"
PREFLIGHT = ROLE / "tasks/preflight.yml"


def test_firewall_defaults_declare_cloudflare_ingress() -> None:
    data = yaml.safe_load(DEFAULTS.read_text(encoding="utf-8"))
    assert data["firewall_cloudflare_ingress_enabled"] is False
    assert data["firewall_cloudflare_tcp_ports"] == []
    assert isinstance(data["firewall_cloudflare_default_ips"], list)
    assert len(data["firewall_cloudflare_default_ips"]) >= 15

    for cidr in data["firewall_cloudflare_default_ips"]:
        net = ipaddress.ip_network(cidr)
        assert net.is_global


def test_firewall_rules_task_has_cloudflare_rule() -> None:
    tasks = yaml.safe_load(RULES.read_text(encoding="utf-8"))
    cf_task = next(
        (t for t in tasks if t.get("name") == "Allow Cloudflare ingress on configured ports"),
        None,
    )
    assert cf_task is not None
    ufw = cf_task["community.general.ufw"]
    assert ufw["rule"] == "allow"
    assert "src" in ufw
    assert "port" in ufw
    assert ufw["proto"] == "tcp"
    assert "firewall_cloudflare_ingress_enabled" in str(cf_task.get("when"))


def test_effective_tcp_ports_excludes_cloudflare_ports_when_enabled() -> None:
    env = jinja2.Environment()
    env.filters.update(CoreFilterModule().filters())
    env.filters.update(MathFilterModule().filters())

    expr = """
    {{
      ((((firewall_tcp_ports | default([])) | map('string')
         | difference((firewall_cloudflare_tcp_ports | default([]) | map('string')) if (firewall_cloudflare_ingress_enabled | default(false) | bool) else []))
        + [ssh_port | string])
      | unique
      | sort)
    }}
    """
    tmpl = env.from_string(expr.strip())

    # Case 1: Cloudflare ingress disabled -> ports 80, 443 remain in effective ports
    res_disabled = yaml.safe_load(tmpl.render(
        firewall_tcp_ports=[80, 443],
        ssh_port=6868,
        firewall_cloudflare_ingress_enabled=False,
        firewall_cloudflare_tcp_ports=[80, 443],
    ))
    assert res_disabled == ["443", "6868", "80"]

    # Case 2: Cloudflare ingress enabled -> ports 80, 443 are removed from world-open list
    res_enabled = yaml.safe_load(tmpl.render(
        firewall_tcp_ports=[80, 443],
        ssh_port=6868,
        firewall_cloudflare_ingress_enabled=True,
        firewall_cloudflare_tcp_ports=[80, 443],
    ))
    assert res_enabled == ["6868"]


def test_effective_tcp_ports_never_drops_ssh_port_even_if_misconfigured() -> None:
    """Anti-lockout invariant: ssh_port MUST NEVER be removed from effective ports."""
    env = jinja2.Environment()
    env.filters.update(CoreFilterModule().filters())
    env.filters.update(MathFilterModule().filters())

    expr = """
    {{
      ((((firewall_tcp_ports | default([])) | map('string')
         | difference((firewall_cloudflare_tcp_ports | default([]) | map('string')) if (firewall_cloudflare_ingress_enabled | default(false) | bool) else []))
        + [ssh_port | string])
      | unique
      | sort)
    }}
    """
    tmpl = env.from_string(expr.strip())

    # Even if an operator accidentally configures ssh_port (6868) in firewall_cloudflare_tcp_ports
    res = yaml.safe_load(tmpl.render(
        firewall_tcp_ports=[80, 443, 6868],
        ssh_port=6868,
        firewall_cloudflare_ingress_enabled=True,
        firewall_cloudflare_tcp_ports=[80, 443, 6868],
    ))
    assert "6868" in res, "ssh_port must NEVER be dropped from global effective ports!"


def test_preflight_has_anti_lockout_ssh_guard() -> None:
    tasks = yaml.safe_load(PREFLIGHT.read_text(encoding="utf-8"))
    guard_task = next(
        (t for t in tasks if t.get("name") == "Guard against locking host out of SSH via Cloudflare restriction"),
        None,
    )
    assert_block = guard_task.get("ansible.builtin.assert", {})
    assert "ssh_port" in str(assert_block.get("fail_msg"))
    assert "firewall_cloudflare_ingress_enabled" in str(guard_task.get("when"))
