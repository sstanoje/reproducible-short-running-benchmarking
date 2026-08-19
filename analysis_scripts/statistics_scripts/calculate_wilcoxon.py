#!/usr/bin/env python3

import json
import statistics
import sys
import warnings
from pathlib import Path

from scipy.stats import wilcoxon


ROOT = Path(__file__).resolve().parents[2]
RESULTS_DIR = ROOT / "results"
OUTPUT_DIR = ROOT / "wilcoxon_test_results"

SUITES = {
    "single_threaded": {
        "managed languages": ["dacapo", "dacapo_con_scala", "renaissance"],
        "unmanaged languages": ["polyBenchC"],
    },
    "multi_threaded": {
        "managed languages": ["dacapo", "dacapo_con_scala", "renaissance"],
        "unmanaged languages": ["parsec"],
    },
}

ENVIRONMENTS = {
    "idle_UMA_server": "idle UMA server",
    "busy_UMA_server": "busy UMA server",
    "idle_NUMA_server": "idle NUMA server",
    "busy_NUMA_server": "busy NUMA server",
    "laptop": "laptop",
}

MACHINE_ORDER = {
    "single_threaded": [
        "idle UMA server", "busy UMA server", "idle NUMA server",
        "busy NUMA server", "laptop",
    ],
    "multi_threaded": [
        "idle UMA server", "busy UMA server", "laptop",
        "idle NUMA server", "busy NUMA server",
    ],
}

CONFIG_DIRS = {
    "recommended": "recommended_configuration_results",
    "mt_recommended": "mt_recommended_configuration_results",
    "default": "default_configuration_results",
}

ST_BENCHMARKS = {
    "fop", "luindex", "factorie", "kiama", "scalac", "scaladoc",
    "scalap", "scalariform", "scalaxb", "mnemonics", "scala-doku", "scala-kmeans",
    "datamining_correlation_correlation", "linear-algebra_blas_trmm_trmm",
    "linear-algebra_solvers_durbin_durbin", "stencils_adi_adi",
    "datamining_covariance_covariance", "linear-algebra_kernels_2mm_2mm",
    "linear-algebra_solvers_gramschmidt_gramschmidt", "stencils_fdtd-2d_fdtd-2d",
    "linear-algebra_blas_gemm_gemm", "linear-algebra_kernels_3mm_3mm",
    "linear-algebra_solvers_ludcmp_ludcmp", "stencils_heat-3d_heat-3d",
    "linear-algebra_blas_gemver_gemver", "linear-algebra_kernels_atax_atax",
    "linear-algebra_solvers_lu_lu", "stencils_jacobi-1d_jacobi-1d",
    "linear-algebra_blas_gesummv_gesummv", "linear-algebra_kernels_bicg_bicg",
    "linear-algebra_solvers_trisolv_trisolv", "stencils_jacobi-2d_jacobi-2d",
    "linear-algebra_blas_symm_symm", "linear-algebra_kernels_doitgen_doitgen",
    "medley_deriche_deriche", "stencils_seidel-2d_seidel-2d",
    "linear-algebra_blas_syr2k_syr2k", "linear-algebra_kernels_mvt_mvt",
    "medley_floyd-warshall_floyd-warshall", "linear-algebra_blas_syrk_syrk",
    "linear-algebra_solvers_cholesky_cholesky", "medley_nussinov_nussinov",
}

MT_BENCHMARKS = {
    "lusearch", "sunflow", "pmd", "xalan", "apparat", "tmt", "akka-uct",
    "finagle-http", "fj-kmeans", "future-genetic", "par-mnemonics", "philosophers",
    "reactors", "scrabble", "rx-scrabble", "scala-stm-bench7", "blackscholes",
    "bodytrack", "facesim", "ferret", "fluidanimate", "swaptions", "vips",
}

OPTION_DIRS = {
    "pinned": "pinning",
}

