#!/bin/bash

# ssh -p 17541 root@142.170.89.112 -L 8080:localhost:8080

INSTANCE_IP=${1:-"142.170.89.112"}
INSTANCE_PORT=${2:-"17541"}
