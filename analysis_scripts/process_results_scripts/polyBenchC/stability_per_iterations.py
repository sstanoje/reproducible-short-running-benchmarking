#!/usr/bin/env python3

import sys
import os
import statistics
import json

results_dir = sys.argv[1]
output_file = sys.argv[2]

results = []

for file in os.listdir(results_dir):
    if file.endswith(".txt") and file != "commands.txt":
        with open(os.path.join(results_dir, file), "r") as f:
            benchmark = file.split(".txt")[0].strip()

            lines = [line.rstrip() for line in f]
            lines = [line for line in lines if "msec" in line]
            times = [float(line.split("msec")[0].strip().split(" ")[-1]) for line in lines]
            times = times[5:]

            stabilities = {}

            for iteration_count in range(30, 101, 10):
                current_times = times[:iteration_count]
                assert len(current_times) == iteration_count

                median = statistics.median(current_times)
                mad = statistics.median(
                    [abs(x - median) for x in current_times]
                )
                rmad = mad / median * 100

                stabilities[iteration_count] = rmad

            results.append({
                "benchmark": benchmark,
                "stabilities": stabilities
            })

results.sort(key=lambda result: result["benchmark"])

with open(output_file, "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=4)