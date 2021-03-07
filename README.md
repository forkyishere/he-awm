# HIVE-Engine Auto Witness Monitor (HE-AWM)

This is a bash script to automate the Hive-Engine Witness node registration status and avoid missed blocks.

Still very early Alpha kind of stuff, so treat it accordantly.
Will get better over time.

## `he_awm.sh`
Executable bash script that runs on the same folder of the HIVE-Engine witness code.

## How to start
Review the script contents and modify at your leasure any initial status or thresholds. Then simply execute the script:
```
[your_hive_engine_witness_folder]> ./he_awm.sh
```

## How to stop
Ctrl+C or kill the pid from the script (use `ps -ef | grep he_awm.sh` to find it)

## Features
 - Blockchain sync detection via `node_app.log` output
 - Automatic register or unregister witness via stability of the node (blocks behind)
   1. Assumes 1 block behind as being acceptable as long there is no repetition (aka recovers quickly)
   2. If the chain is more than 1 block ahead, unregister
   3. Once we are again in sync with zero sync problems for a couple seconds, register
- Display messages when witness is scheduled for signing or signed a block

# Feedback / Contacts
Feel free to submit any feature requests/bugs via github or to contact me on HIVE via @forykw account.
