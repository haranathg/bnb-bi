#!/bin/bash
LOG_FILE="/home/buyandbill/utils/bi_refresh.log"

echo "[$(date)] Starting BI table refresh..." >> $LOG_FILE

mysql buyandbill_cms -e "CALL sp_refresh_bi_tables_v3();" 2>&1 >> $LOG_FILE

if [ $? -eq 0 ]; then
    echo "[$(date)] BI table refresh completed successfully" >> $LOG_FILE
else
    echo "[$(date)] ERROR: BI table refresh failed" >> $LOG_FILE
fi
