#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# Run from the repository root.
cd "$(dirname "${BASH_SOURCE[0]}")"

suites=(dacapo dacapo_con_scala renaissance polyBenchC parsec)
options=(
    base c_states heap hyper_threading pinned pinned_hyper_threading
    process_priority scaling_governors turbo_boost
    turbo_boost_scaling_governors turbo_boost_scaling_governors_c_states
)

# Process all measurements.
echo "[1/3] Regenerating processed summaries"
for suite in "${suites[@]}"; do
    bash "analysis_scripts/process_results_scripts/$suite/process_benchmarks.sh"
done

# Calculate iteration stability for base experiments.
echo "[2/3] Regenerating iteration stability files"
for suite in "${suites[@]}"; do
    for config_dir in results/"$suite"/*/*; do
        output_dir="stability_per_iterations_results/${config_dir#results/}"
        for experiment_dir in "$config_dir"/base/*; do
            [[ -d "$experiment_dir" ]] || continue
            mkdir -p "$output_dir"
            python3 "analysis_scripts/process_results_scripts/$suite/stability_per_iterations.py" \
                "$experiment_dir" "$output_dir/${experiment_dir##*/}_stabilities.json"
        done
    done
done

# Calculate Wilcoxon reports for every setting.
echo "[3/3] Regenerating Wilcoxon reports"
for option in "${options[@]}"; do
    python3 analysis_scripts/statistics_scripts/calculate_wilcoxon.py "$option"
done

echo "Regeneration complete."
