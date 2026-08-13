#!/bin/bash

THREADS=$(nproc)

while true; do
    sleep 2
    stress -c "$THREADS" --timeout 2
done