#!/opt/mesosphere/bin/python

import datetime
import math
import sys

start_times = {}
finish_times = {}

for line in sys.stdin:
  if 'LAUNCH_NESTED_CONTAINER_SESSION' in line:
    space_separated = line.split(' ')

    timestamp = space_separated[6]
    time_split = timestamp.split(':')
    second_split = time_split[2].split('.')
    start_time = datetime.time(hour=int(time_split[0]), minute=int(time_split[1]), second=int(second_split[0]), microsecond=int(second_split[1]))

    dot_separated = line.split('.')
    container_id = dot_separated[7].replace("'\n", '')

    start_times[container_id] = start_time
  elif 'FETCHING to RUNNING' in line and 'check-' in line:
    space_separated = line.split(' ')

    timestamp = space_separated[6]
    time_split = timestamp.split(':')
    second_split = time_split[2].split('.')
    finish_time = datetime.time(hour=int(time_split[0]), minute=int(time_split[1]), second=int(second_split[0]), microsecond=int(second_split[1]))

    dot_separated = line.split('.')
    container_id = dot_separated[7].split(' ')[0]

    finish_times[container_id] = finish_time

response_times = []

for container_id in start_times.keys():
  if container_id in finish_times:
    date = datetime.datetime.min
    time_delta = datetime.datetime.combine(date, finish_times[container_id]) - datetime.datetime.combine(date, start_times[container_id])
    response_times.append(time_delta.total_seconds())

print('Response times:')
print(response_times)

print('\nN = {}'.format(len(response_times)))

total = 0.
for duration in response_times:
  total += duration

mean = total / len(response_times)

print('\nMean: {}'.format(mean))

total = 0.
for duration in response_times:
  total += (duration - mean)**2

print('\nStandard deviation: {}'.format(math.sqrt(total / len(response_times))))
