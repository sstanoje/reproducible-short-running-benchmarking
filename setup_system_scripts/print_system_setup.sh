#!/bin/bash

# --- Data Collection ---

# Turbo Boost
turboboost_val=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo "N/A")
[[ "$turboboost_val" == "1" ]] && tb_status="disabled" || tb_status="enabled"

# ASLR
aslr_val=$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null)
[[ "$aslr_val" == "0" ]] && aslr_status="disabled" || aslr_status="enabled"

# SMT (Hyper-Threading)
smt_val=$(cat /sys/devices/system/cpu/smt/control 2>/dev/null || echo "unknown")
[[ "$smt_val" == "off" ]] && ht_status="disabled" || ht_status="enabled"

# NTP
ntp_status=$(systemctl is-active systemd-timesyncd 2>/dev/null || echo "inactive")

# C-States
c_state_limit=$(cat /sys/module/intel_idle/parameters/max_cstate 2>/dev/null || echo "N/A")
if [[ "$c_state_limit" == "0" ]]; then
    c_status="disabled"
else
    c_status="enabled (max: $c_state_limit)"
fi

# Scaling Governor
governors=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u)
if [[ $(echo "$governors" | wc -l) -eq 1 ]]; then
    governor_status="$governors"
else
    governor_status="mixed"
fi

# Isolated CPUs
isolated=$(cat /sys/devices/system/cpu/isolated 2>/dev/null)
[[ -z "$isolated" ]] && isolated="None"

# --- Output ---

echo "TurboBoost: $tb_status"
echo "Scaling Governor: $governor_status"
echo "Hyper-Threading (SMT): $ht_status"
echo "C-States: $c_status"
echo "ASLR: $aslr_status"
echo "NTP Syncing: $ntp_status"
echo "Isolated Cores: $isolated"