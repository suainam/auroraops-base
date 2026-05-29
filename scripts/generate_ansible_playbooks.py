import os
import re
import yaml
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
MAKEFILE_PATH = os.path.join(PROJECT_ROOT, "Makefile")
PLAYBOOKS_DIR = os.path.join(PROJECT_ROOT, "playbooks")
COLLECTIONS_DIR = os.path.join(PROJECT_ROOT, "collections/ansible_collections/vps")

# 统计信息
stats = {
    'total_roles': 0,
    'explicit_phase': [],
    'fallback_phase': [],
    'unknown_phase': []
}

# 动作翻译
action_map = {
    'deploy': '部署',
    'verify': '验证',
    'rollback': '回滚'
}

action_file_map = {
    'deploy': 'deploy',
    'verify': 'verify',
    'rollback': 'rollback'
}

# 角色到阶段的精确映射
# Phase 0: Bootstrap (裸金属初始化)
# Phase 1: Hardening (安全加固)
# Phase 2: Foundation (基础环境)
# Phase 3: Runtime (运行时环境)
# Phase 4: Services (核心服务)
# Phase 5: Applications (业务应用)
# Phase 6: Observability (可观测性)
# Phase 7: Operations (运维)
# Phase 8: Maintenance (维护)
# Phase 9: CI/CD (持续集成)
#
# 排序规则: 按 phase 排序, phase 内按字母排序
ROLE_PHASE_MAP = {
    # Phase 0: Bootstrap (裸金属初始化) - 对应 domain: system
    'benchmark': 'phase0',
    'journald': 'phase0',
    'limits': 'phase0',
    'reinstall': 'phase0',
    'swap': 'phase0',
    'sysctl': 'phase0',
    'systemd_priority': 'phase0',
    'zram': 'phase0',

    # Phase 1: Hardening (安全加固) - 对应 domain: system
    'fail2ban': 'phase1',
    'firewall': 'phase1',
    'ssh': 'phase1',
    'unattended_upgrades': 'phase1',

    # Phase 2: Foundation (基础环境) - 对应 domain: system, personalization, services
    'base': 'phase2',
    'init': 'phase2',
    'logrotate': 'phase2',
    'user_management': 'phase2',
    'zerotier': 'phase2',
    'easytier': 'phase2',
    # Personalization (可选工具，并入 Foundation)
    'rclone': 'phase2',
    'vim': 'phase2',
    'zsh': 'phase2',

    # Phase 3: Runtime (运行时环境) - 对应 domain: services
    'ansibletest': 'phase3',
    'docker': 'phase3',
    'nodejs': 'phase3',
    'prereq_checks': 'phase3',
    'python_environment': 'phase1',
    'qmd': 'phase3',
    'redis': 'phase3',

    # Phase 4: Services (核心服务) - 对应 domain: services, applications
    'certbot': 'phase4',
    'nginx': 'phase4',
    'postgresql': 'phase4',

    # Phase 5: Applications (业务应用) - 对应 domain: services, applications
    'application_service': 'phase5',
    'application_timer': 'phase5',
    'container_deployer': 'phase5',
    'dailycheckin': 'phase5',
    'docker_apps': 'phase5',
    'ip2free_gateway': 'phase5',
    'openclaw': 'phase5',
    'openviking': 'phase5',

    # Phase 6: Observability (可观测性) - 对应 domain: observability
    'health_checks': 'phase6',
    'monitoring_stack': 'phase6',

    # Phase 7: Operations (运维) - 对应 domain: operations_loop
    'audit': 'phase7',
    'backup': 'phase7',
    'rustic': 'phase7',

    # Phase 8: Maintenance (维护) - 对应 domain: operations_loop
    'cleanup': 'phase8',
    'dist_upgrade': 'phase8',
    'update': 'phase8',

    # Phase 9: CI/CD - 对应 domain: ci_cd
    'gh_key': 'phase9',
    'runner': 'phase9',
    'workflow': 'phase9',
}

