#!/bin/bash

# task-optimizer.sh - Optimize system resources for specific tasks
# Author: Qwen Code
# Date: $(date)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script information
SCRIPT_NAME="Task Optimizer"
SCRIPT_VERSION="1.1-enhanced"

# State file to store original configuration
STATE_FILE="/tmp/task_optimizer_state_$(id -u).txt"
BACKUP_DIR="/tmp/task_optimizer_backups_$(id -u)"

# Function to print header
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    $SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

# Function to print usage
print_usage() {
    echo "Usage:"
    echo "  task-optimizer start \"task description\"  - Start optimization for a task"
    echo "  task-optimizer stop                     - Restore original system state"
    echo "  task-optimizer status                   - Show current optimization status"
    echo "  task-optimizer help                     - Show this help message"
    echo
}

# Function to check if running as root
check_root() {
    # For the wrapper script that runs with sudo, we don't want to exit
    # But for normal usage, we warn the user that some features require sudo
    if [[ $EUID -eq 0 ]]; then
        # If running as root, we're likely being called by the wrapper
        # In this case, we proceed but note that we're in privileged mode
        echo "Running in privileged mode (root)"
    fi
}

# Function to check if sudo is available and working
check_sudo() {
    if ! command -v sudo &> /dev/null; then
        echo -e "${RED}Error: sudo is required but not found${NC}" 1>&2
        exit 1
    fi
    
    # Test sudo access
    if ! sudo -n true 2>/dev/null; then
        # Check if we're in an interactive terminal
        if [ -t 0 ] && [ -t 1 ]; then
            echo -e "${YELLOW}This script requires sudo privileges to optimize system resources.${NC}"
            echo -e "${YELLOW}Please enter your password when prompted.${NC}"
            if ! sudo -v; then
                echo -e "${RED}Error: Unable to obtain sudo privileges${NC}" 1>&2
                exit 1
            fi
        else
            echo -e "${YELLOW}Warning: Unable to obtain sudo privileges in non-interactive mode.${NC}"
            echo -e "${YELLOW}Some optimizations may not work. Please run with proper sudo privileges for full functionality.${NC}"
        fi
    fi
}

# Function to create backup directory
create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    # Ensure directory permissions are secure
    chmod 700 "$BACKUP_DIR"
}

