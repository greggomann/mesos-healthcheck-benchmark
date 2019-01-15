#!/usr/bin/env bash

JQOUTPUT=`echo $1 | jq '
def range(n):
  [0, n] | while(.[0] < .[1]; [.[0] + 1, .[1]]) | .[0];

def task:
  "task-" + (. | tostring) | {
    "name": .,
    "task_id": {
      "value": .
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
    "health_check": {
      "type": "COMMAND",
      "grace_period_seconds": 180,
      "interval_seconds": 120,
      "consecutive_failures": 5,
      "delay_seconds": 30,
      "timeout_seconds": 115,
      "command": {
        "value": "true"
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
  };

{
  "tasks": [range(.) | task]
}
'`

echo "$JQOUTPUT"
