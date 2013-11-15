#!/usr/bin/bash

through=`date +%Y/%m/%d`
cvs log -d "$1<$through 23:59:59" 2>&1 | grep -A3 'revision ' | grep -v 'revision '
