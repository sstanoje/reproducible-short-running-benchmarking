# Warmup analysis for the recommended configuration

Counts indicate the number of unique benchmarks for which each of the first five iterations is at least 1% above the 99th percentile of the subsequent 100 measurement iterations in at least one execution environment.
Each benchmark is counted once per column if any of the five environments meets this rule.

| Suite | Total | Iteration 1 | Iteration 2 | Iteration 3 | Iteration 4 | Iteration 5 |
|---|---:|---:|---:|---:|---:|---:|
| DaCapo | 6 | 6 | 3 | 2 | 2 | 0 |
| Scala DaCapo | 9 | 9 | 4 | 1 | 1 | 0 |
| Renaissance | 13 | 13 | 2 | 1 | 0 | 0 |
| PolyBench/C | 30 | 2 | 0 | 0 | 0 | 0 |
| PARSEC | 8 | 1 | 0 | 0 | 0 | 0 |