OPTION_LABELS = {
    "turbo_boost": {
        "recommended": "R+TurboBoost", "mt_recommended": "MTR+TurboBoost",
        "default": "D-TurboBoost",
    },
    "scaling_governors": {
        "recommended": "R+Powersave/Schedutil", "mt_recommended": "MTR+Powersave/Schedutil",
        "default": "D+Performance",
    },
    "c_states": {
        "recommended": "R+C0-9", "mt_recommended": "MTR+C0-9", "default": "D+C0",
    },
    "hyper_threading": {
        "recommended": "R+HTreading", "default": "D-HTreading",
    },
    "pinned": {
        "recommended": "R-Pinned", "default": "D+Pinned",
    },
    "process_priority": {
        "recommended": "R+PriorityDef", "mt_recommended": "MTR+PriorityDef",
        "default": "D+PriorityInc",
    },
    "heap": {
        "recommended": "R-FixedHeap", "mt_recommended": "MTR-FixedHeap",
        "default": "D+FixedHeap",
    },
    "turbo_boost_scaling_governors": {
        "recommended": "R+TurboBoost+Powersave/Schedutil",
        "mt_recommended": "MTR+TurboBoost+Powersave/Schedutil",
        "default": "D-TurboBoost+Performance",
    },
    "turbo_boost_scaling_governors_c_states": {
        "recommended": "R+TurboBoost+Powersave/Schedutil+C0-9",
        "mt_recommended": "MTR+TurboBoost+Powersave/Schedutil+C0-9",
        "default": "D-TurboBoost+Performance+C0",
    },
    "pinned_hyper_threading": {
        "default": "D+Pinned-HThreading",
    },
}

BASE_COMPARISONS = {
    "single_threaded": [("recommended", "default")],
    "multi_threaded": [
        ("recommended", "default"),
        ("recommended", "mt_recommended"),
        ("mt_recommended", "default"),
    ],
}


def load_data(kind, config, variant, exclude_scala=False):
    benchmarks = ST_BENCHMARKS if kind == "single_threaded" else MT_BENCHMARKS
    suites_by_language = SUITES[kind]

    # =====================================================================
    # IMPORTANT REPRODUCIBILITY NOTE
    #
    # DaCapo con Scala is part of the multi-threaded benchmark set, and
    # `apparat` and `tmt` are therefore kept in MT_BENCHMARKS above.
    #
    # However, the original BASE multi-threaded Wilcoxon scripts accidentally
    # omitted DaCapo con Scala. The published/stored base MT Wilcoxon results
    # were generated with that omission.
    #
    # To reproduce those published results exactly, DaCapo con Scala is
    # excluded ONLY from the base MT analysis. All modified-option MT analyses
    # include DaCapo con Scala normally.
    # =====================================================================
    if kind == "multi_threaded" and exclude_scala:
        suites_by_language = {
            **suites_by_language,
            "managed languages": ["dacapo", "renaissance"],
        }

    result = {
        language: {machine: {} for machine in MACHINE_ORDER[kind]}
        for language in suites_by_language
    }

    for language, suites in suites_by_language.items():
        for suite in suites:
            for environment, machine in ENVIRONMENTS.items():
                directory = RESULTS_DIR / suite / environment / CONFIG_DIRS[config] / variant

                summary_files = sorted(directory.glob("*.json"))

                if len(summary_files) > 1:
                    raise RuntimeError(f"Expected at most one processed JSON summary in {directory}, found {len(summary_files)}")

                for file_path in summary_files:
                    with file_path.open() as file:
                        for row in json.load(file):
                            benchmark = row["benchmark"]

                            if benchmark not in benchmarks:
                                continue

                            result[language][machine][(suite, benchmark)] = {
                                "time": row["median"],
                                "rmad": row["RMAD(%)"]
                            }
    return result


def percent_change(first, second):
    return ((first / second) - 1) * 100


