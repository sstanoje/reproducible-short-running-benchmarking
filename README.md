# Reproducible Short-Running Benchmarking

## Overview

This repository contains the artifacts accompanying the paper **Practical Benchmarking Configurations for Reproducible Execution-Time Measurements of CI/CD-Style Workloads**, accepted for publication in *ACM Transactions on Software Engineering and Methodology (TOSEM)*.

The repository provides system configuration scripts, benchmark execution scripts, experimental results, and statistical analysis outputs used in the evaluation. Its purpose is to support reproduction and further evaluation of the benchmarking configurations and results presented in the paper.

## Repository Structure

The repository is organized as follows:

- `setup_system_scripts/` — scripts used to configure the system for the evaluated benchmarking configurations.
- `run_benchmarks_scripts/` — scripts used to execute the benchmarks and collect execution-time measurements.
- `results/` — experimental results collected during the evaluation.
- `wilcoxon_test_results/` — results of the Wilcoxon statistical tests reported in the paper.
- `descriptions/` — descriptions of the evaluated benchmarks and benchmarking configurations.

## Requirements

The provided system-configuration scripts currently support **Linux systems with Intel processors**. Root privileges are required because the scripts modify CPU, kernel, memory, and boot configuration settings.

The scripts rely on standard Linux utilities together with:

- `numactl`
- `taskset`
- `jq`
- `zip`
- `rsync`
- GNU `time`

The experiments reported in the paper were performed using the following benchmark and toolchain versions. These are the versions used to obtain the published results; other versions were not evaluated.

- Oracle GraalVM: `25-dev+37.1` (Java `25+37-LTS`)
- DaCapo: `23.11-MR2-chopin`
- DaCapo con Scala: `0.1.0-SNAPSHOT`
- Renaissance: `0.16.0`
- PolyBench/C: `4.2.1-beta`
- PARSEC: `3.0`
- GCC/G++: `9.4.0`

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

## Running the Benchmarks

Benchmark execution scripts are provided in `run_benchmarks_scripts/`. There is a separate directory for each benchmark suite, containing a dedicated execution script. The corresponding script should be used to run benchmarks from that suite. All scripts follow the same general command-line interface:

```
sudo ./run_benchmarks.sh <executables_directory> <iterations> <results_directory> [OPTIONS]
```

The positional arguments are:

- `<executables_directory>` — directory containing the benchmark suite executables.
- `<iterations>` — number of iterations for each benchmark.
- `<results_directory>` — directory in which the collected measurements and execution metadata, including the system configuration and executed commands, are stored.

The commonly supported options are:

- `-m, --mode` — selects the benchmarking configuration.
- `-c, --core` — selects the isolated CPU core for the R configuration. If omitted, core `3` is used.

The available modes are `d` for the Default configuration, `r` for the Recommended configuration, and, for benchmark suites supporting multi-threaded execution, `mtr` for the Multi-Threaded Recommended configuration.

After successful execution, the results directory is packaged into `<results_directory>.zip`. The archive contains the benchmark measurements, `config.json`, and `run_commands.txt`.

### Examples

Default configuration:

```
sudo ./run_benchmarks.sh /path/to/executables 105 results_default -m d
```


Recommended configuration using isolated core `3`:

```
sudo ./run_benchmarks.sh /path/to/executables 105 results_recommended -m r -c 3
```


Multi-Threaded Recommended configuration, for suites supporting multi-threaded execution:

```
sudo ./run_benchmarks.sh /path/to/executables 105 results_mtr -m mtr
```

## Benchmark-Specific Notes

### DaCapo

Before running DaCapo benchmarks, the following benchmark-specific paths in the execution script must be configured manually:

- `PATH_TO_HOME` — home directory used by benchmarks that access files or resources relative to the user home directory.
- `PATH_TO_LABS_JDK` — path to the LabsJDK installation used during the experiments. This is required by benchmarks that access the Java runtime installation during execution.

These paths are intentionally not inferred automatically because they depend on the local benchmark build and runtime environment.

### PARSEC

The PARSEC runner uses additional benchmark input files provided in `helper_files.zip` alongside the execution script. These files correspond to the PARSEC `3.0` version used in the experiments reported in the paper. The archive contains the benchmark-specific inputs required by the runner.

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

For each environment, results are further divided according to the evaluated benchmarking configuration:

- `default_configuration_results/`
- `recommended_configuration_results/`
- `mt_recommended_configuration_results/`

Within these directories, `base/` contains measurements for the corresponding complete configuration, while the remaining directories contain measurements obtained when evaluating individual system settings or selected combinations of settings.

Each individual experiment contains execution-time measurements for the corresponding benchmarks together with a `config.json` file describing the system configuration and a `commands.txt` file containing the executed benchmark commands.

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

Individual benchmark suites and configurations can be reproduced independently. As an indication of the expected execution time, running all benchmarks of a suite for 105 iterations under the Recommended configuration on the idle UMA server takes approximately:

- DaCapo — 3.5 hours
- DaCapo con Scala — 0.6 hours
- Renaissance — 1.7 hours
- PolyBench/C — 4.0 hours
- PARSEC — 2.5 hours

Running all five suites once under this configuration takes approximately **12.3 hours** in total.

These values are approximate and depend on the hardware and system environment used for reproduction.