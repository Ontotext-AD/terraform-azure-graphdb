#!/usr/bin/env bash

# Generic helper functions

# Function to print messages with timestamps
log_with_timestamp() {
  if [ -z "$1" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: Missing log message" >&2
    return 1
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1"
}
