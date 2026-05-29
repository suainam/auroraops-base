import os
import re

DYNAMIC_TASK_FILES = {
    # These task files are intentionally kept dynamic so their subtags can
    # stay opt-in and avoid expanding into unrelated runs.
    "hysteria2_client.yml",
}

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    # 1. Replace include_tasks with import_tasks for static .yml files
    # Pattern: ansible.builtin.include_tasks: filename.yml (no variables)
    def repl(match):
        task_ref = match.group(1).strip("'\"")
        if task_ref in DYNAMIC_TASK_FILES:
            return match.group(0)
        return f"ansible.builtin.import_tasks: {match.group(1)}"

    new_content = re.sub(
        r'ansible\.builtin\.include_tasks:\s+([\'"]?[\w\-\.]+\.yml[\'"]?)',
        repl,
        content
    )
    
    # Also handle without ansible.builtin prefix
    def repl_plain(match):
        task_ref = match.group(1).strip("'\"")
        if task_ref in DYNAMIC_TASK_FILES:
            return match.group(0)
        return f"import_tasks: {match.group(1)}"

    new_content = re.sub(
        r'(?<!ansible\.builtin\.)include_tasks:\s+([\'"]?[\w\-\.]+\.yml[\'"]?)',
        repl_plain,
        new_content
    )
    
    if content != new_content:
        with open(filepath, 'w') as f:
            f.write(new_content)
        return True
    return False

def main():
    collections_dir = 'collections/ansible_collections/vps'
    modified_count = 0
    for root, dirs, files in os.walk(collections_dir):
        for file in files:
            if file == 'main.yml' and 'tasks' in root:
                filepath = os.path.join(root, file)
                if process_file(filepath):
                    print(f"Modified: {filepath}")
                    modified_count += 1
    print(f"Total files modified: {modified_count}")

if __name__ == '__main__':
    main()
