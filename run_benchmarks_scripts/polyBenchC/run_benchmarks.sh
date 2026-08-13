#!/bin/bash

# --- Path Configuration ---
# Resolve the helper-script directory relative to this script inside the repo hierarchy
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPTS_DIR="$SCRIPT_DIR/../../setup_system_scripts"

# Default values
MODE="default"
ISOLATED_CORE=3
START_DIR=$(pwd)
EXECUTABLES_DIR=$1
ITERATIONS=$2
RESULT_DIR=$3
ADDITIONAL_COMMAND=""

show_help() {
    echo "Usage: sudo ./run_benchmarks.sh <executables_directory> <iterations> <results_directory> [OPTIONS]"
    echo "Options:"
    echo "  -m, --mode [d|r] Select run mode:"
    echo "                         d, default:          Default benchmark execution"
    echo "                         r, recommended:      Recommended benchmark execution"
    echo "  -c, --core [num]     Specify core for 'r' mode (default: 3)"
    echo "  -h, --help           Show this help"
}

# --- Check Arguments ---
if [ $# -lt 3 ]; then
    show_help
    exit 1
fi

# Move past executables_directory, iterations, and results_directory
shift 3

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--mode)
            case $2 in
                d|default)        MODE="default" ;;
                r|recommended)    MODE="recommended" ;;
                *) echo "Invalid mode. Use d/default or r/recommended."; exit 1 ;;
            esac
            shift ;;
        -c|--core) ISOLATED_CORE="$2"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [[ "$RESULT_DIR" != /* ]]; then
    RESULT_DIR="$START_DIR/$RESULT_DIR"
fi

# --- Configuration Logic ---
case "$MODE" in
    "recommended")
        echo "Mode: RECOMMENDED"
        ADDITIONAL_COMMAND="numactl --cpunodebind=0 --membind=0 taskset -c $ISOLATED_CORE nice -n -20"
        ;;
    "default")
        echo "Mode: DEFAULT"
        ADDITIONAL_COMMAND=""
        ;;
esac

print_configuration() {
    declare -A data_map
    ordered_keys=()
    while IFS=':' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        key_stored=${key// /_}
        data_map["$key_stored"]="$value"
        ordered_keys+=("$key_stored")
    done < <("$SETUP_SCRIPTS_DIR/print_system_setup.sh")

    json="{"
    first=1
    for k in "${ordered_keys[@]}"; do
        v=${data_map[$k]}
        k_printed=${k//_/ }
        [[ $first -eq 0 ]] && json="$json,"
        v_escaped=$(echo "$v" | sed 's/"/\\"/g')
        json="$json\"$k_printed\":\"$v_escaped\""
        first=0
    done
    json="$json}"
    echo -e "$json" | jq . > "$RESULT_DIR/config.json"
}

if [[ ! -d "$EXECUTABLES_DIR" ]]; then
    echo "Executables directory does not exist: $EXECUTABLES_DIR"
    exit 1
fi

if [[ -e "$RESULT_DIR" || -e "${RESULT_DIR}.zip" ]]; then
    echo "Result path already exists: $RESULT_DIR or ${RESULT_DIR}.zip"
    exit 1
fi
mkdir -p "$RESULT_DIR"

cd "$EXECUTABLES_DIR" || exit 1
print_configuration
: > "$RESULT_DIR/run_commands.txt"

# --- Main Benchmark Loop ---
for file in *; do
    # Only run if it's a file AND has the executable bit set
    if [[ -f "$file" && -x "$file" ]]; then

        # Memory cleanup for recommended mode
        if [[ "$MODE" != "default" ]]; then
            echo "3" | sudo tee /proc/sys/vm/drop_caches > /dev/null
            sync
        fi

        echo "Starting ${file}..."
        output_file="$RESULT_DIR/${file}.txt"

        # Execute iterations
        for i in $(seq 1 "$ITERATIONS"); do
            $ADDITIONAL_COMMAND ./"$file" >> "$output_file"
        done

        # --- In-line Rewrite Logic ---
        # PolyBench/C prints times in seconds; we convert to msec as per rewrite.py logic
        if [[ -f "$output_file" ]]; then
            tmp_file=$(mktemp)
            while read -r line; do
                new_line=""
                for word in $line; do
                    # If the word is a number (integer or float), multiply by 1000
                    if [[ "$word" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                        # Use awk for floating point math: seconds * 1000 = milliseconds
                        val_msec=$(awk "BEGIN {print $word * 1000}")
                        new_line="$new_line ${val_msec} msec"
                    else
                        new_line="$new_line $word"
                    fi
                done
                echo "$new_line" | xargs >> "$tmp_file"
            done < "$output_file"
            mv "$tmp_file" "$output_file"
        fi

        echo "$ADDITIONAL_COMMAND ./$file" >> "$RESULT_DIR/run_commands.txt"
    fi
done

# --- Cleanup and Packaging ---
RESULT_PARENT=$(dirname "$RESULT_DIR")
RESULT_NAME=$(basename "$RESULT_DIR")

cd "$RESULT_PARENT" || exit 1

if zip -r "${RESULT_NAME}.zip" "$RESULT_NAME"; then
    rm -rf "$RESULT_NAME"
    echo "Done. Results saved in ${RESULT_PARENT}/${RESULT_NAME}.zip"
else
    echo "Error: Failed to create results archive. Original results were preserved."
    exit 1
fi