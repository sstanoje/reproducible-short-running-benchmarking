#!/bin/bash

# Applies settings that require changing the kernel command line.
# A reboot is required after running this script.

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

MODE=""
ISOLATED_CORE=3

show_help() {
    echo "Usage: sudo ./setup_boot_settings.sh -m <r|mtr> [-c CORE_NUMBER]"
    echo ""
    echo "Options:"
    echo "  -m, --mode <r|mtr>    Benchmarking configuration"
    echo "  -c, --core <number>   Core to isolate in R mode (default: 3)"
    echo "  -h, --help            Show this help message"
}

apply_grub_changes() {
    local opts="$1"
    local grub_file="/etc/default/grub"

    sed -i \
        "s|^\(GRUB_CMDLINE_LINUX=\".*\)\"$|\1 $opts\"|" \
        "$grub_file"

    if command -v update-grub > /dev/null; then
        update-grub
    elif command -v grub-mkconfig > /dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
    elif command -v grub2-mkconfig > /dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        echo "ERROR: Could not find a supported GRUB configuration command."
        exit 1
    fi

    echo
    echo "GRUB updated with:"
    echo "$opts"
    echo
    echo "REBOOT REQUIRED."
}

# Disable deeper C-states.
cstate_options() {
    echo "processor.max_cstate=0 intel_idle.max_cstate=0"
}

# Generate kernel parameters for isolating one logical CPU.
isolation_options() {
    local target_core=$1
    local max_idx=$(($(nproc) - 1))
    local affinity=""

    if [ "$target_core" -eq 0 ]; then
        affinity="1-$max_idx"
    elif [ "$target_core" -eq "$max_idx" ]; then
        affinity="0-$((max_idx - 1))"
    else
        affinity="0-$((target_core - 1)),$((target_core + 1))-$max_idx"
    fi

    echo "isolcpus=domain,managed_irq,$target_core nohz_full=$target_core rcu_nocbs=$target_core irqaffinity=$affinity"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -c|--core)
            ISOLATED_CORE="$2"
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
        echo "--- Configuring boot settings for R ---"
        OPTIONS="$(cstate_options) $(isolation_options "$ISOLATED_CORE")"
        apply_grub_changes "$OPTIONS"
        ;;
    mtr)
        echo "--- Configuring boot settings for MTR ---"
        OPTIONS="$(cstate_options)"
        apply_grub_changes "$OPTIONS"
        ;;
    *)
        echo "Invalid or missing mode."
        show_help
        exit 1
        ;;
esac
