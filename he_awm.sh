#!/bin/bash
# Program: HIVE-Engine Auto Witness Monitor (HE-AWM)
# Description: Manages the sync of the node and the witness registration status/notifications
# Author: forykw
# Date: 2022/11/05
# v1.3.0

## Optimised for:
# Hive-Engine 1.8.2+

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
# Represents the initial and previous assumed states of the node when this script starts (1-Down, 0-Running)
NODE_DOWN="1"
NODE_PREVIOUS_STATE=${NODE_DOWN}
# Enable or disable fork detection (default: 1-Enabled)
FORK_MONITOR_ENABLED="1"

# Timestamp format for script output
timestamp_format ()
{
        echo "[`date --iso-8601=seconds`] "
}

# Check state of the running chain and if in a fork, unregister and stop the node
check_fork_monitor ()
{
	# Represents the state of the chain (0-onchain, 1-forked)
	# Represents previous state detected
	PREV_STATUS=0
	# RPC Nodes to compare against
	HE_RPC_NODES=("https://api2.hive-engine.com/rpc" "https://api.hive-engine.com/rpc")
	# Number of RPC Nodes is defined by ${#HE_RPC_NODES[@]}
	echo $(timestamp_format)"Fork monitor started..."
	while [ true ]; do
		# Scan every 60 seconds (increase this value if you don't won't too often scans)
		sleep 60
		# Reset the level of forking comparison for decision
                FORK_DECISION=0
		echo $(timestamp_format)"Scanning for forks!"
		# Target nodes on HE_RPC_NODES array
		for (( i=0; i<${#HE_RPC_NODES[@]}; i++ )); do
		        # If it finds at least one line with divergent, then we are in a fork against that node
			SCAN_RESULT=`node find_divergent_block.js -n ${HE_RPC_NODES[${i}]} | grep divergent | wc -l`
			# Update detected forks against all RPC nodes configured for scan
			echo $(timestamp_format)"Fork scan result["$((${i}+1))"/${#HE_RPC_NODES[@]}]: ${SCAN_RESULT}"
			if [ ${SCAN_RESULT} -ge 1 ]; then
				((FORK_DECISION++))
			fi
		done
		echo $(timestamp_format)"Fork scan decision weight[${#HE_RPC_NODES[@]}]: ${FORK_DECISION}"

		# Act based on the decisions
		if [ ${FORK_DECISION} -ge 2  ] && [ ${PREV_STATUS} -eq 0 ]; then
			# We have potentially forked since all nodes reported forked status
			echo $(timestamp_format)"Fork detected, unregistering..."
        		node witness_action.js unregister
			echo $(timestamp_format)"Unregistration Broadcasted, stopping node(${PM2_NODE_NAME})..."
			pm2 stop ${PM2_NODE_NAME}
			PREV_STATUS=1
		elif [ ${FORK_DECISION} -lt 2  ] && [ ${PREV_STATUS} -eq 1 ]; then
			# If we were forked previously and currently are not anymore for all nodes, then let's restart the node
			# This also covers the situation the database might be restored, so you don't need to restart the monitor
			echo $(timestamp_format)"Restarting node(${PM2_NODE_NAME})..."
			pm2 start ${PM2_NODE_NAME}
			PREV_STATUS=0
		else
			# Otherwise if the node had forked and stopped or is running fine, do nothing
			echo "" > /dev/null
		fi
	done
}

# Start the fork monitor in background if enabled
if [ "${FORK_MONITOR_ENABLED}" == "1" ]; then
check_fork_monitor &
fi

# Main loop
while [ true ]; do
# Save last state of the node
NODE_PREVIOUS_STATE=${NODE_DOWN}

# Validate if node is down
NODE_DOWN=`pm2 list | grep ${PM2_NODE_NAME} | grep stopped | wc -l`

# If starting the node, wait a few seconds for log to change
if [ "${NODE_PREVIOUS_STATE}" == "1" ] && [ "${NODE_DOWN}" == "0" ]; then
	echo $(timestamp_format)"Waiting some time for node to start..."
	sleep 10
fi

# If the node is up validate if there is enought log to make decisions, otherwise wait
if [ "${NODE_DOWN}" == "0" ]; then
	while [ `tail -n 1000 ${NODE_APP_LOG} | grep Streamer | grep head_block_number | grep "blocks\ ahead" | wc -l` -lt 2  ]; do
		# While waiting, monitor if the node goes down
		NODE_DOWN=`pm2 list | grep ${PM2_NODE_NAME} | grep stopped | wc -l`
		if [ "${NODE_DOWN}" == "1" ]; then
			break;
		fi
		echo $(timestamp_format)"Waiting for more log information..."
		sleep 1
	done
fi

# For the next two variables "BLOCKS_MISSING" and "TIMES_MISSING"
# (TODO) - Fix the cases when logrotate starts a new file and there are no messages
# (IMPROVE) - Find a way to not rely on tail and be lightweight in IO access
# (FIX) - Play with arrays and reduce the amount of queries to IO

# Find current <Round>
# Adjust number of lines depending on log history messages
CURRENT_ROUND=`tail -n 1000 ${NODE_APP_LOG} | grep P2P | grep currentRound | tail -n 1 | cut -d " " -f 6`

# Find any recent <Round> witness messages
# (TODO) - use another method as tail generates repeated messages (adjust tail lines for log history adjustment)
WITNESS_INFO[0]=`tail -n 1000 ${NODE_APP_LOG} | grep Blockchain | grep ${WITNESS_NAME} | grep ${CURRENT_ROUND} | grep scheduled | tail -n 1 | awk '{ print $5, $8, $9, $10, $11, $12" - Last log message ("$1 , $2")" }'`
WITNESS_INFO[1]=`tail -n 1000 ${NODE_APP_LOG} | grep signed | grep ${WITNESS_NAME} | grep ${CURRENT_ROUND} | tail -n 1 | awk '{ print $7, $8, $9" - Last log message ("$1 , $2")" }'`
# Print if there is any message
if [ -n "${WITNESS_INFO[0]}" ]; then
	echo $(timestamp_format)${WITNESS_INFO[0]}
fi
if [ -n "${WITNESS_INFO[1]}" ]; then
        echo $(timestamp_format)${WITNESS_INFO[1]}
fi


# Get number of blocks still missing from last streamer message
BLOCKS_MISSING=`tail -n 333 ${NODE_APP_LOG} | grep Streamer | grep head_block_number | tail -n 1 | cut -d" " -f 12`

# Search the log for X amount of streamer messages and count how many we were missing blocks
# The bigger you set the tailed lines (-n) the higher number of messages you will get (higher requirements for being stable) 
# Should be used with the same number of lines as the BLOCKS_MISSING variable. But is not mandatory!
TIMES_MISSING=`tail -n 333 ${NODE_APP_LOG} | grep Streamer | grep head_block_number | grep -v "0\ blocks\ ahead"|wc -l`

# Update time
CURRENT_TIME=`date --iso-8601=seconds`

# Validate if node is down (again) to increase reaction due low IO log performance
NODE_DOWN=`pm2 list | grep ${PM2_NODE_NAME} | grep stopped | wc -l`

# Validate sync status
if [ "${NODE_DOWN}" == "1" ]; then
	echo "[${CURRENT_TIME}] Node is DOWN."
	REGISTER="0"
elif [ "${NODE_DOWN}" == "0" ] && [ "${BLOCKS_MISSING}" != "" ]; then
	# The order of the IFs matter!
        if [ "${TIMES_MISSING}" == "0" ] && [ "${BLOCKS_MISSING}" == "0" ]; then
                # No missed blocks, therefore we can be sure to continue signing or register
                echo $(timestamp_format)"Witness State[${SIGNING_BLOCKS}] Round[${CURRENT_ROUND}] - Node is stable and in sync!"
                REGISTER="1"
	elif [[ ( ${TIMES_MISSING} -lt 5 ) ]] && [[ ( "${BLOCKS_MISSING}" == "1" ) || ( "${BLOCKS_MISSING}" == "0" ) ]]; then
                # Let's assume that one or two times behind and up to 1 block missed is an evaluation zone A (no decisions)
                echo $(timestamp_format)"Witness State[${SIGNING_BLOCKS}] Round[${CURRENT_ROUND}] - Evaluation threshold... [${BLOCKS_MISSING}]BM [${TIMES_MISSING}]TM"

	else
                # If there are more than one message with missing blocks and still out of sync, then indicate to unregister
                echo $(timestamp_format)"Witness State[${SIGNING_BLOCKS}] Round[${CURRENT_ROUND}] - Node is unstable with: [${BLOCKS_MISSING}]BM [${TIMES_MISSING}]TM"
                REGISTER="0"
	fi
else
	# When the log output is flooded with other messages and there is not enough lines parsed to capture the blocks ahead info
	# If you experience too many of these messages, try to increase the number of lines parsed for the BLOCKS_MISSING variable (and the TIMES_MISSING too)
	echo $(timestamp_format)"Could not parse blocks ahead field..."
fi

# (Un)Register witness depeding on signing status
if [ "${SIGNING_BLOCKS}" == "0" ] && [ "${REGISTER}" == "1" ]; then
	echo $(timestamp_format)"Registering Witness"
	SIGNING_BLOCKS="1"
	node witness_action.js register
	echo $(timestamp_format)"Registration Broadcasted"
elif [ "${SIGNING_BLOCKS}" == "1" ] && [ "${REGISTER}" == "0" ]; then
	echo $(timestamp_format)"Unregistering Witness"
	SIGNING_BLOCKS="0"
	node witness_action.js unregister
	echo $(timestamp_format)"Unregistration Broadcasted"
fi

# Scan frequency
sleep 5
done