def wilcoxon_summary(values):
    effect = statistics.median(values)

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        p = 1.0 if all(value == 0 for value in values) else wilcoxon(values, mode="approx").pvalue

    return {
        "effect": round(effect, 3),
        "p": float(p),
        "significant": "yes" if p < 0.05 else "no",
    }


def result_text(metric, effect, first, second):
    if metric == "median_time":
        winner = first if effect < 0 else second
        loser = second if effect < 0 else first
        return f"{winner} faster than {loser} by {abs(effect):.3f}%"

    winner = first if effect < 0 else second
    loser = second if effect < 0 else first
    return f"{winner} lower RMAD than {loser} by {abs(effect):.3f} pp"


def compare(first_data, second_data, first_label, second_label):
    keys = sorted(set(first_data) & set(second_data))
    if not keys:
        return None

    time = wilcoxon_summary([
        percent_change(first_data[key]["time"], second_data[key]["time"])
        for key in keys
    ])

    rmad = wilcoxon_summary([
        first_data[key]["rmad"] - second_data[key]["rmad"]
        for key in keys
    ])

    time["result"] = result_text("median_time", time["effect"], first_label, second_label)
    rmad["result"] = result_text("rmad", rmad["effect"], first_label, second_label)

    return {"median_time": time, "rmad": rmad}


def add_comparison(report, name, first_data, second_data, first_label, second_label, kind):
    report[name] = {"managed languages": {}, "unmanaged languages": {}}

    for language in report[name]:
        for machine in MACHINE_ORDER[kind]:
            values = compare(
                first_data[language][machine],
                second_data[language][machine],
                first_label,
                second_label,
            )
            if values is not None:
                report[name][language][machine] = values


def build_base_report(kind):
    configs = {config for pair in BASE_COMPARISONS[kind] for config in pair}

    # See the reproducibility note in load_data().
    exclude_scala = kind == "multi_threaded"

    data = {
        config: load_data(kind, config, "base", exclude_scala=exclude_scala)
        for config in configs
    }

    report = {}
    for first, second in BASE_COMPARISONS[kind]:
        add_comparison(
            report,
            f"{first} vs {second}",
            data[first],
            data[second],
            first,
            second,
            kind,
        )

    return report


def build_option_report(kind, option):
    variant = OPTION_DIRS.get(option, option)

    configs = ["default"] if option == "pinned_hyper_threading" else (
        ["recommended", "default"]
        if kind == "single_threaded"
        else ["recommended", "mt_recommended", "default"]
    )

    fallback = {
        "recommended": "Recommended",
        "mt_recommended": "MT-Recommended",
        "default": "Default",
    }

    report = {}
    for config in configs:
        add_comparison(
            report,
            f"{config} vs modified {config}",
            load_data(kind, config, "base"),
            load_data(kind, config, variant),
            config,
            OPTION_LABELS[option].get(config, fallback[config]),
            kind,
        )

    return report


def metric_report(report, metric):
    return {
        comparison: {
            language: {
                machine: values[metric]
                for machine, values in machines.items()
            }
            for language, machines in languages.items()
        }
        for comparison, languages in report.items()
    }


def write_reports(option, kind, report):
    output = OUTPUT_DIR / option
    output.mkdir(parents=True, exist_ok=True)

    for metric, suffix in [("median_time", "times"), ("rmad", "rmads")]:
        path = output / f"{option}_wilcoxon_{suffix}_{kind}_report.json"
        with path.open("w") as file:
            json.dump(metric_report(report, metric), file, indent=4)
        print(path)


def main():
    if len(sys.argv) != 2 or (sys.argv[1] != "base" and sys.argv[1] not in OPTION_LABELS):
        print(f"Usage: {sys.argv[0]} base|<option>")
        sys.exit(1)

    option = sys.argv[1]

    for kind in ("single_threaded", "multi_threaded"):
        report = build_base_report(kind) if option == "base" else build_option_report(kind, option)
        write_reports(option, kind, report)


if __name__ == "__main__":
    main()