# 仅作为依赖被引用，不应独立部署的角色
LIBRARY_ROLES = {
    'backup_service',  # 已废弃，由 application_service 替代
    'backup_timer',   # 已废弃，由 application_timer 替代
}

# 额外标签映射 (Role -> Tags)
EXTRA_ROLE_TAGS = {
    'docker': ['docker_install', 'docker_config'],
    'docker_apps': ['sillytavern', 'gcli2api', 'hysteria2', 'vaultwarden', 'gemini', 'flare', 'singbox', 'cliproxyapi', 'init_data', 'newapi_suite', 'shellcrash', 'optimizer', 'manifest'],
    'nginx': ['nginx_install', 'nginx_site_config', 'nginx_site_enable', 'nginx_cfip', 'nginx_logrotate', 'nginx_config'],
    'certbot': ['certbot_install', 'certbot_certs'],
    'nodejs': [
        # Core functionality (role prefix required)
        'nodejs_install',    # Node.js installation
        'nodejs_npm',        # npm configuration and package management
        # Managed packages (package name as tag, like docker_apps)
        'bitwarden',         # Bitwarden CLI (bw command)
        'opencode',          # OpenCode AI assistant
        'hermes',            # Hermes AI agent (replacing OpenClaw)
        'openclaw',          # OpenClaw AI bot gateway
        # Internal fine-grained tags (for advanced users)
        'bitwarden_login', 'bitwarden_sync',
        'opencode_install', 'opencode_config', 'opencode_project_config', 'opencode_server',
        'openclaw_check', 'openclaw_config', 'openclaw_auth', 'openclaw_telegram', 'openclaw_verify',
    ],
    'redis': ['redis_install', 'redis_config', 'redis_logrotate'],
    'postgresql': ['postgresql_install', 'postgresql_config', 'postgresql_users_dbs', 'postgresql_logrotate'],
    'audit': ['audit_security_audit', 'audit_timer_config', 'audit_timer_verify', 'audit_timer_rollback', 'audit_cleanup'],
    'ansibletest': [
        'ansibletest_install',   # 安装测试依赖
        'ansibletest_run',       # 运行测试
        'ansibletest_status',     # 查看状态
        'ansibletest_result',     # 查看结果
        'ansibletest_cleanup'     # 清理环境
    ],
    'ip2free_gateway': ['ip2free_gateway_install', 'ip2free_gateway_config'],
    'qmd': ['qmd_install', 'qmd_links', 'qmd_verify', 'qmd_rollback'],
    # 'openclaw': ['openclaw_check', 'openclaw_config', 'openclaw_auth', 'openclaw_telegram', 'openclaw_verify'],
    'openviking': ['openviking_install', 'openviking_config', 'openviking_verify'],
    'backup': ['backup_full'],  # 深度验证子标签 (哈希校验)
    'rustic': ['rustic_restore'],  # Rustic 子标签 (restore, verify, rollback)
    'gh_key': [
        'gh_key_install',    # Generate key
        'gh_key_config',     # Configure SSH
        'gh_key_api',        # Add to GitHub
        'gh_key_clone'      # Clone repository
    ]
}

DOMAIN_PHASE_MAP = {
    'system': 'phase0',       # 包含 phase0-2 角色 (bootstrap, hardening, foundation)
    'personalization': 'phase2',  # 个性化工具 (foundation)
    'services': 'phase3',     # 运行时环境 (runtime)
    'applications': 'phase5', # 业务应用 (applications)
    'observability': 'phase6', # 可观测性 (observability)
    'operations_loop': 'phase7', # 运维 (operations)
    'ci_cd': 'phase9'        # CI/CD
}
# Note: These values are fallback defaults for roles not explicitly mapped in ROLE_PHASE_MAP.
# The actual phase for each role is determined by ROLE_PHASE_MAP, which takes precedence.
# Phase 0/4/8 are covered by explicit ROLE_PHASE_MAP entries, no separate domains needed.