# Function to capture current system state
capture_state() {
    echo "Capturing current system state..."
    
    # Create or clear state file
    > "$STATE_FILE"
    
    # Capture CPU governor states for all CPUs
    if [ -d "/sys/devices/system/cpu" ]; then
        local cpu_governors=()
        for cpu_path in /sys/devices/system/cpu/cpu[0-9]*; do
            if [ -f "$cpu_path/cpufreq/scaling_governor" ]; then
                local cpu_num=$(basename "$cpu_path")
                echo "CPU_${cpu_num}_GOVERNOR=$(cat "$cpu_path/cpufreq/scaling_governor")" >> "$STATE_FILE"
            fi
        done
    fi
    
    # Capture current nice values of running processes
    ps -eo pid,ni,comm | tail -n +2 > "$BACKUP_DIR/nice_values.txt"
    
    # Capture current I/O scheduler for all block devices
    for disk in /sys/block/*/queue/scheduler; do
        if [ -f "$disk" ]; then
            local disk_name=$(echo "$disk" | cut -d'/' -f4) # Extract disk name like sda, nvme0n1
            echo "IO_SCHEDULER_$disk_name=$(cat "$disk" | grep -o '\[.*\]' | tr -d '[]')" >> "$STATE_FILE"
        fi
    done
    
    # Capture current swappiness
    echo "SWAPPINESS=$(cat /proc/sys/vm/swappiness)" >> "$STATE_FILE"
    
    # Capture current CPU affinity for running processes (optional, can be slow on many processes)
    # We'll save this to a separate file to avoid cluttering the main state file
    > "$BACKUP_DIR/affinity_state.txt"  # Clear the file
    # This is a simplified approach - could be expanded to save to individual files per PID if needed
    ps -eo pid,comm | tail -n +2 | while read pid comm; do
        if [ -d "/proc/$pid" ] && [ -r "/proc/$pid/status" ]; then
            local affinity=$(taskset -p "$pid" 2>/dev/null | grep -o "affinity: .*" | cut -d' ' -f2 || echo "unknown")
            echo "AFFINITY_$pid=$affinity" >> "$BACKUP_DIR/affinity_state.txt"
        fi
    done
    
    echo "State captured successfully."
}

# Function to optimize for task
optimize_for_task() {
    local task_description="$1"
    echo -e "${GREEN}Optimizing system for task: $task_description${NC}"
    
    # Save task description
    echo "TASK_DESCRIPTION=$task_description" >> "$STATE_FILE"
    echo "OPTIMIZATION_START=$(date)" >> "$STATE_FILE"
    
    # Check if we have sudo access
    local has_sudo=false
    if sudo -n true 2>/dev/null; then
        has_sudo=true
    fi
    
    # 1. CPU Optimization - Set performance governor for all CPUs
    echo "Optimizing CPU performance..."
    if $has_sudo; then
        if command -v cpupower &> /dev/null; then
            # Use cpupower for a potentially more robust approach
            sudo cpupower frequency-set -g performance > /dev/null 2>&1 || echo "Could not set CPU governor using cpupower"
        else
            # Fallback to direct sysfs approach for all CPUs
            for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
                if [ -w "$cpu/cpufreq/scaling_governor" ]; then
                    echo "performance" | sudo tee "$cpu/cpufreq/scaling_governor" > /dev/null 2>&1 || true
                fi
            done
        fi
    else
        echo -e "${YELLOW}Skipping CPU optimization (requires sudo)${NC}"
    fi
    
    # 2. Memory Optimization - Reduce swappiness
    echo "Optimizing memory management..."
    echo "Previous swappiness: $(cat /proc/sys/vm/swappiness)"
    if $has_sudo; then
        echo 1 | sudo tee /proc/sys/vm/swappiness > /dev/null
    else
        echo -e "${YELLOW}Skipping memory optimization (requires sudo)${NC}"
    fi
    
    # 3. I/O Optimization - Set I/O scheduler to none/deadline based on disk type
    echo "Optimizing I/O scheduler..."
    if $has_sudo; then
        for disk in /sys/block/*/queue/scheduler; do
            if [ -w "$disk" ]; then
                local disk_name=$(echo "$disk" | cut -d'/' -f4)
                # Determine the best scheduler based on the disk type (sata, nvme, etc.)
                local preferred_scheduler
                if [[ "$disk_name" == nvme* ]]; then
                    # For NVMe SSDs, 'none' is often the best for newer kernels
                    # If 'none' is not available, try 'none' or stick with default if not found
                    preferred_scheduler="none"
                else
                    # For SATA SSDs and HDDs, 'deadline' or 'mq-deadline' are often good
                    preferred_scheduler="deadline"
                fi
                
                # Try to use the preferred scheduler first, then alternatives
                for scheduler in $preferred_scheduler none mq-deadline; do
                    if grep -q "$scheduler" "$disk"; then
                        echo "$scheduler" | sudo tee "$disk" > /dev/null
                        echo "Set scheduler for $disk_name to $scheduler"
                        break
                    else
                        echo "Scheduler $scheduler not available for $disk_name, trying next option..."
                    fi
                done
            fi
        done
    else
        echo -e "${YELLOW}Skipping I/O optimization (requires sudo)${NC}"
    fi
    
    # 4. Process Priority Optimization - Renice high priority processes
    echo "Optimizing process priorities..."
    # Give high priority to shell and its children (current process tree)
    renice -10 $$ > /dev/null 2>&1 || true # Use $$ for current process PID
    
    # 5. Disable unnecessary services temporarily (optional, requires more complex logic)
    echo -e "${YELLOW}Disabling non-essential services not implemented in this version.${NC}"
    # This is complex and system-specific. A real implementation would require a list of services to potentially stop.
    # For now, we just warn the user.
    echo -e "${YELLOW}Consider stopping services like bluetooth, cups-browsed, if not needed manually.${NC}"
    
    echo -e "${GREEN}Optimization complete!${NC}"
    echo "System is now optimized for: $task_description"
}

