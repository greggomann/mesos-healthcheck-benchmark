#!/usr/bin/env bash

# Usage: ./run-test-check-throughput.sh [agent_ip] [array of num_tasks, i.e. '1 2 4 8']

AGENT_IP=$1
CHECK_INTERVAL=$2
CHECK_TIMEOUT=$3

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

message() {
  echo -e "${GREEN}$@${NC}"
}

error() {
  echo -e "${RED}$@${NC}"
}

run_command() {
  ssh -l centos -A -oConnectTimeout=10 -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=QUIET -oBatchMode=yes -oPasswordAuthentication=no -t $@
}

copy_file() {
  scp -oConnectTimeout=10 -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR -oBatchMode=yes -oPasswordAuthentication=no $@
}

run_command $AGENT_IP 'sudo which perf &>/dev/null'
if [ $? -ne 0 ]; then
  echo "installing perf on the agent ... "
  run_command $AGENT_IP 'sudo yum -y install perf 1>/dev/null'
fi

LEFT=200
RIGHT=300
while (( $LEFT < $RIGHT )); do
  NUM_TASKS=$(( $LEFT + ($RIGHT - $LEFT)/2 ))
  LOG_FILE="run-test-check-throughput-$NUM_TASKS.txt"

  message "$NUM_TASKS tasks"

  echo "=================================================================" | tee -a $LOG_FILE
  echo "Running check throughput test with $NUM_TASKS concurrent tasks" | tee -a $LOG_FILE

  echo "Task group JSON definition:" >>$LOG_FILE
  ./tasks-healthcheck.py $NUM_TASKS $CHECK_INTERVAL $CHECK_TIMEOUT >>$LOG_FILE
  ./tasks-healthcheck.py $NUM_TASKS $CHECK_INTERVAL $CHECK_TIMEOUT >task-group-$NUM_TASKS.json

  export GLOG_v=1
  export DCOS_SERVICE_ACCOUNT_CREDENTIAL="$(cat mesos-execute.json)"
  export LIBPROCESS_SSL_ENABLED=true
  export LIBPROCESS_SSL_SUPPORT_DOWNGRADE=true
  export LIBPROCESS_SSL_CERT_FILE=/run/dcos/pki/tls/certs/marathon.crt
  export LIBPROCESS_SSL_KEY_FILE=/run/dcos/pki/tls/private/marathon.key
  export MESOS_HTTP_AUTHENTICATEE="com_mesosphere_dcos_http_Authenticatee"
  export MESOS_MODULES='{"libraries":[{"file":"/opt/mesosphere/lib/mesos/libdcos_security.so","modules":[{"name":"com_mesosphere_dcos_http_Authenticatee"}]}]}'
  export MESOS_VERBOSE=1
  /opt/mesosphere/active/mesos/bin/mesos-execute --principal=mesos-execute --master=leader.mesos:5050 --secret="${DCOS_SERVICE_ACCOUNT_CREDENTIAL}" --task_group="$PWD/task-group-$NUM_TASKS.json" &>>$LOG_FILE&

  SCHEDULER_PID=$!

  # Wait 5 minutes or until a health check fails.
  for (( j = 0; j < 6; j++ )); do
    sleep 30
    echo -n "... "
    grep "healthy?: 0" $LOG_FILE &>/dev/null
    if [[ $? -eq 0 ]]; then
      break
    fi
  done
  echo "DONE!"

  grep "healthy?: 0" $LOG_FILE &>/dev/null
  if [[ $? -eq 0 ]]; then
    message "Generating logs ... "
    AGENT_LOG_FILENAME="agent-log.txt"
    run_command $AGENT_IP "journalctl -u dcos-mesos-slave --since='5 minutes ago' > $AGENT_LOG_FILENAME"

    message "Running perf --no-inherit ... "
    run_command $AGENT_IP 'sudo perf record --output=/home/centos/perf-no-inherit.data.tmp --freq=100 --no-inherit --call-graph dwarf -p `ps aux | grep mesos-agent | grep packages | grep -v grep | awk "{ print \\\$2 }"` -- sleep 60 1>/dev/null'
    run_command $AGENT_IP 'sudo perf script --header --input perf-no-inherit.data.tmp | c++filt >perf-no-inherit.data'
    run_command $AGENT_IP 'sudo rm -f perf-no-inherit.data.tmp'
    run_command $AGENT_IP 'sudo chown centos:centos /home/centos/perf-no-inherit.data'

    message "Running perf ..."
    run_command $AGENT_IP 'sudo perf record --output=/home/centos/perf-inherit.data.tmp --freq=100 --call-graph dwarf -p `ps aux | grep mesos-agent | grep packages | grep -v grep | awk "{ print \\\$2 }"` -- sleep 60'
    run_command $AGENT_IP 'sudo perf script --header --input perf-inherit.data.tmp | c++filt >perf-inherit.data'
    run_command $AGENT_IP 'sudo rm -f perf-inherit.data.tmp'
    run_command $AGENT_IP 'sudo chown centos:centos /home/centos/perf-inherit.data'

    kill -9 $SCHEDULER_PID

    message "Creating test result artifact ..."

    AGENT_TARBALL_FILE="check-throughput-agent-results-$NUM_TASKS.tgz"
    run_command $AGENT_IP "tar -cvzf $AGENT_TARBALL_FILE perf-*.data $AGENT_LOG_FILENAME 1>/dev/null"
    run_command $AGENT_IP "rm -f perf-*.data $AGENT_LOG_FILENAME 1>/dev/null"
    copy_file "centos@$AGENT_IP:$AGENT_TARBALL_FILE" ./

    tar -cvzf results-$NUM_TASKS.tgz $AGENT_TARBALL_FILE $LOG_FILE task-group-$NUM_TASKS.json &>/dev/null
    rm -f task-group-$NUM_TASKS.json $AGENT_TARBALL_FILE

    error "$NUM_TASKS: FAILURE! =("
    echo "$NUM_TASKS: FAILURE! =(" >>$LOG_FILE
    RIGHT=$NUM_TASKS
  else
    kill -9 $SCHEDULER_PID

    rm -f task-group-$NUM_TASKS.json $LOG_FILE

    message "$NUM_TASKS: SUCCESS! =)"
    LEFT=$(( $NUM_TASKS + 1 ))
  fi
done

message "Finished running tests - last run was with $NUM_TASKS tasks - healthchecks seem to start failing at $LEFT tasks"
