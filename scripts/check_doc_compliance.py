#!/usr/bin/env python3
import os
import re
import sys

# 定义规范模板
ROLE_README_SECTIONS = [
    "## 1. 概述",
    "## 2. 变量说明",
    "## 3. 内部逻辑",
    "## 4. 依赖关系",
    "## 5. 维护与排查"
]

WIKI_USAGE_SECTIONS = [
    "## 1. 阶段目标",
    "## 2. 快速部署",
    "## 3. 关键配置说明",
    "## 4. 验证步骤",
    "## 5. 常见问题排查"
]

def check_file(file_path, required_sections):
    if not os.path.exists(file_path):
        return False, "文件不存在"
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    missing = []
    for section in required_sections:
        if section not in content:
            missing.append(section)
    
    if missing:
        return False, f"缺少章节: {', '.join(missing)}"
    return True, "符合规范"

def main():
    base_dir = "/root/AuroraOps"
    roles_base = os.path.join(base_dir, "collections/ansible_collections/vps")
    wiki_base = os.path.join(base_dir, "wiki")
    
    issues = []

    # 1. 检查 Roles README
    print("--- 检查 Role README 规范 ---")
    for root, dirs, files in os.walk(roles_base):
        if os.path.basename(root) == "roles":
            for role in dirs:
                # 忽略某些特殊的目录或文件
                if role.startswith('.') or role == "__pycache__":
                    continue
                
                readme_path = os.path.join(root, role, "README.md")
                role_name = f"{os.path.basename(os.path.dirname(root))}/{role}"
                
                # 排除 archive 目录
                if "archive" in readme_path:
                    continue
                    
                is_ok, msg = check_file(readme_path, ROLE_README_SECTIONS)
                if not is_ok:
                    issues.append(f"[Role] {role_name}: {msg}")
                    print(f"❌ {role_name}: {msg}")
                else:
                    print(f"✅ {role_name}: OK")

    # 2. 检查 Wiki Usage
    print("\n--- 检查 Wiki Usage 规范 ---")
    for root, dirs, files in os.walk(wiki_base):
        for file in files:
            if file.endswith("_Usage.md") or file.endswith("Usage.md"):
                file_path = os.path.join(root, file)
                rel_path = os.path.relpath(file_path, wiki_base)
                
                is_ok, msg = check_file(file_path, WIKI_USAGE_SECTIONS)
                if not is_ok:
                    issues.append(f"[Wiki] {rel_path}: {msg}")
                    print(f"❌ {rel_path}: {msg}")
                else:
                    print(f"✅ {rel_path}: OK")

    if issues:
        print(f"\n发现 {len(issues)} 个文档规范问题。")
        # sys.exit(1) # 可选：在 CI 中退出非零
    else:
        print("\n所有文档均符合规范！")

if __name__ == "__main__":
    main()