def get_collection_domains():
    """获取 collection domains，按部署阶段顺序排序"""
    if not os.path.exists(COLLECTIONS_DIR):
        print(f"Warning: Collections directory not found at {COLLECTIONS_DIR}")
        return []
    
    # 按部署阶段顺序排序 domains
    PHASE_ORDER = [
        'system',
        'personalization',
        'services',
        'applications',
        'observability',
        'operations_loop',
        'ci_cd'
    ]
    
    all_domains = [d for d in os.listdir(COLLECTIONS_DIR) 
                   if os.path.isdir(os.path.join(COLLECTIONS_DIR, d)) and not d.startswith('.')]
    
    # 按 PHASE_ORDER 排序，未知 domain 放在最后
    sorted_domains = []
    for domain in PHASE_ORDER:
        if domain in all_domains:
            sorted_domains.append(domain)
    
    for domain in all_domains:
        if domain not in sorted_domains:
            sorted_domains.append(domain)
    
    return sorted_domains

def get_roles_in_domain(domain):
    roles_dir = os.path.join(COLLECTIONS_DIR, domain, "roles")
    if not os.path.exists(roles_dir): return []
    return [d for d in os.listdir(roles_dir) 
            if os.path.isdir(os.path.join(roles_dir, d)) and d not in LIBRARY_ROLES]

def get_phase_for_role(domain, role):
    """
    确定 Role 的部署阶段。
    优先使用 ROLE_PHASE_MAP (Explicit)，否则回退到 DOMAIN_PHASE_MAP (Fallback)。
    副作用：更新全局 stats 统计信息。
    """
    if role in ROLE_PHASE_MAP:
        # 仅在第一次遇到该 role 时记录（防止 deploy/verify/rollback 重复统计）
        if role not in [r[0] for r in stats['explicit_phase']]:
            stats['explicit_phase'].append((role, ROLE_PHASE_MAP[role]))
        return ROLE_PHASE_MAP[role]
    
    phase = DOMAIN_PHASE_MAP.get(domain, 'unknown')
    if phase == 'unknown':
        if role not in [r[0] for r in stats['unknown_phase']]:
            stats['unknown_phase'].append((role, domain))
    else:
        if role not in [r[0] for r in stats['fallback_phase']]:
            stats['fallback_phase'].append((role, phase))
            
    return phase

