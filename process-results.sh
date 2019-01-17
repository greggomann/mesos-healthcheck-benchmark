#!/usr/bin/env bash

CHECK_RATE_FILE=plot_check_rate.txt
RESPONSE_TIME_FILE=plot_response_time.txt

rm $CHECK_RATE_FILE
echo "Command Check Rates" >> $CHECK_RATE_FILE
echo "Tasks in One Pod" >> $CHECK_RATE_FILE
echo "Average Check Rate (per sec.)" >> $CHECK_RATE_FILE

rm $RESPONSE_TIME_FILE
echo "Command Check Responsiveness" >> $RESPONSE_TIME_FILE
echo "Tasks in One Pod" >> $RESPONSE_TIME_FILE
echo "Time to Launch Check (sec.)" >> $RESPONSE_TIME_FILE

for NUM in 1 2 4 8 16 32 64 128 256; do

  CHECK_COUNT=`cat ./results/results-$NUM/agent-log.txt | grep LAUNCH_NESTED_CONTAINER_SESSION | wc -l`
  CHECK_RATE=`bc <<< "scale=2; $CHECK_COUNT/300"`
  RESPONSE_TIME=`./healthcheck-response.py < ./results/results-$NUM/agent-log.txt`

  # Write data for check rate plot.
  echo "$NUM $CHECK_RATE" >> $CHECK_RATE_FILE

  # Write data for response time plot.
  echo "$NUM $RESPONSE_TIME" >> $RESPONSE_TIME_FILE

done
