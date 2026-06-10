#!/bin/bash

# --- Path Configuration ---
# Update this variable to the directory containing your helper scripts
SCRIPTS_PATH="/home/strahinja/Desktop/scripts"

# Default values
MODE="default"
ISOLATED_CORE=3
ITERATIONS=$1
RESULT_DIR=$2
ADDITIONAL_COMMAND=""
THREADS="$(grep -c processor /proc/cpuinfo)"

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
case "$MODE" in
    "recommended")
        echo "Mode: RECOMMENDED"
        sudo "$SCRIPTS_PATH/setup_system.sh" --all "$ISOLATED_CORE"
        ADDITIONAL_COMMAND="numactl --cpunodebind=0 --membind=0 taskset -c $ISOLATED_CORE nice -n -20"
        ;;
    "mt_recommended")
        echo "Mode: MT_RECOMMENDED"
        sudo "$SCRIPTS_PATH/setup_system.sh" --mt-rec
        ADDITIONAL_COMMAND="numactl --cpunodebind=0 --membind=0 nice -n -20"
        ;;
    "default")
        echo "Mode: DEFAULT"
        ADDITIONAL_COMMAND=""
        ;;
esac

copy_inputs() {
  if [[ ! -d "$SRC_DIR" ]]; then
    echo "ERROR: Missing directory: $SRC_DIR" >&2
    exit 1
  fi
  mapfile -t TO_COPY < <(find "$SRC_DIR" -mindepth 1 -maxdepth 1 ! -name '*.tar' -printf '%f\n' | sort)
  for name in "${TO_COPY[@]:-}"; do
    rsync -a --quiet -- "$SRC_DIR/$name" ./
  done
}

cleanup_inputs() {
  for name in "${TO_COPY[@]:-}"; do
    rm -rf -- "$name"
  done
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
    raytrace)
      CMD=( $ADDITIONAL_COMMAND "./raytrace" "happy_buddha.obj" "-automove" "-nthreads" "$THREADS" "-frames" "3" "-res" "1920" "1080" )
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
        key=$(echo "$key" | xargs);
        value=$(echo "$value" | xargs)
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
for file in *; do
    # Only run if it's a file AND has the executable bit set
    if [[ -f "$file" && -x "$file" && "$file" != *.sh && "$file" != *.py ]]; then
        BENCH=$file
        SRC_DIR="../helper_files/$BENCH"
        output_file="${BENCH}.txt"
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

        echo "${CMD[@]}" >> run_commands.txt
        cleanup_inputs
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