def generate_top_level_playbook(action, collection_domains):
    """生成顶层 Playbook (deploy.yml 等)"""
    playbook_content = []
    for domain in collection_domains:
        if get_roles_in_domain(domain):
            # 顶层 import 绝对不带标签，防止标签继承污染
            playbook_content.append({'import_playbook': f'{domain}/{action_file_map[action]}.yml'})

    output_path = os.path.join(PLAYBOOKS_DIR, f'{action_file_map[action]}.yml')
    with open(output_path, 'w') as f:
        f.write("# Generated by scripts/generate_ansible_playbooks.py\n")
        yaml.dump(playbook_content, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
    # print(f'Generated {output_path}')

def get_role_sort_key(domain, role):
    """
    确定 Role 的排序权重。
    Phase 0 拥有特殊的显式顺序，其他按 phase 和名称排序。
    """
    phase = get_phase_for_role(domain, role)
    
    # Phase 0 显式排序权重
    PHASE0_ORDER = {
        'benchmark': 0,
        'reinstall': 1,
        'journald': 2,
        'limits': 3,
        'swap': 4,
        'zram': 5,
        'sysctl': 10,  # Sysctl 依赖前面的指标，放在较后面
        'systemd_priority': 11
    }
    
    if phase == 'phase0' and role in PHASE0_ORDER:
        return (0, PHASE0_ORDER[role], role)
    
    # 提取 Phase 数字用于排序
    try:
        if phase.startswith('phase'):
            p_num = int(phase.replace('phase', ''))
        else:
            p_num = 99
    except:
        p_num = 99
        
    return (p_num, 50, role) # 50 是中间权重，非显式指定的 Phase 0 角色排在中间

def generate_functional_playbook(action, collection_domain, roles):
    """生成功能性 Playbook (如 system/deploy.yml)，采用 Single-Play 结构优化性能"""
    if not roles: return
    
    play = {
        'name': f'{action_map[action]} {collection_domain}',
        'hosts': 'all',
        'gather_facts': True, # 依赖 ansible.cfg 中的 smart gathering 和缓存
        'tags': [action, collection_domain],
        'tasks': []
    }
    
    if not os.environ.get("AURORAOPS_SKIP_VAULT"):
        play['vars_files'] = [
            '../../secrets/vault.yml' if collection_domain != '.' else './secrets/vault.yml'
        ]

    # 按阶段和显式权重排序角色
    sorted_roles = sorted(roles, key=lambda r: get_role_sort_key(collection_domain, r))

    for role in sorted_roles:
        phase = get_phase_for_role(collection_domain, role)
        apply_attrs = {
            'tags': [action, phase, collection_domain, role]
        }
        if collection_domain == 'ci_cd' and role == 'workflow':
            apply_attrs['become'] = False
        task = {
            'name': f'{action_map[action]} {collection_domain}.{role}',
            'include_role': {
                'name': f'vps.{collection_domain}.{role}',
                'tasks_from': action if action in ['verify', 'rollback'] else 'main',
                'apply': apply_attrs
            },
            'when': f"auroraops_roles['{collection_domain}']['{role}'] | default(true) | bool",
            'tags': [action, phase, collection_domain, role] + EXTRA_ROLE_TAGS.get(role, [])
        }
        play['tasks'].append(task)

    domain_playbooks_dir = os.path.join(PLAYBOOKS_DIR, collection_domain)
    os.makedirs(domain_playbooks_dir, exist_ok=True)
    output_path = os.path.join(domain_playbooks_dir, f'{action_file_map[action]}.yml')
    with open(output_path, 'w') as f:
        f.write(f"# Generated by scripts/generate_ansible_playbooks.py\n# Optimized Single-Play structure for high performance\n")
        yaml.dump([play], f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
    # print(f'Generated {output_path}')

def print_summary():
    """打印生成统计报告"""
    explicit_count = len(stats['explicit_phase'])
    fallback_count = len(stats['fallback_phase'])
    unknown_count = len(stats['unknown_phase'])
    total_count = explicit_count + fallback_count + unknown_count
    
    print("-" * 60)
    print(f"Playbook Generation Summary")
    print("-" * 60)
    print(f"Total Roles Processed: {total_count}")
    print(f"Explicit Phase Mapped: \033[32m{explicit_count}\033[0m") # Green
    
    if fallback_count > 0:
        print(f"Domain Fallback Used:  \033[33m{fallback_count}\033[0m (Warning: Verify these phases)") # Yellow
        for role, phase in stats['fallback_phase']:
            print(f"  - {role} -> {phase} (via domain default)")
            
    if unknown_count > 0:
        print(f"Unknown Phase:         \033[31m{unknown_count}\033[0m (Error: Phase not found)") # Red
        for role, domain in stats['unknown_phase']:
            print(f"  - {role} (domain: {domain})")
            
    print("-" * 60)

def main():
    domains = get_collection_domains()
    # 仅在第一次迭代（deploy）时收集统计信息即可，因为 Verify/Rollback 的 Role 集合是一样的
    # 但由于 get_phase_for_role 内部做了去重，多次调用也无妨
    
    print("Generating playbooks...")
    for action in ['deploy', 'verify', 'rollback']:
        generate_top_level_playbook(action, domains)
        for d in domains:
            generate_functional_playbook(action, d, get_roles_in_domain(d))
            
    print_summary()

if __name__ == '__main__':
    main()
