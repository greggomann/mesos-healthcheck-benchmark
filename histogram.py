#!/opt/mesosphere/bin/python

import sys
from collections import OrderedDict

numdict = {}

for line in sys.stdin:
  numstring = line.strip()
  num = int(numstring)
  value = numdict.setdefault(num, 0)
  numdict[num] = value + 1

for key in sorted(numdict):
  print("{:<10}{:=<{width}}".format(key, "", width=numdict[key]))
