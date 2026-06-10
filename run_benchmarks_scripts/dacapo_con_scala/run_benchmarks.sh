#!/bin/bash

# --- Path Configuration ---
SCRIPTS_PATH="/home/strahinja/Desktop/scripts"

# Default values
MODE="default"
ISOLATED_CORE=3
ITERATIONS=$1
RESULT_DIR=$2
ADDITIONAL_COMMAND=""
HEAP_SIZE=""

show_help() {
    echo "Usage: sudo ./run_benchmarks.sh [iterations] [results_directory] [OPTIONS]"
    echo "Options:"
    echo "  -m, --mode [d|r|mtr] Select run mode:"
    echo "                         d, default:        No tuning, no pinning"
    echo "                         r, recommended:    Full tuning (HT off, Isolated Core, C-States off)"
    echo "                         mtr, mt_recommended: MT tuning (HT on, No Isolation, C-States off)"
    echo "  -c, --core [num]     Specify core for 'r' mode (default: 3)"
    echo "  -h, --help           Show this help"
}

# --- Check Arguments ---
if [ $# -lt 2 ]; then
    show_help
    exit 1
fi

shift 2 # Move past iterations and directory

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--mode)
            case $2 in
                d|default)        MODE="default" ;;
                r|recommended)    MODE="recommended" ;;
                mtr|mt_recommended) MODE="mt_recommended" ;;
                *) echo "Invalid mode. Use d/default, r/recommended, or mtr/mt_recommended."; exit 1 ;;
            esac
            shift ;;
        -c|--core) ISOLATED_CORE="$2"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# --- Configuration Logic ---
# Merged from run_default.sh, run_recommended.sh, and run_mt_recommended.sh

case "$MODE" in
    "recommended")
        echo "Mode: RECOMMENDED"
        sudo "$SCRIPTS_PATH/setup_system.sh" --all "$ISOLATED_CORE"
        ADDITIONAL_COMMAND="numactl --cpunodebind=0 --membind=0 taskset -c $ISOLATED_CORE nice -n -20"
        HEAP_SIZE="-Xms16g -Xmx16g -Xmn8g"
        ;;
    "mt_recommended")
        echo "Mode: MT_RECOMMENDED"
        sudo "$SCRIPTS_PATH/setup_system.sh" --mt-rec
        ADDITIONAL_COMMAND="numactl --cpunodebind=0 --membind=0 nice -n -20"
        HEAP_SIZE="-Xms16g -Xmx16g -Xmn8g"
        ;;
    "default")
        echo "Mode: DEFAULT"
        ADDITIONAL_COMMAND=""
        HEAP_SIZE=""
        ;;
esac

print_configuration() {
    declare -A data_map
    ordered_keys=()
    while IFS=':' read -r key value; do
        key=$(echo "$key" | xargs); value=$(echo "$value" | xargs)
        key_stored=${key// /_}
        data_map["$key_stored"]="$value"
        ordered_keys+=("$key_stored")
    done < <("$SCRIPTS_PATH/print_system_setup.sh")

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
    echo -e "$json" | jq . > config.json
}

print_configuration
touch run_commands.txt

# --- Main Benchmark Loop ---
# This section merges the file filtering and specialized command flags from your 3 scripts

for file in *; do
    # Only run if it's a file AND has the executable bit set
    if [[ -f "$file" && -x "$file" ]]; then

        # Memory cleanup for recommended modes
        if [[ "$MODE" != "default" ]]; then
            echo "3" | sudo tee /proc/sys/vm/drop_caches > /dev/null
            sync
        fi

        echo "Starting ${file}..."

        # Build command
        CMD="$ADDITIONAL_COMMAND ./$file $file -n $ITERATIONS -s default --preserve $HEAP_SIZE"

        eval "$CMD" > "${file}.txt"
        echo "$CMD" >> run_commands.txt
    fi
done

# Cleanup and Packaging
mkdir -p "../$RESULT_DIR"
mv *.txt "../$RESULT_DIR/"
mv config.json "../$RESULT_DIR/"
mv run_commands.txt "../$RESULT_DIR/"

cd ..
zip -r "${RESULT_DIR}.zip" "$RESULT_DIR"
rm -rf "$RESULT_DIR"

echo "Done. Results saved in ${RESULT_DIR}.zip"