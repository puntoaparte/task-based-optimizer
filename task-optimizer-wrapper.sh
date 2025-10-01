#!/bin/bash

# task-optimizer-wrapper.sh - Wrapper script to run task-optimizer with sudo privileges
# This script helps ensure the task optimizer can make system-level optimizations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# When installed, the main script is named "task-optimizer" (without .sh extension)
# When run from source directory, it's named "task-optimizer.sh"
if [ -f "$SCRIPT_DIR/task-optimizer" ]; then
    TASK_OPTIMIZER="$SCRIPT_DIR/task-optimizer"
elif [ -f "$SCRIPT_DIR/task-optimizer.sh" ]; then
    TASK_OPTIMIZER="$SCRIPT_DIR/task-optimizer.sh"
else
    echo -e "${RED}Error: Main task optimizer script not found in $SCRIPT_DIR${NC}" 1>&2
    exit 1
fi

# Make sure the main script is executable
chmod +x "$TASK_OPTIMIZER" 2>/dev/null || { echo -e "${RED}Error: Could not set executable permissions on main script${NC}" 1>&2; exit 1; }

# Run the main script WITH SUDO privileges to allow system-level optimizations
echo -e "${BLUE}Executing task-optimizer with elevated privileges...${NC}"
sudo "$TASK_OPTIMIZER" "$@"