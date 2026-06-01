#!/bin/bash
STATE="${1:-idle}"
echo "$STATE" > /tmp/codex_traffic_light_state
