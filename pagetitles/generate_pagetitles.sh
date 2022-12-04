#!/bin/bash

cat pageTitles.txt | jq -R -s -c 'split("\n") | [ .[] | select(length > 0) ]' | jq . > pageTitles.json

