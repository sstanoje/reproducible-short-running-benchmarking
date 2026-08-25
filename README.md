# Reproducible Short-Running Benchmarking

## Overview

This repository contains the artifacts accompanying the paper **Practical Benchmarking Configurations for Reproducible Execution-Time Measurements of CI/CD-Style Workloads**, published in *ACM Transactions on Software Engineering and Methodology (TOSEM)*. DOI: [10.1145/3838807](https://doi.org/10.1145/3838807).

The repository provides system configuration scripts, benchmark execution scripts, experimental results, and statistical analysis outputs used in the evaluation. Its purpose is to support reproduction and further evaluation of the benchmarking configurations and results presented in the paper.

## Repository Structure

The repository is organized as follows:

- `setup_system_scripts/` — scripts used to configure the recommended (R) and multi-threaded recommended (MTR) baseline configurations and to generate the background stress workload used in the busy-server experiments.
- `run_benchmarks_scripts/` — scripts used to execute the benchmarks and collect execution-time measurements.
- `results/` — experimental results collected during the evaluation.
- `wilcoxon_test_results/` — results of the Wilcoxon statistical tests reported in the paper.
- `analysis_scripts/` — scripts used to process the experimental measurements and reproduce the reported statistical analyses.
- `descriptions/` — descriptions of the evaluated benchmarks and benchmarking configurations.

## Requirements

The provided system-configuration scripts currently support **GRUB-based Linux systems with Intel processors**. Root privileges are required because the scripts modify CPU, kernel, memory, and boot configuration settings.

The scripts rely on standard Linux utilities together with:

- `numactl`
- `taskset`
- `jq`
- `zip`
- `unzip`
- `stress`
- `rsync`
- GNU `time`

The experiments reported in the paper were performed using the following benchmark and toolchain versions. These are the versions used to obtain the published results; other versions were not evaluated. The Java and Scala benchmark versions listed below are the versions provided by the Oracle GraalVM version used in our experiments.

- Oracle GraalVM: `25-dev+37.1` (Java `25+37-LTS`)
- DaCapo: `23.11-MR2-chopin`
- DaCapo con Scala: `0.1.0-SNAPSHOT`
- Renaissance: `0.16.0`
- PolyBench/C: `4.2.1-beta`
- PARSEC: `3.0-beta-20150206`
- GCC/G++: `9.4.0`

The analysis scripts additionally require:

- Python 3 (used version: Python 3.8.10)
- NumPy (used version: NumPy 1.22.3)
- SciPy (used version: SciPy 1.8.0)

## Preparing the Benchmarks

The benchmark runners expect prebuilt executables.

### Java and Scala Benchmarks

DaCapo, DaCapo con Scala, and Renaissance benchmarks were compiled to native executables using Oracle GraalVM `25-dev+37.1` with Java/LabsJDK `25+37-LTS`, using Native Image Enterprise Edition with profile-guided optimization (PGO).

Before building the benchmarks, set `JAVA_HOME` to the LabsJDK installation used for the build:

```
export JAVA_HOME=<path_to_LabsJDK>
```

Then, from the `graal-enterprise/vm-enterprise/` directory of the GraalVM Enterprise Edition source tree, build the Native Image component:

```
mx --env ni-ee build
```

After the build completes, an individual benchmark can be compiled using:

```
mx --env ni-ee benchmark <benchmark_suite>-native-image:<benchmark> -- --jvm=native-image --jvm-config=pgo-ee -Dnative-image.benchmark.stages=agent,instrument-image,instrument-run,image
```

The GraalVM benchmark-suite identifiers are `dacapo`, `scala_dacapo`, and `renaissance` for DaCapo, DaCapo con Scala, and Renaissance, respectively.

The Native Image benchmark workflow performed the agent, instrumented-image, instrumented-run, and final image-build stages. The final benchmark execution stage was not part of executable preparation. This corresponds to the standard Native Image PGO workflow of building an instrumented executable, running it to collect profiling data, and rebuilding an optimized executable.

The generated Native Image executables should be renamed to the corresponding benchmark identifiers expected by the benchmark execution scripts before they are collected in the executables directory. For example, the generated `dacapo-23-11-mr2-chopin-fop-pgo-ee` executable should be copied or renamed as `fop`.

### PolyBench/C

PolyBench/C `4.2.1-beta` was compiled with GCC `9.4.0` using the `LARGE_DATASET` configuration. The benchmarks were compiled with `-O3`, `POLYBENCH_TIME`, and double precision.

For the UMA server and laptop, the executables were built using `-march=native`. For the NUMA server, they were built using `-march=haswell`.

From the root directory of the PolyBench/C source tree, create the output directory before compiling the benchmarks:

```
mkdir -p build/bin
```

The general compilation command was:

```
gcc -std=c11 -O3 <architecture-option> -fno-plt -D_POSIX_C_SOURCE=200112L -DPOLYBENCH_TIME -DLARGE_DATASET -I utilities <kernel_source> utilities/polybench.c -o build/bin/<executable_name> -lm
```

where `<architecture-option>` was `-march=native` for the UMA server and laptop, and `-march=haswell` for the NUMA server.

The `<kernel_source>` argument denotes the relative path to the corresponding PolyBench/C kernel source file. The `<executable_name>` should be derived from this source path by removing the leading `./` and the `.c` suffix and replacing directory separators with underscores. For example, `./linear-algebra/kernels/atax/atax.c` is compiled as `linear-algebra_kernels_atax_atax`.

### PARSEC

PARSEC `3.0-beta-20150206` was built using GCC/G++ `9.4.0` and the standard `gcc` build configuration. To reproduce the toolchain used in the experiments, the compiler paths in `config/gcc.bldconf` should be configured to use GCC/G++ `9.4.0`.

From the root directory of the PARSEC source tree, the benchmarks can be built using:

```
./bin/parsecmgmt -a build -p all -c gcc
```

Among the eight PARSEC benchmarks used in our evaluation, freqmine uses OpenMP, while the remaining seven use pthreads.

## System Setup

Before running benchmarks under the recommended configurations, the system must be configured using the scripts in `setup_system_scripts/`.

### Recommended Configuration (R)

1. Apply boot-time settings and select the isolated core.
2. Reboot the machine.
3. Apply runtime settings.
4. Run the benchmark script using the same isolated core.

The R configuration uses an isolated CPU core. If no core is specified, core `3` is used by default.

Apply the boot-time settings:

```
sudo ./setup_system_scripts/setup_boot_settings.sh -m r -c 3
```

Reboot the machine:

```
sudo reboot
```

After rebooting, apply the runtime settings:

```
sudo ./setup_system_scripts/setup_run_settings.sh -m r
```

**The same isolated core must be specified when running the benchmarks.**

### Multi-Threaded Recommended Configuration (MTR)

1. Apply boot-time settings.
2. Reboot the machine.
3. Apply runtime settings.
4. Run the benchmark script.

Apply the boot-time settings:

```
sudo ./setup_system_scripts/setup_boot_settings.sh -m mtr
```

Reboot the machine:

```
sudo reboot
```

After rebooting, apply the runtime settings:

```
sudo ./setup_system_scripts/setup_run_settings.sh -m mtr
```

### Default Configuration (D)

No setup scripts are applied. Benchmarks are executed using the system's default configuration.

### Restoring the System

To restore the system after benchmarking, remove the benchmarking-specific kernel options from `GRUB_CMDLINE_LINUX` in `/etc/default/grub`, update the GRUB configuration, and reboot. For Ubuntu and other systems providing `update-grub`, use:

```
sudo update-grub
sudo reboot
```

On Arch Linux use:

```
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

The benchmarking-specific kernel options are `processor.max_cstate=0`, `intel_idle.max_cstate=0`, and, for the R configuration, the `isolcpus`, `nohz_full`, `rcu_nocbs`, and `irqaffinity` options.

After rebooting, re-enable network time synchronization:

```
sudo timedatectl set-ntp true
```

The system should be restored to its default state before switching between the R, MTR, and D baseline configurations, so that boot-time and runtime settings from a previous benchmarking configuration do not remain active.

## Running the Benchmarks

Benchmark execution scripts are provided in `run_benchmarks_scripts/`. There is a separate directory for each benchmark suite, containing a dedicated execution script. The corresponding script should be used to run benchmarks from that suite. All scripts follow the same general command-line interface:

```
sudo ./run_benchmarks.sh <executables_directory> <iterations> <results_directory> [OPTIONS]
```

The positional arguments are:

- `<executables_directory>` — directory containing the benchmark suite executables.
- `<iterations>` — number of benchmark iterations for Java and Scala benchmarks or complete benchmark executions for C and C++ benchmarks.
- `<results_directory>` — directory in which the collected measurements and execution metadata, including the system configuration and executed commands, are stored.

The commonly supported options are:

- `-m, --mode` — selects the benchmarking configuration.
- `-c, --core` — selects the isolated CPU core for the R configuration. If omitted, core `3` is used.
- `-s, --stress` — selects whether the benchmark is executed with the background stress workload. Supported values are `stress` and `no_stress`. If omitted, `no_stress` is used.

The available modes are `d` for the Default configuration, `r` for the Recommended configuration, and, for benchmark suites supporting multi-threaded execution, `mtr` for the Multi-Threaded Recommended configuration.

The background stress workload is intended for reproducing the busy-server experiments. It is implemented by `setup_system_scripts/run_stress_random.sh` and alternates between 2 seconds of CPU stress using a number of workers equal to the number of logical CPUs reported by `nproc` and 2 seconds without additional load. The selected stress mode is recorded in `config.json`. Background stress was applied only in the server experiments. No additional synthetic stress workload was used on the laptop because it was evaluated under its existing background system load.

After benchmark execution completes, the results directory is packaged into `<results_directory>.zip`. The archive contains the benchmark measurements, `config.json`, and `commands.txt`.

### Examples

Default configuration:

```
sudo ./run_benchmarks.sh /path/to/executables 105 results_default -m d
```

Recommended configuration using isolated core `3`:

```
sudo ./run_benchmarks.sh /path/to/executables 105 results_recommended -m r -c 3
```

Recommended configuration with the background stress workload:

```
sudo ./run_benchmarks.sh /path/to/executables 105 results_recommended_busy -m r -c 3 -s stress
```

Multi-Threaded Recommended configuration, for suites supporting multi-threaded execution:

```
sudo ./run_benchmarks.sh /path/to/executables 105 results_mtr -m mtr
```

## Benchmark-Specific Notes

### DaCapo

Before running DaCapo benchmarks, the following benchmark-specific paths in the execution script must be configured manually:

- `PATH_TO_HOME` — home directory used by benchmarks that access files or resources relative to the user home directory.
- `PATH_TO_LABS_JDK` — path to the LabsJDK installation used during the experiments. This is required by the `fop` benchmark, which accesses the Java runtime installation during execution.

These paths are intentionally not inferred automatically because they depend on the local benchmark build and runtime environment.

### PARSEC

The PARSEC runner uses additional benchmark input files provided as benchmark-specific archives in the `helper_files/` directory alongside the execution script. These files correspond to PARSEC `3.0`, the version used in the experiments reported in the paper.

## Experimental Results

The `results/` directory contains the experimental measurements used in the paper. Results are first organized by benchmark suite:

- `dacapo/`
- `dacapo_con_scala/`
- `renaissance/`
- `polyBenchC/`
- `parsec/`

Within each benchmark suite, results are organized by evaluation environment:

- `idle_UMA_server/`
- `busy_UMA_server/`
- `idle_NUMA_server/`
- `busy_NUMA_server/`
- `laptop/`

Depending on the benchmark suite, results are further divided according to the applicable benchmarking configurations:

- `default_configuration_results/`
- `recommended_configuration_results/`
- `mt_recommended_configuration_results/`

Within these directories, `base/` contains measurements for the corresponding complete configuration, while the remaining directories contain measurements obtained when evaluating individual system settings or selected combinations of settings.

Each individual experiment contains execution-time measurements for the corresponding benchmarks together with a `config.json` file describing the system configuration and a `commands.txt` file containing the executed benchmark commands.

## Reproducing the Reported Statistics

The scripts in `analysis_scripts/` can be used to regenerate the processed benchmark results and Wilcoxon statistical reports from the experimental measurements stored in `results/`.

### Processing the Experimental Results

Each benchmark suite has a dedicated processing script under `analysis_scripts/process_results_scripts/`. The scripts discard the first five warmup repetitions and generate JSON summaries containing the statistics used in the analysis, including median execution time and RMAD.

From the repository root, run:

```
./analysis_scripts/process_results_scripts/<benchmark_suite>/process_benchmarks.sh
```

For example:

```
./analysis_scripts/process_results_scripts/dacapo/process_benchmarks.sh
```

### Wilcoxon Statistical Tests

The Wilcoxon base reports can be regenerated using:

```
python3 analysis_scripts/statistics_scripts/calculate_wilcoxon.py base
```

The same script is used for the individual system settings and evaluated combinations. For example:

```
python3 analysis_scripts/statistics_scripts/calculate_wilcoxon.py turbo_boost
```

The supported options are:

- `base`
- `c_states`
- `heap`
- `hyper_threading`
- `pinned`
- `pinned_hyper_threading`
- `process_priority`
- `scaling_governors`
- `turbo_boost`
- `turbo_boost_scaling_governors`
- `turbo_boost_scaling_governors_c_states`

The generated reports are written to the corresponding directories under `wilcoxon_test_results/`.

The Wilcoxon analysis preserves the benchmark grouping used to obtain the reported results. In particular, DaCapo con Scala is excluded from the base multi-threaded Wilcoxon analysis because it was inadvertently omitted from the original analysis used to produce the reported base results. It is included in the remaining multi-threaded analyses.

## Statistical Analysis

The `wilcoxon_test_results/` directory contains the results of the Wilcoxon statistical tests reported in the paper.

The results are organized according to the evaluated system setting or combination of settings, including:

- `base/`
- `c_states/`
- `heap/`
- `hyper_threading/`
- `pinned/`
- `pinned_hyper_threading/`
- `process_priority/`
- `scaling_governors/`
- `turbo_boost/`
- `turbo_boost_scaling_governors/`
- `turbo_boost_scaling_governors_c_states/`

For each evaluated setting, separate JSON reports are provided for execution-time stability measured using RMAD, and execution time. Where applicable, separate reports are provided for single-threaded and multi-threaded executions.

Each report contains the corresponding statistical comparison, effect, p-value, significance result, and a textual summary of the comparison.

## Reproduction Scope

The complete experimental evaluation reported in the paper required more than **1069 hours of aggregate benchmark execution time**. Reproducing the entire experimental campaign therefore requires substantial computational resources and time.

Individual benchmark suites and configurations can be reproduced independently. As an indication of the expected execution time, running all benchmarks of a suite for 105 repetitions under the Recommended configuration on the idle UMA server takes approximately:

- DaCapo — 3.5 hours
- DaCapo con Scala — 0.6 hours
- Renaissance — 1.7 hours
- PolyBench/C — 4.0 hours
- PARSEC — 2.5 hours

Running all five suites once under this configuration takes approximately **12.3 hours** in total.

These values are approximate and depend on the hardware and system environment used for reproduction.