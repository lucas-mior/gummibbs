#!/bin/sh

script="$1"
message="$2"

>&2 echo "${script}: $message"
# dunstify "$script" "$message"
