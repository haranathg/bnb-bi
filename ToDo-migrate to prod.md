To migrate to prod
-- run sql - to create sp_create_bi_tables.sql
-- create the refresh log table
CREATE TABLE IF NOT EXISTS bi_refresh_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    refresh_type VARCHAR(50),
    status VARCHAR(20),
    message TEXT,
    started_at DATETIME,
    completed_at DATETIME,
    rows_consolidated INT,
    rows_asp INT,
    rows_wac INT,
    rows_awp INT,
    INDEX idx_started_at (started_at),
    INDEX idx_status (status)
);
-- move the utils folder to prod -- the .sh file
-- create the .my.cnf file with prod credentials

-- create the crontab - 
crontab -e
0 2 * * * /home/buyandbi/utils/refresh_bi.sh >> /home/buyandbi/utils/bi_refresh.log 2>&1


