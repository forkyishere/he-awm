# HIVE-Engine Auto Witness Monitor (HE-AWM)


> _This script is a Bash script for monitoring a Hive-Engine witness node. The script is designed to manage the synchronization of the node, as well as the registration status of the witness account. The script also includes a "fork monitor" which checks for potential forking on the chain and takes appropriate action if a fork is detected._

🦾 automatic script description via https://chat.openai.com/chat

## Disclaimer
Without any guarantees and at your own responsability, so treat it accordantly. Will get better over time.

This script needs to be (potentially) modified if the Hive-Engine code changes, therefore always double check the `Optimised for:` comment section inside the script.
The main focus is to allow a node to live without disrupting the network in case of problematic situations, hence it can unregister temporarily your witness or stop the node.
Until a new flag is added (for dry run) make due deliegence before executing this script.
Runnning this script will only take actions passively to what happens to your node log, in terms of node (un)registration and node stop/start status.

## `he_awm.sh`
Name of the executable bash script that runs on the same folder of the HIVE-Engine witness code.

## Configurables
Inside the script check the `Requirements` comment section and its variables. Adapting these to your node should be enought to get you going.

In addition, if you would like to customise the state of which the script starts, change the variables under the `State variables` comment section to other initial states.

## How to start
Review the script contents and modify at your leasure any initial status or thresholds. Then simply execute the script:
```
[your_hive_engine_witness_folder]> ./he_awm.sh
```

## How to stop
Ctrl+C or kill the pid from the script (use `ps -ef | grep he_awm.sh` to find it)

## Start with log and screen output
```
[your_hive_engine_witness_folder]> ./he_awm.sh 2>&1 | tee -a he_awm.log
```

# Features
 - Blockchain sync detection via `node_app.log` output
 - Automatic register or unregister witness via stability of the node (blocks behind)
   1. Assumes 1 block behind as being acceptable as long there is no more than 4 repetitions (configurable) - aka recovers quickly
   2. If the chain is more than 1 block ahead, unregister
   3. Once we are again in sync with zero sync problems for a couple seconds, register
- Display messages when witness is scheduled for signing or signed a block
- Fork detection and node unregister+shutdown
- Node recovery on false fork alarm (depends on `antiForkBufferMaxSize` and scan frequency)
- IPv6 scanning to guarantee witness communication (unregister if communication is lost)

# Feedback / Contacts
Feel free to submit any feature requests/bugs via github or to contact me on HIVE via @forykw account.
