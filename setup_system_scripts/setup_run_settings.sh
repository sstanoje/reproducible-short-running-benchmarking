#!/bin/bash

# Applies runtime system settings after reboot.
# These settings do not require another reboot.

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

MODE=""

show_help() {
    echo "Usage: sudo ./setup_run_settings.sh -m <r|mtr>"
    echo ""
    echo "Options:"
    echo "  -m, --mode <r|mtr>    Benchmarking configuration"
    echo "  -h, --help            Show this help message"
}

tune_performance() {
    echo "--- Setting performance mode ---"

    # Disable Intel Turbo Boost.
    if [ -f "/sys/devices/system/cpu/intel_pstate/no_turbo" ]; then
        echo "1" > /sys/devices/system/cpu/intel_pstate/no_turbo
    else
        echo "Warning: Intel Turbo Boost control was not found."
    fi

    # Set the scaling governor to performance on all available CPUs.
    for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if [ -f "$governor" ]; then
            echo "performance" > "$governor"
        fi
    done
}

disable_swap() {
    echo "--- Disabling swap ---"
    swapoff -a
}

disable_aslr() {
    echo "--- Disabling ASLR ---"
    echo "0" > /proc/sys/kernel/randomize_va_space
}

disable_hyperthreading() {
    echo "--- Disabling Hyper-Threading ---"

    if [ -f "/sys/devices/system/cpu/smt/control" ]; then
        echo off > /sys/devices/system/cpu/smt/control
    else
        echo "Warning: SMT control was not found."
    fi
}

stop_ntp() {
    echo "--- Stopping NTP synchronization ---"
    systemctl stop systemd-timesyncd 2>/dev/null || \
        service ntp stop 2>/dev/null
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

case "$MODE" in
    r)
        echo "--- Applying runtime settings for R ---"
        tune_performance
        disable_swap
        disable_aslr
        disable_hyperthreading
        stop_ntp
        ;;
    mtr)
        echo "--- Applying runtime settings for MTR ---"
        tune_performance
        disable_swap
        disable_aslr
        stop_ntp
        ;;
    *)
        echo "Invalid or missing mode."
        show_help
        exit 1
        ;;
esac

echo "--- Runtime configuration complete ---"