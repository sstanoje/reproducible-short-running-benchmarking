#!/usr/bin/env python3

import sys
import os
import statistics
import json
import operator
from scipy import stats
import numpy as np

dir = sys.argv[1]
iterations = sys.argv[2]

iter = 0
if iterations != "all":
        iter = int(iterations)

files = os.listdir(dir + "/")

total_times = []
total_avg = 0

results = []

for file in files:
        if file.endswith(".txt") and file != 'commands.txt' and '.json' not in file:
                with open(os.path.join(dir, file), 'r') as f:
                        benchmark = file.split('.txt')[0].strip()
                        lines = [line.rstrip() for line in f]
                        lines = [line for line in lines if "msec" in line]
                        times = [float(time.split("msec")[0].strip().split(' ')[-1]) for time in lines]
                        times = times[5 : ]

                        if iterations != "all":
                                times = times[ : iter]
                                assert(len(times) == iter)

                        mean = statistics.mean(times)

                        stdev = statistics.stdev(times)
                        stdev_percent = (stdev / mean) * 100

                        median = statistics.median(times)

                        CV = stdev / mean

                        MAD = statistics.median([abs(x - median) for x in times])
                        RMAD = MAD / median

                        q1, q3 = np.percentile(times, [25, 75])
                        CQV = (q3 - q1) / (q3 + q1) * 100

                        shapiro_stat, shapiro_p = stats.shapiro(times)
                        normal_shapiro = True if shapiro_p > 0.05 else False

                        results.append({'benchmark' : benchmark, 'stdev(%)' : stdev_percent, 'RMAD(%)' : RMAD * 100, 'avg time' : mean, 'median' : median, 'normal distribution' : normal_shapiro})

results.sort(key=operator.itemgetter('benchmark'))

with open(dir + ".json", "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=4)
