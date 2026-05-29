#!/usr/bin/env python3
import os
import subprocess
import sys
import json

def run_command(cmd):
    try:
        result = subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return f"Error: {e.stderr.strip()}"

def check_sysctl(param):
    return run_command(f"/usr/sbin/sysctl -n {param}")

def check_mount_options(path):
    return run_command(f"findmnt {path} -o OPTIONS")

def check_scheduler(dev):
    if os.path.exists(f"/sys/block/{dev}/queue/scheduler"):
        return run_command(f"cat /sys/block/{dev}/queue/scheduler")
    return "N/A"

def get_limits(limit_type):
    # limit_type is -Sn or -Hn
    return run_command(f"ulimit {limit_type}")

def main():
    print("=== AuroraOps Phase 0: Infrastructure Baseline Verification ===")
    
    # 1. Check I/O Scheduler & Mount Options
    print("\n[Storage Optimization]")
    # Try to find the root disk
    root_dev = run_command("lsblk -no PKNAME $(findmnt -nvo SOURCE /) | head -n1")
    if not root_dev:
        root_dev = "vda" # Fallback
    
    sched = check_scheduler(root_dev)
    root_opts = check_mount_options("/")
    print(f"  - Disk Scheduler ({root_dev}): {sched}")
    print(f"  - Root Mount Options: {root_opts}")
    
    # 2. Check Sysctl I/O & Network
    print("\n[Kernel & Network Tuning]")
    dirty_ratio = check_sysctl("vm.dirty_ratio")
    dirty_bg = check_sysctl("vm.dirty_background_ratio")
    tcp_cc = check_sysctl("net.ipv4.tcp_congestion_control")
    rmem_max = check_sysctl("net.core.rmem_max")
    
    print(f"  - vm.dirty_ratio: {dirty_ratio}")
    print(f"  - vm.dirty_background_ratio: {dirty_bg}")
    print(f"  - TCP Congestion Control: {tcp_cc}")
    print(f"  - net.core.rmem_max: {rmem_max}")
    
    # 3. Check System Limits
    print("\n[System Limits]")
    soft_nofile = get_limits("-Sn")
    hard_nofile = get_limits("-Hn")
    print(f"  - Max Open Files (Soft): {soft_nofile}")
    print(f"  - Max Open Files (Hard): {hard_nofile}")
    
    # 4. Check Swap & Zram
    print("\n[Memory & Swap]")
    swap_info = run_command("/usr/sbin/swapon --show --noheadings")
    print(f"  - Active Swap:\n{swap_info if swap_info else '    None'}")
    
    # 5. Check Service Status
    print("\n[Core Services]")
    for svc in ["systemd-journald", "fail2ban", "systemd-timesyncd"]:
        status = run_command(f"systemctl is-active {svc}")
        print(f"  - {svc}: {status}")
    
    # 6. Current Load Snapshot
    print("\n--- Current System Load Snapshot ---")
    print(run_command("top -b -n 1 | head -n 5"))
    
    print("\n--- Current I/O Load (Top 5) ---")
    # Check if pidstat exists
    if run_command("which pidstat") != "Error: ":
        print(run_command("pidstat -d 1 1 | sort -k 4 -rn | head -n 5"))
    else:
        print("  - pidstat not found, skipping I/O process breakdown.")

if __name__ == "__main__":
    main()
