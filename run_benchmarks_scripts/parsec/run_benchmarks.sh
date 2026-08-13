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
THREADS="$(grep -c processor /proc/cpuinfo)"

show_help() {
    echo "Usage: sudo ./run_benchmarks.sh <executables_directory> <iterations> <results_directory> [OPTIONS]"
    echo "Options:"
    echo "  -m, --mode [d|r|mtr] Select run mode:"
    echo "                         d, default:          Default benchmark execution"
    echo "                         r, recommended:      Recommended benchmark execution"
    echo "                         mtr, mt_recommended: Multi-threaded recommended benchmark execution"
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
                mtr|mt_recommended) MODE="mt_recommended" ;; # Updated shorthand to mtr
                *) echo "Invalid mode. Use d/default, r/recommended, or mtr/mt_recommended."; exit 1 ;;
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
    "mt_recommended")
        echo "Mode: MT_RECOMMENDED (Multi-Threaded Tuned)"
        ADDITIONAL_COMMAND="numactl --cpunodebind=0 --membind=0 nice -n -20"
        ;;
    "default")
        echo "Mode: DEFAULT"
        ADDITIONAL_COMMAND=""
        ;;
esac

copy_inputs() {
    if [[ ! -f "$SRC_ZIP" ]]; then
        echo "ERROR: Missing helper archive: $SRC_ZIP" >&2
        exit 1
    fi

    INPUT_TMP_DIR=$(mktemp -d)
    unzip -q "$SRC_ZIP" -d "$INPUT_TMP_DIR"

    # Support archives containing either the files directly
    # or a top-level directory named after the benchmark
    if [[ -d "$INPUT_TMP_DIR/$BENCH" ]]; then
        INPUT_SRC_DIR="$INPUT_TMP_DIR/$BENCH"
    else
        INPUT_SRC_DIR="$INPUT_TMP_DIR"
    fi

    mapfile -t TO_COPY < <(
        find "$INPUT_SRC_DIR" -mindepth 1 -maxdepth 1 ! -name '*.tar' -printf '%f\n' | sort
    )

    for name in "${TO_COPY[@]:-}"; do
        rsync -a --quiet -- "$INPUT_SRC_DIR/$name" ./
    done
}

cleanup_inputs() {
    for name in "${TO_COPY[@]:-}"; do
        rm -rf -- "$name"
    done

    rm -rf -- "$INPUT_TMP_DIR"
}

build_cmd() {
  case "$BENCH" in
    blackscholes)
      CMD=( $ADDITIONAL_COMMAND "./blackscholes" "$THREADS" "in_64K.txt" "prices.txt" )
      ;;
    bodytrack)
      CMD=( $ADDITIONAL_COMMAND "./bodytrack" "sequenceB_4" "4" "4" "4000" "5" "0" "$THREADS" )
      ;;
    facesim)
      CMD=( $ADDITIONAL_COMMAND "./facesim" "-timing" "-threads" "$THREADS" )
      ;;
    ferret)
      CMD=( $ADDITIONAL_COMMAND "./ferret" "corel" "lsh" "queries" "10" "20" "$THREADS" "output.txt" )
      ;;
    fluidanimate)
      CMD=( $ADDITIONAL_COMMAND "./fluidanimate" "$THREADS" "5" "in_300K.fluid" "out.fluid" )
      ;;
    freqmine)
      CMD=( env OMP_NUM_THREADS="$THREADS" $ADDITIONAL_COMMAND "./freqmine" "kosarak_990k.dat" "790" )
      ;;
    swaptions)
      CMD=( $ADDITIONAL_COMMAND "./swaptions" "-ns" "64" "-sm" "40000" "-nt" "$THREADS" )
      ;;
    vips)
      CMD=( env IM_CONCURRENCY="$THREADS" $ADDITIONAL_COMMAND ./vips im_benchmark bigben_2662x5500.v output.v )
      ;;
    *)
      echo "Unsupported benchmark: $BENCH" >&2
      exit 1
      ;;
  esac
}

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
    if [[ -f "$file" && -x "$file" && "$file" != *.sh && "$file" != *.py ]]; then
        BENCH=$file
        SRC_ZIP="$SCRIPT_DIR/helper_files/${BENCH}.zip"
        output_file="$RESULT_DIR/${BENCH}.txt"
        : > "$output_file"

        # Stage inputs
        TO_COPY=()
        copy_inputs

        # Memory cleanup for recommended modes (recommended and mt_recommended)
        if [[ "$MODE" != "default" ]]; then
            echo "3" | sudo tee /proc/sys/vm/drop_caches > /dev/null
            sync
        fi

        echo "Starting $BENCH..."

        for ((i=1; i<=ITERATIONS; i++)); do
            build_cmd
            tmp=$(mktemp)

            # Use /usr/bin/time to capture wall clock time in seconds
            if /usr/bin/time -f "%e" -o "$tmp" -- "${CMD[@]}" >/dev/null 2>&1; then
              secs=$(cat "$tmp")
              # Convert seconds to milliseconds (msec)
              awk -v s="$secs" 'BEGIN{printf("%.0f msec\n", s*1000)}' >> "$output_file"
            else
              echo "-1" >> "$output_file"
            fi
            rm -f -- "$tmp"
        done

        echo "${CMD[@]}" >> "$RESULT_DIR/run_commands.txt"
        cleanup_inputs
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