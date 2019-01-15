#!/usr/bin/env python3

import json
import random
import sys

def generateTaskGroup(numTasks, interval, timeout):
  return { "tasks": [
    {
      "name": "task-" + str(i),
      "task_id": {
        "value": "task-" + str(i)
      },
      "agent_id": {
        "value": ""
      },
      "resources": [
        {
          "name": "cpus",
          "type": "SCALAR",
          "scalar": {
            "value": 0.01
          }
        },
        {
          "name": "mem",
          "type": "SCALAR",
          "scalar": {
            "value": 32
          }
        }
      ],
      "check": {
        "type": "COMMAND",
        "interval_seconds": interval,
        "timeout_seconds": timeout,
        "delay_seconds": random.random() * 10.37 + 10.,
        "command": {
          "command": {
            "value": "exit $((1 + RANDOM % 10))"
          }
        }
      },
      "container": {
        "type": "MESOS",
        "mesos": {
          "image": {
            "type": "DOCKER",
            "docker": {
              "name": "alpine"
            }
          }
        }
      },
      "command": {
        "value": "sleep 99999999"
      }
    } for i in range(numTasks) ] }

if len(sys.argv) != 4:
  sys.exit('Usage: ./tasks-healthcheck.py [num_tasks] [healthcheck_interval] [healthcheck_timeout]')

numTasks = int(sys.argv[1])
interval = float(sys.argv[2])
timeout = float(sys.argv[3])

print(json.dumps(generateTaskGroup(numTasks, interval, timeout)))