# Function to restore original state
restore_state() {
    if [ ! -f "$STATE_FILE" ]; then
        echo -e "${YELLOW}No optimization state found. Nothing to restore.${NC}"
        return 0
    fi
    
    echo -e "${GREEN}Restoring original system state...${NC}"
    
    # Check if we have sudo access
    local has_sudo=false
    if sudo -n true 2>/dev/null; then
        has_sudo=true
    fi
    
    # --- Restore CPU Governors ---
    if $has_sudo; then
        for line in $(grep -E '^CPU_cpu[0-9]+_GOVERNOR=' "$STATE_FILE"); do
            local cpu_gov_line="$line"
            local cpu_name=$(echo "$cpu_gov_line" | cut -d'=' -f1 | sed 's/CPU_//; s/_GOVERNOR//')
            local original_governor=$(echo "$cpu_gov_line" | cut -d'=' -f2)
            if [ -n "$cpu_name" ] && [ -n "$original_governor" ]; then
                local cpu_path="/sys/devices/system/cpu/$cpu_name/cpufreq/scaling_governor"
                if [ -w "$cpu_path" ]; then
                    echo "$original_governor" | sudo tee "$cpu_path" > /dev/null 2>&1 || echo "Could not restore governor for $cpu_name"
                    echo "Restored governor for $cpu_name to $original_governor"
                fi
            fi
        done
    else
        echo -e "${YELLOW}Skipping CPU governor restoration (requires sudo)${NC}"
    fi
    
    # --- Restore swappiness ---
    if grep -q "SWAPPINESS=" "$STATE_FILE"; then
        local original_swappiness=$(grep "SWAPPINESS=" "$STATE_FILE" | cut -d'=' -f2)
        echo "Restoring swappiness to $original_swappiness..."
        if $has_sudo; then
            echo "$original_swappiness" | sudo tee /proc/sys/vm/swappiness > /dev/null
        else
            echo -e "${YELLOW}Skipping swappiness restoration (requires sudo)${NC}"
        fi
    fi
    
    # --- Restore I/O scheduler ---
    if $has_sudo; then
        for line in $(grep -E '^IO_SCHEDULER_' "$STATE_FILE"); do
            local io_line="$line"
            local disk_name=$(echo "$io_line" | cut -d'=' -f1 | sed 's/IO_SCHEDULER_//')
            local original_scheduler=$(echo "$io_line" | cut -d'=' -f2)
            if [ -n "$disk_name" ] && [ -n "$original_scheduler" ]; then
                local disk_scheduler_path="/sys/block/$disk_name/queue/scheduler"
                if [ -w "$disk_scheduler_path" ] && grep -q "$original_scheduler" "$disk_scheduler_path"; then
                    echo "$original_scheduler" | sudo tee "$disk_scheduler_path" > /dev/null 2>&1
                    echo "Restored scheduler for $disk_name to $original_scheduler"
                else
                    echo "Original scheduler $original_scheduler not available or path unwritable for $disk_name"
                fi
            fi
        done
    else
        echo -e "${YELLOW}Skipping I/O scheduler restoration (requires sudo)${NC}"
    fi
    
    # Get task description for the message
    if grep -q "TASK_DESCRIPTION=" "$STATE_FILE"; then
        local task_description=$(grep "TASK_DESCRIPTION=" "$STATE_FILE" | cut -d'=' -f2-)
        echo "Task completed: $task_description"
    fi
    
    # Clean up state file
    rm -f "$STATE_FILE"
    # Clean up backup directory contents
    rm -f "$BACKUP_DIR"/*.txt
    
    echo -e "${GREEN}System state restored successfully!${NC}"
}

# Function to show status
show_status() {
    if [ -f "$STATE_FILE" ]; then
        echo -e "${YELLOW}System is currently optimized for a task:${NC}"
        if grep -q "TASK_DESCRIPTION=" "$STATE_FILE"; then
            local task_description=$(grep "TASK_DESCRIPTION=" "$STATE_FILE" | cut -d'=' -f2-)
            echo "Task: $task_description"
        fi
        if grep -q "OPTIMIZATION_START=" "$STATE_FILE"; then
            local start_time=$(grep "OPTIMIZATION_START=" "$STATE_FILE" | cut -d'=' -f2-)
            echo "Optimization started: $start_time"
        fi
        echo
        echo "Current system settings:"
        if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then
            echo "  CPU Governor (cpu0): $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")"
        fi
        echo "  Swappiness: $(cat /proc/sys/vm/swappiness)"
        if [ -f "/sys/block/sda/queue/scheduler" ]; then
            echo "  I/O Scheduler (sda): $(cat /sys/block/sda/queue/scheduler | grep -o '\[.*\]' | tr -d '[]')"
        fi
        if [ -f "/sys/block/nvme0n1/queue/scheduler" ] 2>/dev/null; then
            echo "  I/O Scheduler (nvme0n1): $(cat /sys/block/nvme0n1/queue/scheduler | grep -o '\[.*\]' | tr -d '[]' 2>/dev/null || echo "unknown")"
        fi
    else
        echo -e "${GREEN}System is in normal state (not optimized for any specific task)${NC}"
        echo
        echo "Current system settings:"
        if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then
            echo "  CPU Governor (cpu0): $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")"
        fi
        echo "  Swappiness: $(cat /proc/sys/vm/swappiness)"
        if [ -f "/sys/block/sda/queue/scheduler" ]; then
            echo "  I/O Scheduler (sda): $(cat /sys/block/sda/queue/scheduler | grep -o '\[.*\]' | tr -d '[]')"
        fi
        if [ -f "/sys/block/nvme0n1/queue/scheduler" ] 2>/dev/null; then
            echo "  I/O Scheduler (nvme0n1): $(cat /sys/block/nvme0n1/queue/scheduler | grep -o '\[.*\]' | tr -d '[]' 2>/dev/null || echo "unknown")"
        fi
    fi
}

# Function to show help
show_help() {
    print_header
    print_usage
    echo "This script optimizes your system resources for specific tasks and can restore"
    echo "the original state when the task is completed."
    echo
    echo "Features:"
    echo "  - CPU performance optimization (governor -> performance)"
    echo "  - Memory management tuning (swappiness -> 1)"
    echo "  - I/O scheduler optimization (deadline/none per disk type)"
    echo "  - Process priority adjustment (renice current process)"
    echo
    echo "Examples:"
    echo "  task-optimizer start \"Compiling kernel\""
    echo "  task-optimizer start \"Building Docker images\""
    echo "  task-optimizer stop"
    echo
}

# Main function
main() {
    check_root
    check_sudo
    create_backup_dir
    
    if [ $# -eq 0 ]; then
        print_header
        print_usage
        exit 1
    fi
    
    case "$1" in
        start)
            if [ $# -ne 2 ]; then
                echo -e "${RED}Error: Please provide a task description${NC}"
                print_usage
                exit 1
            fi
            
            # Capture current state before optimization
            capture_state
            # Apply optimizations
            optimize_for_task "$2"
            ;;
        stop)
            restore_state
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$1'${NC}"
            print_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"