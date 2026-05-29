#!/usr/bin/env python3
"""
子标签格式检查器 - 检查 Ansible 角色任务中的子标签是否符合规范

规范：
1. 所有子标签必须以 "<role>_" 开头（如 nginx_config, docker_install）
2. 例外：
   - 保留标签：always, never
   - 阶段标签：phase0, phase1, ..., phase9
   - 特殊角色：docker_apps 允许应用名作为子标签（如 sillytavern, gcli2api）

Usage:
    python scripts/check_subtags.py [--strict]
"""

import os
import sys
import yaml
import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent
COLLECTIONS_DIR = PROJECT_ROOT / "collections" / "ansible_collections" / "vps"

# 保留标签（不需要以角色名开头）
RESERVED_TAGS = {'always', 'never'}

# 阶段标签（不需要以角色名开头）
PHASE_TAGS = {'phase0', 'phase1', 'phase2', 'phase2_5', 'phase3', 'phase4', 'phase5', 'phase6', 'phase6_5', 'phase6_8', 'phase7', 'phase9', 'phase10'}

# 特殊角色及其允许的特殊子标签
SPECIAL_ROLES = {
    'docker_apps': {
        # docker_apps 允许应用名作为子标签
        'allowed_subtags': {
            'sillytavern', 'gcli2api', 'vaultwarden', 'gemini', 'flare',
            'singbox', 'cliproxyapi', 'newapi_suite', 'shellcrash',
            'init_data', 'hysteria2', 'restore_consistency', 'priority'
        }
    },
    'nodejs': {
        # nodejs 管理的 npm 包，允许包名作为子标签
        'allowed_subtags': {
            'bitwarden', 'opencode',  # 包名
            'bitwarden_login', 'bitwarden_sync',  # 细粒度功能
            'opencode_install', 'opencode_config', 'opencode_antigravity',
            'opencode_project_config', 'opencode_server'
        }
    }
}


def load_yaml_file(file_path):
    """安全加载 YAML 文件"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"❌ Error parsing YAML in {file_path}: {e}")
        return None
    except FileNotFoundError:
        print(f"❌ File not found: {file_path}")
        return None


def is_valid_subtag(tag, role_name, domain):
    """
    检查子标签是否符合规范
    
    返回: (is_valid, reason)
    """
    # 1. 检查是否是保留标签
    if tag in RESERVED_TAGS:
        return True, None
    
    # 2. 检查是否是阶段标签
    if tag in PHASE_TAGS:
        return True, None
    
    # 3. 检查是否是 action 标签
    if tag in {'deploy', 'verify', 'rollback', 'restore'}:
        return True, None
    
    # 4. 检查是否是 domain 或 role 本身
    if tag == domain or tag == role_name:
        return True, None
    
    # 5. 检查特殊角色的特殊子标签
    if role_name in SPECIAL_ROLES:
        special_config = SPECIAL_ROLES[role_name]
        if tag in special_config.get('allowed_subtags', set()):
            return True, None
    
    # 6. 检查是否以 role_name 开头
    expected_prefix = f"{role_name}_"
    if tag.startswith(expected_prefix):
        return True, None
    
    # 7. 不符合规范
    expected_tag = f"{role_name}_{tag}"
    return False, f"子标签 '{tag}' 不符合规范，应该改为 '{expected_tag}'"


def check_task_subtags(task, role_name, domain, file_path, task_idx):
    """检查单个任务的子标签"""
    issues = []
    
    if not isinstance(task, dict):
        return issues
    
    tags = task.get('tags', [])
    if isinstance(tags, str):
        tags = [tags]
    
    task_name = task.get('name', f'Task {task_idx}')
    
    for tag in tags:
        is_valid, reason = is_valid_subtag(tag, role_name, domain)
        if not is_valid:
            issues.append({
                'file': file_path,
                'task_name': task_name,
                'tag': tag,
                'reason': reason,
                'role': role_name,
                'domain': domain
            })
    
    return issues


def check_role_file(file_path, domain, role_name):
    """检查角色任务文件"""
    issues = []
    
    data = load_yaml_file(file_path)
    if not data or not isinstance(data, list):
        return issues
    
    for idx, task in enumerate(data, 1):
        task_issues = check_task_subtags(task, role_name, domain, file_path, idx)
        issues.extend(task_issues)
    
    return issues


def main():
    """主函数"""
    import argparse
    parser = argparse.ArgumentParser(description='检查 Ansible 子标签格式')
    parser.add_argument('--strict', action='store_true', help='严格模式（包含警告）')
    parser.add_argument('--fix-suggestions', action='store_true', help='输出修复建议')
    args = parser.parse_args()
    
    all_issues = []
    total_files_checked = 0
    
    print("🔍 Checking subtag format compliance...")
    print("=" * 70)
    
    # 遍历所有 domain
    for domain_path in COLLECTIONS_DIR.iterdir():
        if not domain_path.is_dir():
            continue
        
        domain = domain_path.name
        roles_dir = domain_path / "roles"
        
        if not roles_dir.exists():
            continue
        
        # 遍历所有 role
        for role_path in roles_dir.iterdir():
            if not role_path.is_dir():
                continue
            
            role_name = role_path.name
            tasks_dir = role_path / "tasks"
            
            if not tasks_dir.exists():
                continue
            
            # 检查所有任务文件
            for task_file in ['main.yml', 'verify.yml', 'rollback.yml', 'deploy.yml']:
                file_path = tasks_dir / task_file
                
                if not file_path.exists():
                    continue
                
                total_files_checked += 1
                issues = check_role_file(str(file_path), domain, role_name)
                all_issues.extend(issues)
    
    # 输出结果
    print(f"\n📊 Summary: {total_files_checked} files checked, {len(all_issues)} issues found")
    print("=" * 70)
    
    if all_issues:
        # 按角色分组
        from collections import defaultdict
        by_role = defaultdict(list)
        for issue in all_issues:
            key = f"{issue['domain']}.{issue['role']}"
            by_role[key].append(issue)
        
        print("\n❌ Issues by role:")
        for role_key in sorted(by_role.keys()):
            role_issues = by_role[role_key]
            print(f"\n  📦 {role_key} ({len(role_issues)} issues)")
            
            for issue in role_issues:
                print(f"     • {issue['tag']}")
                print(f"       File: {issue['file']}")
                print(f"       Task: {issue['task_name'][:60]}...")
                print(f"       Fix:  {issue['reason']}")
                print()
        
        if args.fix_suggestions:
            print("\n💡 Auto-fix suggestions:")
            print("-" * 70)
            for role_key in sorted(by_role.keys()):
                print(f"\n# Fix for {role_key}")
                role_issues = by_role[role_key]
                unique_tags = {issue['tag']: issue for issue in role_issues}
                
                for old_tag, issue in unique_tags.items():
                    new_tag = f"{issue['role']}_{old_tag}"
                    print(f"# Replace '{old_tag}' -> '{new_tag}'")
        
        print(f"\n⚠️  Found {len(all_issues)} subtag format issues")
        return 1
    else:
        print("\n✅ All subtags comply with the naming convention!")
        print("   Format: <role>_<function>")
        print("   Special roles: docker_apps (allows app names)")
        return 0


if __name__ == "__main__":
    sys.exit(main())
