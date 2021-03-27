#!/bin/bash
# Program: HIVE-Engine Auto Witness Monitor (HE-AWM)
# Description: Manages the sync of the node and the witness registration status/notifications
# Author: forykw
# Date: 2021/03/27
# v1.2

## Optimised for:
# Hive-Engine 1.2.0

## Requirements
# Log name output from the hive-engine node (app.js)
NODE_APP_LOG="node_app.log"
# Name of the witness account signing blocks
WITNESS_NAME="atexoras.witness"
# Name of the PM2 process that started the node (app.js)
PM2_NODE_NAME="prod-hivengwit"

## State variables
# Represents the witness registered state (1-Registered, 2-Unregistered)
SIGNING_BLOCKS="0"
# Represents the intention to register (1-Registering, 2-Unregistering)
REGISTER="0"
# Represents the initial assumed state of the node when this script starts (1-Down, 0-Running)
NODE_DOWN="1"

# Main loop
while [ true ]; do
# Validate if node is down
NODE_DOWN=`pm2 status ${PM2_NODE_NAME} |grep stopped|wc -l`

# For the next two variables "BLOCKS_MISSING" and "TIMES_MISSING"
# (TODO) - Fix the cases when logrotate starts a new file and there are no messages
# (IMPROVE) - Find a way to not rely on tail and be lightweight in IO access
# (FIX) - Play with arrays and reduce the amount of queries to IO

# Find current <Round>
CURRENT_ROUND=`tail -n 1000 ${NODE_APP_LOG} | grep P2P | grep currentRound | tail -n 1 | cut -d " " -f 6`

# Find any recent <Round> witness messages
# (TODO) - use another method as tail generates repeated messages (adjust tail lines for repetition adjustment)
WITNESS_INFO=`tail -n 200 ${NODE_APP_LOG} | grep Blockchain | grep ${WITNESS_NAME} | grep ${CURRENT_ROUND} | tail -n 1`
# Print if there is any message
if [ -n "${WITNESS_INFO}" ]; then
	echo ${WITNESS_INFO}
fi

# Get number of blocks still missing from last streamer message
BLOCKS_MISSING=`tail -n 333 ${NODE_APP_LOG} | grep Streamer | grep head_block_number | tail -n 1 | cut -d" " -f 12`

# Search the log for X amount of streamer messages and count how many we were missing blocks
# The bigger you set the tailed lines (-n) the higher number of messages you will get (higher requirements for being stable) 
TIMES_MISSING=`tail -n 333 ${NODE_APP_LOG} | grep Streamer | grep head_block_number | grep -v "0\ blocks\ ahead"|wc -l`

# Update time
CURRENT_TIME=`date --iso-8601=seconds`

# Validate sync status
if [ "${NODE_DOWN}" == "1" ]; then
	echo "[${CURRENT_TIME}] Node is DOWN."
	REGISTER="0"
elif [ "${NODE_DOWN}" == "0" ] && [ "${BLOCKS_MISSING}" != "" ]; then
	# The order of the IFs matter!
        if [ "${TIMES_MISSING}" == "0" ] && [ "${BLOCKS_MISSING}" == "0" ]; then
                # No missed blocks, therefore we can be sure to continue signing or register
                echo "[${CURRENT_TIME}] Witness State[${SIGNING_BLOCKS}] - Node is stable and in sync!"
                REGISTER="1"
	elif [ "${TIMES_MISSING}" == "1" ] && [[ ( "${BLOCKS_MISSING}" == "1" ) || ( "${BLOCKS_MISSING}" == "0" ) ]]; then
		# Let's assume for now that 1 block or one time behind is a evaluation zone (no decisions)
		echo "[${CURRENT_TIME}] Witness State[${SIGNING_BLOCKS}] - Evaluation threshold... [${BLOCKS_MISSING}]BM [${TIMES_MISSING}]TM"
	else
                # If there are more than one message with missing blocks and still out of sync, then indicate to unregister
                echo "[${CURRENT_TIME}] Witness State[${SIGNING_BLOCKS}] - Node is unstable with: [${BLOCKS_MISSING}]BM [${TIMES_MISSING}]TM"
                REGISTER="0"
	fi
else
	echo "["${CURRENT_TIME}"] Unknown error"
fi

# (Un)Register witness depeding on signing status
if [ "${SIGNING_BLOCKS}" == "0" ] && [ "${REGISTER}" == "1" ]; then
	echo "[${CURRENT_TIME}] Registering Witness"
	SIGNING_BLOCKS="1"
	node witness_action.js register
	echo "[${CURRENT_TIME}] Registration Broadcasted"
elif [ "${SIGNING_BLOCKS}" == "1" ] && [ "${REGISTER}" == "0" ]; then
	echo "[${CURRENT_TIME}] Unregistering Witness"
	SIGNING_BLOCKS="0"
	node witness_action.js unregister
	echo "[${CURRENT_TIME}] Unregistration Broadcasted"
fi

# Scan frequency
sleep 10
done