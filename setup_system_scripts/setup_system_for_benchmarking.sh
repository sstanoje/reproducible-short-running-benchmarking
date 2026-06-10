#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# Default isolated core if none is provided (defaults to 3)
ISOLATED_CORE=${2:-3}

show_help() {
  echo "Usage: sudo ./setup_system.sh [OPTION] [CORE_NUMBER]"
  echo "Options:"
  echo "  -p, --performance    Set CPU governor to performance and disable TurboBoost"
  echo "  -m, --memory         Disable swap and drop filesystem caches"
  echo "  -s, --security       Disable Address Space Layout Randomization (ASLR)"
  echo "  -t, --topology       Disable Hyper-Threading (SMT)"
  echo "  -n, --ntp            Stop NTP time syncing"
  echo "  -c, --cstates        Apply GRUB C-state optimizations (max_cstate=0)"
  echo "  -i, --isolate        Apply GRUB Core Isolation for core [CORE_NUMBER]"
  echo "  -M, --mt-rec         MT Recommended: Perf, Mem, Security, NTP, and Disabled C-states"
  echo "  -a, --all            Apply all (Recommended Mode: MT-Rec + Isolate + Disable HT)"
  echo "  -h, --help           Show this help message"
}

# --- Tuning Functions ---

tune_performance() {
    echo "--- Setting Performance Mode ---"
    if [ -f "/sys/devices/system/cpu/intel_pstate/no_turbo" ]; then
        echo "1" > /sys/devices/system/cpu/intel_pstate/no_turbo
    fi
    num_of_cores=$(nproc)
    for i in $(seq 0 $((num_of_cores-1))); do
        if [ -f "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor" ]; then
            echo "performance" > "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor"
        fi
    done
}

tune_memory() {
    echo "--- Cleaning Memory ---"
    swapoff -a
    echo "3" > /proc/sys/vm/drop_caches
    sync
}

tune_security() {
    echo "--- Disabling ASLR ---"
    echo "0" > /proc/sys/kernel/randomize_va_space
}

tune_topology() {
    echo "--- Disabling Hyper-Threading ---"
    if [ -f "/sys/devices/system/cpu/smt/control" ]; then
        echo off > /sys/devices/system/cpu/smt/control
    fi
}

tune_ntp() {
    echo "--- Stopping NTP ---"
    systemctl stop systemd-timesyncd 2>/dev/null || service ntp stop 2>/dev/null
}

# --- New Decoupled GRUB Functions ---

apply_grub_changes() {
    local opts="$1"
    GRUB_FILE="/etc/default/grub"
    cp $GRUB_FILE "${GRUB_FILE}.bak"
    sed -i "s|^GRUB_CMDLINE_LINUX=\".*\"|GRUB_CMDLINE_LINUX=\"$opts\"|" $GRUB_FILE

    if command -v update-grub > /dev/null; then
        update-grub
    else
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
    echo "!!! GRUB updated with: $opts. REBOOT REQUIRED !!!"
}

tune_cstates_only() {
    echo "--- Disabling C-states ---"
    local opts="processor.max_cstate=0 intel_idle.max_cstate=0"
    apply_grub_changes "$opts"
}

tune_isolation_only() {
    local target_core=$1
    echo "--- Setting Core Isolation ($target_core) ---"
    local max_idx=$(($(nproc) - 1))
    local affinity=""
    if [ "$target_core" -eq 0 ]; then affinity="1-$max_idx"
    elif [ "$target_core" -eq "$max_idx" ]; then affinity="0-$((max_idx - 1))"
    else affinity="0-$((target_core - 1)),$((target_core + 1))-$max_idx"; fi

    local opts="isolcpus=domain,managed_irq,$target_core nohz_full=$target_core rcu_nocbs=$target_core irqaffinity=$affinity"
    apply_grub_changes "$opts"
}

tune_full_grub() {
    local target_core=$1
    echo "--- Setting Full GRUB (C-states + Isolation $target_core) ---"
    local max_idx=$(($(nproc) - 1))
    local affinity=""
    if [ "$target_core" -eq 0 ]; then affinity="1-$max_idx"
    elif [ "$target_core" -eq "$max_idx" ]; then affinity="0-$((max_idx - 1))"
    else affinity="0-$((target_core - 1)),$((target_core + 1))-$max_idx"; fi

    local opts="processor.max_cstate=0 intel_idle.max_cstate=0 isolcpus=domain,managed_irq,$target_core nohz_full=$target_core rcu_nocbs=$target_core irqaffinity=$affinity"
    apply_grub_changes "$opts"
}

# --- Argument Parsing ---

case "$1" in
    -p|--performance) tune_performance ;;
    -m|--memory)      tune_memory ;;
    -s|--security)    tune_security ;;
    -t|--topology)    tune_topology ;;
    -n|--ntp)         tune_ntp ;;
    -c|--cstates)     tune_cstates_only ;;
    -i|--isolate)     tune_isolation_only "$ISOLATED_CORE" ;;
    -M|--mt-rec)
        # MT mode now includes C-state disabling
        tune_performance
        tune_memory
        tune_security
        tune_ntp
        tune_cstates_only
        ;;
    -a|--all)
        tune_performance
        tune_memory
        tune_security
        tune_topology
        tune_ntp
        tune_full_grub "$ISOLATED_CORE"
        ;;
    *) show_help; exit 1 ;;
esac
