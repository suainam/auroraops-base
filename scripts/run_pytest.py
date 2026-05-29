#!/usr/bin/env python3
"""
AuroraOps Pytest Runner
=======================
读取 Ansible 角色配置并执行测试

与 make deploy/verify/rollback 保持一致的接口

用法:
    python scripts/run_pytest.py --enabled-only
    python scripts/run_pytest.py --role system.base
    python scripts/run_pytest.py --all
    python scripts/run_pytest.py --html
"""

import sys
import subprocess
import argparse
import yaml
import json
import datetime
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
RESULTS_DIR = PROJECT_ROOT / "tests" / "results"


def load_yaml_file(filepath):
    """加载 YAML 文件"""
    try:
        with open(filepath, 'r') as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        print(f"Warning: Could not load {filepath}: {e}")
        return {}


def get_global_roles():
    """从 group_vars/all/roles.yml 获取全局角色配置"""
    roles_file = PROJECT_ROOT / "inventories" / "group_vars" / "all" / "roles.yml"
    data = load_yaml_file(roles_file)
    return data.get('auroraops_roles', {})


def get_host_roles(host):
    """从 host_vars/{host}.yml 获取主机特定的角色配置"""
    host_file = PROJECT_ROOT / "inventories" / "host_vars" / f"{host}.yml"
    data = load_yaml_file(host_file)
    return data.get('auroraops_roles', {})


def merge_roles(global_roles, host_roles):
    """合并全局角色和主机特定角色配置"""
    merged = {}
    
    # 从全局配置开始
    for domain, roles in global_roles.items():
        merged[domain] = dict(roles)
    
    # 用主机配置覆盖
    for domain, roles in host_roles.items():
        if domain in merged:
            merged[domain].update(roles)
        else:
            merged[domain] = dict(roles)
    
    return merged


def get_enabled_roles(host=None):
    """获取启用的角色列表"""
    global_roles = get_global_roles()
    host_roles = get_host_roles(host) if host else {}
    merged = merge_roles(global_roles, host_roles)
    
    enabled = []
    for domain, roles in merged.items():
        for role_name, enabled_flag in roles.items():
            if enabled_flag:
                enabled.append(f"{domain}.{role_name}")
    
    return sorted(enabled)


def get_all_roles():
    """获取所有角色列表（不管启用状态）"""
    global_roles = get_global_roles()
    
    all_roles = []
    for domain, roles in global_roles.items():
        for role_name in roles.keys():
            all_roles.append(f"{domain}.{role_name}")
    
    return sorted(all_roles)


def role_to_pytest_marker(role_name):
    """将 role.domain.role 转换为 pytest 标记格式"""
    # 保持原始格式 test_role_deploy[domain.role]
    return role_name


def run_pytest(pytest_args, verbose=True):
    """运行 pytest"""
    cmd = [sys.executable, "-m", "pytest"] + pytest_args
    
    if verbose:
        print(f"Running: {' '.join(cmd)}")
        print("=" * 70)
    
    return subprocess.run(cmd, cwd=PROJECT_ROOT)


