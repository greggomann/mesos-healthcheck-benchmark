#!/usr/bin/env bash

# Usage: ./run-test-check-throughput.sh [master_ip:port] [agent_ip] [array of num_tasks, i.e. '1 2 4 8']

ARGUMENTS=("$@")
NUM_ARGS=${#ARGUMENTS[@]}

MASTER_ADDRESS=$1
AGENT_ADDRESS=$2

for (( i = 2; i < $NUM_ARGS; i++ )); do
  NUM_TASKS=${ARGUMENTS[${i}]}

  # Save original stdout and stderr, then redirect to a file.
  exec 3>&1 4>&2 1>run-test-check-throughput-$NUM_TASKS.txt 2>&1

  printf "\n=================================================================\n"
  printf "Running check throughput test with $NUM_TASKS concurrent tasks\n"
  printf "\nTask group JSON definition:\n"
  ./tasks-check.py $NUM_TASKS 0 300

  ./tasks-check.py $NUM_TASKS 0 300 > task-group-$NUM_TASKS.json

  /opt/mesosphere/active/mesos/bin/mesos-execute --master=$MASTER_ADDRESS --task_group="`./tasks-check.py $NUM_TASKS 0 300`" &

  SCHEDULER_PID=$!

  printf "$NUM_TASKS tasks " >&3
  for (( j = 0; j < 6; j++ )); do
    sleep 60
    printf "... " >&3
  done

  printf "generating logs ... " >&3
  LOG_FILENAME="agent-log.txt"
  ssh $AGENT_ADDRESS "journalctl -u dcos-mesos-slave --since='5 minutes ago' > $LOG_FILENAME"

  printf "running perf --no-inherit ... " >&3
  ssh -t $AGENT_ADDRESS 'sudo perf record --output=/home/centos/perf-no-inherit.data --freq=100 --no-inherit --call-graph dwarf -p `ps aux | grep mesos-agent | grep packages | grep -v grep | awk "{ print \\\$2 }"` -- sleep 60'
  ssh -t $AGENT_ADDRESS 'sudo chown centos:centos /home/centos/perf-no-inherit.data'
  printf "running perf ..." >&3
  ssh -t $AGENT_ADDRESS 'sudo perf record --output=/home/centos/perf-inherit.data --freq=100 --call-graph dwarf -p `ps aux | grep mesos-agent | grep packages | grep -v grep | awk "{ print \\\$2 }"` -- sleep 60'
  ssh -t $AGENT_ADDRESS 'sudo chown centos:centos /home/centos/perf-inherit.data'

  printf "creating test result artifact ..." >&3
  TARBALL_FILENAME="check-throughput-agent-results-$NUM_TASKS.tgz"

  ssh $AGENT_ADDRESS "tar -cvzf check-throughput-agent-results-$NUM_TASKS.tgz perf-no-inherit.data perf-inherit.data $LOG_FILENAME"
  scp $AGENT_ADDRESS:~/check-throughput-agent-results-$NUM_TASKS.tgz ./

  kill -9 $SCHEDULER_PID

  # Restore stdout and stderr file descriptors.
  exec 1>&3 2>&4

  printf "\n" >&3
done
