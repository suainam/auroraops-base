import os
import yaml

COLLECTION_DOMAINS = ["system", "personalization", "services", "applications", "observability", "operations_loop", "ci_cd"]

# Ansible 动作类型列表 (deploy/verify/rollback/restore 互斥)
ACTION_MODES = ['deploy', 'verify', 'rollback', 'restore']

# 任务模式检测模式 - 用于识别特殊模式任务，免于通用标签检查
# 键: 动作模式, 值: 检测该模式的 when 条件关键字
TASK_MODE_PATTERNS = {
    'restore': ['_restore_mode', 'restore_'],
    'verify': ['_verify_mode', 'verify_'],
    'rollback': ['_rollback_mode', 'rollback_'],
}

# 动态获取项目根目录
# os.path.abspath(__file__) 获取当前脚本的绝对路径
# os.path.dirname() 获取目录名，连续两次获取到项目根目录
ANSIBLE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load_yaml_file(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML in {file_path}: {e}")
        return None
    except FileNotFoundError:
        print(f"File not found: {file_path}")
        return None

def check_tags(item, expected_tags, item_type, file_path, item_name=""):
    missing_tags = []
    if 'tags' not in item:
        missing_tags.append(f"Missing 'tags' field in {item_type} '{item_name}' in {file_path}")
    else:
        for tag in expected_tags:
            if tag not in item['tags']:
                missing_tags.append(f"Missing expected tag '{tag}' in {item_type} '{item_name}' in {file_path}")
    return missing_tags

def check_playbook_tags(file_path, collection_domain=None):
    issues = []
    data = load_yaml_file(file_path)
    if not data:
        return issues

    if isinstance(data, list):
        for play in data:
            # Determine the action tag based on the playbook file name
            current_playbook_action_tag = None
            if 'deploy.yml' in file_path:
                current_playbook_action_tag = 'deploy'
            elif 'verify.yml' in file_path:
                current_playbook_action_tag = 'verify'
            elif 'rollback.yml' in file_path:
                current_playbook_action_tag = 'rollback'

            # 顶层 Playbook 的处理 (deploy.yml, verify.yml, rollback.yml)
            if not collection_domain:
                # 检查 import_playbook
                if 'import_playbook' in play:
                    # 顶层 import 现在不强制要求标签，以防污染继承链
                    pass 
                continue

            # 功能性 Playbook 的处理 (playbooks/<domain>/deploy.yml)
            if collection_domain:
                # 检查 Play 级别的标签
                expected_play_tags = [current_playbook_action_tag, collection_domain]
                issues.extend(check_tags(play, expected_play_tags, "play", file_path, play.get('name', 'Unnamed Play')))

                # 检查 roles
                if 'roles' in play and play['roles'] is not None:
                    for role_entry in play['roles']:
                        role_name = role_entry if isinstance(role_entry, str) else role_entry.get('role')
                        if role_name:
                            parts = role_name.split('.')
                            if len(parts) >= 3:
                                # role 格式: vps.domain.role_name
                                role_actual_name = parts[2]
                                expected_role_tags = [current_playbook_action_tag, collection_domain, role_actual_name]
                                issues.extend(check_tags(role_entry, expected_role_tags, "role entry", file_path, role_name))

    return issues

def get_task_mode_from_when(task):
    """通过 when 条件检测任务执行模式，返回 ACTION_MODES 中的模式或 None"""
    when_condition = task.get('when', '')
    
    # 统一处理为列表
    conditions = [when_condition] if isinstance(when_condition, str) else when_condition if isinstance(when_condition, list) else []
    
    # 遍历所有动作模式检测
    for mode in ACTION_MODES:
        patterns = TASK_MODE_PATTERNS.get(mode, [f'_{mode}_mode'])
        for condition in conditions:
            if isinstance(condition, str):
                if any(p in condition.lower() for p in patterns):
                    return mode
    
    return None


def check_role_task_tags(file_path, collection_domain, role_name):
    """检查角色任务标签"""
    issues = []
    data = load_yaml_file(file_path)
    if not data:
        return issues

    # 从文件名检测当前 playbook 类型
    current_playbook_type = None
    for mode in ACTION_MODES:
        if f'{mode}.yml' in file_path or (mode == 'deploy' and 'main.yml' in file_path):
            current_playbook_type = mode
            break
    
    if not current_playbook_type:
        return issues

    if isinstance(data, list):
        for task in data:
            task_name = task.get('name', 'Unnamed Task')
            expected_tags = []
            
            # 检测任务执行模式
            task_mode = get_task_mode_from_when(task)
            
            # 通用任务（无特定模式或模式匹配当前playbook）需要当前类型标签
            # 专用任务（如restore任务在deploy playbook中）不需要当前类型标签
            other_modes = [m for m in ACTION_MODES if m != current_playbook_type]
            is_dedicated_task = task_mode in other_modes
            
            if not is_dedicated_task:
                expected_tags.append(current_playbook_type)
            
            expected_tags.extend([collection_domain, role_name])
            issues.extend(check_tags(task, expected_tags, "role task", file_path, task_name))
    
    return issues

def main():
    all_issues = []

    # Check top-level playbooks
    for playbook_name in ["deploy.yml", "verify.yml", "rollback.yml"]:
        file_path = os.path.join(ANSIBLE_ROOT, "playbooks", playbook_name)
        if os.path.exists(file_path):
            print(f"Checking top-level playbook: {file_path}")
            all_issues.extend(check_playbook_tags(file_path))

    # Check functional playbooks
    for domain in COLLECTION_DOMAINS:
        for action_file in ["deploy.yml", "verify.yml", "rollback.yml"]:
            file_path = os.path.join(ANSIBLE_ROOT, "playbooks", domain, action_file)
            if os.path.exists(file_path):
                print(f"Checking functional playbook: {file_path}")
                all_issues.extend(check_playbook_tags(file_path, collection_domain=domain))

    # Check role tasks
    for domain in COLLECTION_DOMAINS:
        roles_path = os.path.join(ANSIBLE_ROOT, "collections", "ansible_collections", "vps", domain, "roles")
        if os.path.exists(roles_path):
            for role_name in os.listdir(roles_path):
                role_dir = os.path.join(roles_path, role_name)
                if os.path.isdir(role_dir):
                    for task_file in ["main.yml", "verify.yml", "rollback.yml", "deploy.yml"]:
                        file_path = os.path.join(role_dir, "tasks", task_file)
                        if os.path.exists(file_path):
                            print(f"Checking role task file: {file_path}")
                            all_issues.extend(check_role_task_tags(file_path, domain, role_name))

    if all_issues:
        print("\n--- Tag Check Report ---")
        for issue in all_issues:
            print(f"- {issue}")
        print("\nTag check completed with issues.")
    else:
        print("\nAll Ansible Playbooks and role tasks have proper tags.")

if __name__ == "__main__":
    main()