def main():
    parser = argparse.ArgumentParser(
        description="Run pytest for AuroraOps roles",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/run_pytest.py --enabled-only    # 测试启用的角色
  python scripts/run_pytest.py --all             # 测试所有角色
  python scripts/run_pytest.py --role system.base # 测试特定角色
  python scripts/run_pytest.py --html            # 生成 HTML 报告
        """
    )
    
    parser.add_argument(
        "--enabled-only",
        action="store_true",
        help="只测试启用的角色"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="测试所有角色（忽略启用状态）"
    )
    parser.add_argument(
        "--role",
        help="测试特定角色 (e.g., system.base)"
    )
    parser.add_argument(
        "--roles",
        nargs="+",
        help="测试多个角色"
    )
    parser.add_argument(
        "--host",
        default="cc15",
        help="目标主机 (默认: cc15)"
    )
    parser.add_argument(
        "--html",
        action="store_true",
        help="生成 HTML 报告"
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=0,
        help="并行工作进程数 (0=自动)"
    )
    parser.add_argument(
        "--background",
        action="store_true",
        help="后台运行"
    )
    parser.add_argument(
        "--output",
        help="输出目录 (默认: 自动创建带时间戳的目录)"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="详细输出"
    )
    
    args, extra_args = parser.parse_known_args()
    
    # 构建 pytest 命令
    pytest_cmd = [
        "tests/integration/test_role_deploy.py",
        "-v",
        "-n", str(args.workers) if args.workers else "0"
    ]

    # 确定要测试的角色
    if args.enabled_only:
        roles = get_enabled_roles(args.host)
        if not roles:
            print("No enabled roles found!")
            return 1

        print(f"Testing {len(roles)} enabled roles on {args.host}:")
        for role in roles[:10]:  # 只显示前10个
            print(f"  - {role}")
        if len(roles) > 10:
            print(f"  ... and {len(roles) - 10} more")

        # 直接在脚本内部设置环境变量，避免 -k 过滤器过长
        import os
        os.environ['AURORAOPS_TEST_ROLES'] = ','.join(roles)
        os.environ['AURORAOPS_TEST_HOST'] = args.host
    
    elif args.role:
        print(f"Testing role: {args.role}")
        pytest_cmd.extend(["-k", role_to_pytest_marker(args.role)])
    
    elif args.roles:
        print(f"Testing roles: {', '.join(args.roles)}")
        markers = [role_to_pytest_marker(r) for r in args.roles]
        pytest_cmd.extend(["-k", " or ".join(markers)])
    
    elif args.all:
        roles = get_all_roles()
        print(f"Testing all {len(roles)} roles:")
        # 不添加 -k 过滤器，测试所有角色
    
    else:
        # 默认行为：测试启用的角色
        roles = get_enabled_roles(args.host)
        print(f"Testing {len(roles)} enabled roles on {args.host}")
        markers = [role_to_pytest_marker(r) for r in roles]
        pytest_cmd.extend(["-k", " or ".join(markers)])
    
    # 添加 HTML 报告选项
    if args.html:
        if args.output:
            report_path = Path(args.output) / "report.html"
        else:
            report_path = PROJECT_ROOT / "tests" / "reports" / "report.html"
        report_path.parent.mkdir(parents=True, exist_ok=True)
        pytest_cmd.extend([
            "--html", str(report_path),
            "--self-contained-html"
        ])
        print(f"\nHTML report will be saved to: {report_path}")
    
    # 添加额外的 pytest 参数
    pytest_cmd.extend(extra_args)
    
    # 后台运行
    if args.background:
        # 创建输出目录
        if args.output:
            output_dir = Path(args.output)
        else:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
            output_dir = RESULTS_DIR / "pytest" / timestamp
        output_dir.mkdir(parents=True, exist_ok=True)
        
        print(f"Running pytest in background")
        print(f"Output directory: {output_dir}")
        print(f"Check progress: make test-status")
        
        # 构建完整命令
        full_cmd = [sys.executable, "-m", "pytest"] + pytest_cmd
        
        # 重定向输出
        log_file = output_dir / "pytest.log"
        with open(log_file, "w") as f:
            result = subprocess.run(full_cmd, cwd=PROJECT_ROOT, stdout=f, stderr=f)
        
        print(f"Pytest completed with return code: {result.returncode}")
        print(f"Log file: {log_file}")
        
        # 保存结果
        result_file = output_dir / "result.json"
        result_data = {
            "returncode": result.returncode,
            "timestamp": datetime.datetime.now().isoformat(),
            "command": full_cmd,
            "output_file": str(log_file)
        }
        with open(result_file, "w") as f:
            json.dump(result_data, f, indent=2)
        
        return result.returncode
    
    # 前台运行
    result = run_pytest(pytest_cmd, verbose=args.verbose)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
