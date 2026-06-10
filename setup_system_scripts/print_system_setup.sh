#!/bin/bash

# --- Formatting Helpers ---
BOLD="\e[1m"
GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

print_header() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${RESET}"
}

print_stat() {
    local label=$1
    local value=$2
    local status_color=$RESET

    # Color coding for readability
    # Enabled/Performance = Green
    # Disabled/0 = Red
    if [[ "$value" == "enabled" || "$value" == "performance" ]]; then
        status_color=$GREEN
    elif [[ "$value" == "disabled" || "$value" == "0" ]]; then
        status_color=$RED
    fi

    printf "%-30s : %b%s%b\n" "$label" "$status_color" "$value" "$RESET"
}

# --- Data Collection ---

# Turboboost
turboboost_val=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo "N/A")
[[ "$turboboost_val" == "1" ]] && tb_status="disabled" || tb_status="enabled"

# ASLR
aslr_val=$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null)
[[ "$aslr_val" == "0" ]] && aslr_status="disabled" || aslr_status="enabled"

# SMT (Hyper-threading)
smt_val=$(cat /sys/devices/system/cpu/smt/control 2>/dev/null || echo "unknown")
[[ "$smt_val" == "off" ]] && ht_status="disabled" || ht_status="enabled"

# NTP status
ntp_status=$(systemctl is-active systemd-timesyncd 2>/dev/null || echo "inactive")

# C-States Logic
c_state_limit=$(cat /sys/module/intel_idle/parameters/max_cstate 2>/dev/null || echo "N/A")
if [[ "$c_state_limit" == "0" ]]; then
    c_status="disabled"
else
    c_status="enabled (max: $c_state_limit)"
fi

# --- Output ---

clear
echo -e "${BOLD}SYSTEM TUNING STATUS REPORT${RESET}"
echo "------------------------------------------------"

print_header "CPU & Power Settings"
print_stat "TurboBoost" "$tb_status"

# Scaling Governor (summarized)
num_of_cores=$(nproc)
governors=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u)
if [[ $(echo "$governors" | wc -l) -eq 1 ]]; then
    print_stat "Scaling Governor (All)" "$governors"
else
    echo -e "Scaling Governors: Mixed"
    for i in $(seq 0 $((num_of_cores-1))); do
        gov=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor 2>/dev/null)
        print_stat "  Core $i" "$gov"
    done
fi

print_stat "Hyper-Threading (SMT)" "$ht_status"
print_stat "C-States" "$c_status"

print_header "Kernel & Memory"
print_stat "ASLR" "$aslr_status"
print_stat "NTP Syncing" "$ntp_status"

# Isolated CPUs
isolated=$(cat /sys/devices/system/cpu/isolated 2>/dev/null)
[[ -z "$isolated" ]] && isolated="None"
print_header "Isolation & Boot"
print_stat "Isolated Cores" "$isolated"

echo "------------------------------------------------"