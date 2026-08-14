#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/../../../results/dacapo"

environments=(
    "idle_UMA_server"
    "busy_UMA_server"
    "idle_NUMA_server"
    "busy_NUMA_server"
    "laptop"
)

configurations=(
    "default_configuration_results"
    "recommended_configuration_results"
    "mt_recommended_configuration_results"
)

for environment in "${environments[@]}"; do
    for configuration in "${configurations[@]}"; do
        config_dir="$RESULTS_DIR/$environment/$configuration"

        # Some suites/environments may not contain every configuration
        [[ -d "$config_dir" ]] || continue

        for setting_dir in "$config_dir"/*; do
            [[ -d "$setting_dir" ]] || continue

            for experiment_dir in "$setting_dir"/*; do
                [[ -d "$experiment_dir" ]] || continue

                echo "Processing $experiment_dir"
                "$SCRIPT_DIR/process_file.py" "$experiment_dir" all
            done
        done
    done
done