#!/usr/bin/env python3
import re
from pathlib import Path

import numpy as np

root = Path(__file__).resolve().parents[2]

suites = {
    "dacapo": "DaCapo",
    "dacapo_con_scala": "Scala DaCapo",
    "renaissance": "Renaissance",
    "polyBenchC": "PolyBench/C",
    "parsec": "PARSEC",
}

table = [
    "# Warmup analysis for the recommended configuration",
    "",
    "Counts indicate the number of unique benchmarks for which each of the first five "
    "iterations is at least 1% above the 99th percentile of the subsequent 100 "
    "measurement iterations in at least one execution environment.",
    "Each benchmark is counted once per column if any of the five environments meets this rule.",
    "",
    "| Suite | Total | Iteration 1 | Iteration 2 | Iteration 3 | Iteration 4 | Iteration 5 |",
    "|---|---:|---:|---:|---:|---:|---:|",
]

for suite, name in suites.items():
    benchmarks = set()
    warmup = [set() for _ in range(5)]

    # Read baseline recommended measurements from all environments.
    for file in sorted(
        (root / "results" / suite).glob(
            "*/recommended_configuration_results/base/*/*.txt"
        )
    ):
        if file.name == "commands.txt":
            continue

        text = file.read_text()

        if suite in ("dacapo", "dacapo_con_scala"):
            pattern = r"(?:completed warmup\s+\d+\s+in|PASSED in)\s+([\d.]+)\s*msec"
        elif suite == "renaissance" and "msec" not in text:
            pattern = r"completed \(([\d.]+)\s*ms\)"
        else:
            pattern = r"([\d.]+)\s*msec"

        times = [float(value) for value in re.findall(pattern, text)]
        assert len(times) >= 105, file

        benchmarks.add(file.stem)

        threshold = np.percentile(times[5:105], 99) * 1.01

        for iteration, time in enumerate(times[:5]):
            if time >= threshold:
                warmup[iteration].add(file.stem)

    counts = [name, str(len(benchmarks))] + [
        str(len(items)) for items in warmup
    ]
    table.append("| " + " | ".join(counts) + " |")

output_dir = root / "warmup_analysis_results"
output_dir.mkdir(exist_ok=True)

output = output_dir / "recommended_warmup_evidence.md"
output.write_text("\n".join(table) + "\n")

print("Warmup evidence saved to:", output)