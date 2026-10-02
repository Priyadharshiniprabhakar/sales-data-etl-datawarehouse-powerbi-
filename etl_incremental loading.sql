DELIMITER //

DROP PROCEDURE IF EXISTS sp_incremental_sales_etl//

CREATE PROCEDURE sp_incremental_sales_etl()
BEGIN
    DECLARE v_start_time DATETIME;
    DECLARE v_job_id INT DEFAULT NULL;
    DECLARE v_last_load DATETIME;
    
    -- Error diagnostic variables
    DECLARE v_sql_state VARCHAR(5);
    DECLARE v_err_no INT;
    DECLARE v_err_msg TEXT;

    -- Exit Handler: captures exact error details into etl_log
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Extract exact MySQL error diagnostics
        GET DIAGNOSTICS CONDITION 1
            v_sql_state = RETURNED_SQLSTATE,
            v_err_no = MYSQL_ERRNO,
            v_err_msg = MESSAGE_TEXT;
            
        -- Roll back uncommitted transaction data
        ROLLBACK;
        
        -- Update metadata & log (Survives because etl_metadata was committed before START TRANSACTION)
        IF v_job_id IS NOT NULL THEN
            UPDATE etl_metadata
            SET end_time = NOW(),
                status = 'FAILED'
            WHERE job_id = v_job_id;
            
            INSERT INTO etl_log (job_id, step_name, status, message)
            VALUES (
                v_job_id, 
                'ERROR', 
                'FAILED', 
                CONCAT('Error ', v_err_no, ' (', v_sql_state, '): ', v_err_msg)
            );
        END IF;
    END;

    SET v_start_time = NOW();

    -- =================================================================
    -- STEP 1: INITIALIZE METADATA (Outside Transaction)
    -- Auto-committed so ROLLBACK won't destroy job_id on error
    -- =================================================================
    INSERT INTO etl_metadata (job_name, start_time, status)
    VALUES ('Sales Incremental ETL', v_start_time, 'RUNNING');

    SET v_job_id = LAST_INSERT_ID();

    -- Retrieve Last Successful Load Timestamp
    SELECT IFNULL(MAX(last_load_time), '1900-01-01 00:00:00')
    INTO v_last_load
    FROM etl_metadata
    WHERE status = 'SUCCESS';

    -- =================================================================
    -- STEP 2: BEGIN DATA TRANSACTION
    -- =================================================================
    START TRANSACTION;

    INSERT INTO etl_log (job_id, step_name, status, message)
    VALUES (v_job_id, 'START', 'SUCCESS', 'ETL Process Started');

    -- =================================================================
    -- STEP 3: ERROR LOGGING SECTION
    -- =================================================================

    -- Error Orders: NULL Values
    INSERT INTO e_order (o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue, error_message)
    SELECT o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue, 'Null values'
    FROM l_order
    WHERE load_time > v_last_load AND load_time <= v_start_time
      AND (o_id IS NULL OR c_id IS NULL OR p_id IS NULL);

    -- Error Orders: Invalid Quantity
    INSERT INTO e_order (o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue, error_message)
    SELECT o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue, 'Invalid value'
    FROM l_order
    WHERE load_time > v_last_load AND load_time <= v_start_time 
      AND o_quatity < 0;

    -- Error Orders: Invalid Price
    INSERT INTO e_order (o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue, error_message)
    SELECT o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue, 'Invalid price'
    FROM l_order
    WHERE load_time > v_last_load AND load_time <= v_start_time 
      AND (
        unitprice IS NULL
        OR REPLACE(unitprice, ',', '') NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
        OR CAST(REPLACE(unitprice, ',', '') AS DECIMAL(10,2)) <= 0
      );

    -- Error Orders: Duplicates
    INSERT INTO e_order (o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue, error_message)
    SELECT o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue, 'Duplicate'
    FROM (
        SELECT *, ROW_NUMBER() OVER(PARTITION BY o_id ORDER BY load_time DESC) AS rnk
        FROM l_order
        WHERE load_time > v_last_load AND load_time <= v_start_time
    ) o 
    WHERE rnk > 1;

    -- Error Region: Missing City or Postcode
    INSERT INTO e_region (r_index, r_suburbs, r_city, r_postcode, r_longitude, r_latitude, r_fulladdress, error_message)
    SELECT r_index, r_suburbs, r_city, r_postcode, r_longitude, r_latitude, r_fulladdress, 'City or postcode is missing'
    FROM l_region
    WHERE load_time > v_last_load AND load_time <= v_start_time 
      AND (r_city IS NULL OR r_postcode IS NULL);

    -- Error Region: Duplicates
    INSERT INTO e_region (r_index, r_suburbs, r_city, r_postcode, error_message)
    SELECT r_index, r_suburbs, r_city, r_postcode, 'Duplicate region id found'
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY r_index ORDER BY load_time DESC) AS rn
        FROM l_region
        WHERE load_time > v_last_load AND load_time <= v_start_time
    ) x
    WHERE rn > 1;

    -- Error Region: Invalid Coordinates
    INSERT INTO e_region (r_index, r_longitude, r_latitude, error_message)
    SELECT r_index, r_longitude, r_latitude, 'Invalid latitude or longitude'
    FROM l_region
    WHERE load_time > v_last_load AND load_time <= v_start_time 
      AND (
        CAST(r_latitude AS DECIMAL(10,6)) NOT BETWEEN -90 AND 90 
        OR CAST(r_longitude AS DECIMAL(10,6)) NOT BETWEEN -180 AND 180
      );

    -- Error Products: Nulls
    INSERT INTO e_product (p_id, p_name, error_message)
    SELECT p_id, p_name, 'Product ID or Product Name is missing'
    FROM l_product
    WHERE load_time > v_last_load AND load_time <= v_start_time 
      AND (p_id IS NULL OR p_name IS NULL);

    -- Error Products: Duplicates
    INSERT INTO e_product (p_id, p_name, error_message)
    SELECT p_id, p_name, 'Duplicate Product ID'
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY p_id ORDER BY load_time DESC) AS rn
        FROM l_product
        WHERE load_time > v_last_load AND load_time <= v_start_time
    ) x
    WHERE rn > 1;

    -- Error Products: Blank Name
    INSERT INTO e_product (p_id, p_name, error_message)
    SELECT p_id, p_name, 'Product Name is blank'
    FROM l_product
    WHERE load_time > v_last_load AND load_time <= v_start_time 
      AND TRIM(p_name) = '';

    -- Error Customers: Nulls
    INSERT INTO e_customers (id, c_name, error_message)
    SELECT id, c_name, 'Customer ID or Customer Name is missing'
    FROM l_customers
    WHERE load_time > v_last_load AND load_time <= v_start_time 
      AND (id IS NULL OR c_name IS NULL);

    -- Error Customers: Duplicates
    INSERT INTO e_customers (id, c_name, error_message)
    SELECT id, c_name, 'Duplicate Customer ID'
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY load_time DESC) AS rn
        FROM l_customers
        WHERE load_time > v_last_load AND load_time <= v_start_time
    ) x
    WHERE rn > 1;

    -- Error Customers: Blank Name
    INSERT INTO e_customers (id, c_name, error_message)
    SELECT id, c_name, 'Customer Name is blank'
    FROM l_customers
    WHERE load_time > v_last_load AND load_time <= v_start_time 
      AND TRIM(c_name) = '';

    INSERT INTO etl_log (job_id, step_name, status, message)
    VALUES (v_job_id, 'VALIDATION', 'SUCCESS', 'Validation Completed');

    -- =================================================================
    -- STEP 4: STAGING LOADS
    -- =================================================================

    -- Staging Orders
    INSERT INTO s_order (o_id, order_date, ship_date, c_id, channel, currency_code, warehouse_code, r_id, p_id, o_quatity, unitprice, total_unit_cost, total_revenue)
    SELECT o_id,
           STR_TO_DATE(REPLACE(order_date, '/', '-'), '%d-%m-%Y'),
           STR_TO_DATE(REPLACE(ship_date, '/', '-'), '%d-%m-%Y'),
           c_id,
           TRIM(LOWER(channel)),
           TRIM(UPPER(currency_code)),
           TRIM(warehouse_code),
           r_id,
           p_id,
           o_quatity,
           unitprice,
           total_unit_cost,
           total_revenue
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY o_id ORDER BY load_time DESC) AS rn
        FROM l_order
        WHERE load_time > v_last_load AND load_time <= v_start_time
    ) x
    WHERE rn = 1
      AND o_id IS NOT NULL
      AND c_id IS NOT NULL
      AND p_id IS NOT NULL
      AND o_quatity >= 0
      AND REPLACE(unitprice, ',', '') REGEXP '^[0-9]+(\\.[0-9]+)?$'
      AND CAST(REPLACE(unitprice, ',', '') AS DECIMAL(10,2)) > 0;

    -- Staging Region
    INSERT INTO s_region (r_index, r_suburbs, r_city, r_postcode, r_longitude, r_latitude, r_fulladdress)
    SELECT r_index, TRIM(r_suburbs), TRIM(r_city), TRIM(r_postcode), CAST(r_longitude AS DECIMAL(10,7)), CAST(r_latitude AS DECIMAL(9,7)), TRIM(r_fulladdress)
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY r_index ORDER BY load_time DESC) AS rn
        FROM l_region
        WHERE load_time > v_last_load AND load_time <= v_start_time
    ) x
    WHERE rn = 1
      AND r_city IS NOT NULL
      AND r_postcode IS NOT NULL
      AND CAST(r_latitude AS DECIMAL(9,7)) BETWEEN -90 AND 90
      AND CAST(r_longitude AS DECIMAL(10,7)) BETWEEN -180 AND 180;

    -- Staging Products
    INSERT INTO s_product (p_id, p_name)
    SELECT p_id, TRIM(p_name)
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY p_id ORDER BY load_time DESC) AS rn
        FROM l_product
        WHERE load_time > v_last_load AND load_time <= v_start_time
    ) x
    WHERE rn = 1
      AND p_id IS NOT NULL
      AND p_name IS NOT NULL
      AND TRIM(p_name) <> '';

    -- Staging Customers
    INSERT INTO s_customers (id, c_name)
    SELECT id, TRIM(c_name)
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY load_time DESC) AS rn
        FROM l_customers
        WHERE load_time > v_last_load AND load_time <= v_start_time
    ) x
    WHERE rn = 1
      AND id IS NOT NULL
      AND c_name IS NOT NULL
      AND TRIM(c_name) <> '';

    INSERT INTO etl_log (job_id, step_name, status, message)
    VALUES (v_job_id, 'STAGE LOAD', 'SUCCESS', 'Valid Orders Loaded');

    -- =================================================================
    -- STEP 5: INCREMENTAL DIMENSION LOADS
    -- =================================================================

    -- Customer Dimension
    INSERT INTO dim_customer (customer_id, customer_name)
    SELECT sc.id, sc.c_name 
    FROM s_customers sc
    WHERE NOT EXISTS (
        SELECT 1 FROM dim_customer dc WHERE dc.customer_id = sc.id
    );

    INSERT INTO etl_log (job_id, step_name, status, message)
    VALUES (v_job_id, 'CUSTOMER DIMENSION', 'SUCCESS', 'Customer Dimension Loaded');

    -- Product Dimension
    INSERT INTO dim_product (product_id, product_name)
    SELECT sp.p_id, sp.p_name
    FROM s_product sp
    WHERE NOT EXISTS (
        SELECT 1 FROM dim_product dp WHERE dp.product_id = sp.p_id
    );

    INSERT INTO etl_log (job_id, step_name, status, message)
    VALUES (v_job_id, 'PRODUCT DIMENSION', 'SUCCESS', 'Product Dimension Loaded');

    -- Region Dimension
    INSERT INTO dim_region (region_id, suburb, city, postcode, longitude, latitude, full_address)
    SELECT sr.r_index, sr.r_suburbs, sr.r_city, sr.r_postcode, sr.r_longitude, sr.r_latitude, sr.r_fulladdress
    FROM s_region sr
    WHERE NOT EXISTS (
        SELECT 1 FROM dim_region dr WHERE dr.region_id = sr.r_index
    );

    INSERT INTO etl_log (job_id, step_name, status, message)
    VALUES (v_job_id, 'REGION DIMENSION', 'SUCCESS', 'Region Dimension Loaded');

    -- =================================================================
    -- STEP 6: INCREMENTAL FACT LOAD
    -- =================================================================

    INSERT INTO fact_sales (
        order_id, customer_id, product_id, region_id, 
        order_date, ship_date, channel, currency_code, 
        warehouse_code, quantity, unit_price, total_unit_cost, total_revenue
    )
    SELECT s.o_id, s.c_id, s.p_id, s.r_id, 
           s.order_date, s.ship_date, s.channel, s.currency_code, 
           s.warehouse_code, s.o_quatity, 
           CAST(REPLACE(s.unitprice, ',', '') AS DECIMAL(10,2)), 
           CAST(REPLACE(s.total_unit_cost, ',', '') AS DECIMAL(10,2)), 
           CAST(REPLACE(s.total_revenue, ',', '') AS DECIMAL(10,2))
    FROM s_order s
    WHERE NOT EXISTS (
        SELECT 1 FROM fact_sales f WHERE f.order_id = s.o_id
    );

    INSERT INTO etl_log (job_id, step_name, status, message)
    VALUES (v_job_id, 'FACT LOAD', 'SUCCESS', 'Fact Table Loaded');

    -- =================================================================
    -- STEP 7: UPDATE METADATA & COMMIT
    -- =================================================================

    UPDATE etl_metadata
    SET end_time = NOW(),
        status = 'SUCCESS',
        records_loaded = (SELECT COUNT(*) FROM l_order WHERE load_time > v_last_load AND load_time <= v_start_time),
        records_rejected = (SELECT COUNT(*) FROM e_order WHERE o_id IS NOT NULL),
        last_load_time = v_start_time
    WHERE job_id = v_job_id;

    INSERT INTO etl_log (job_id, step_name, status, message)
    VALUES (v_job_id, 'END', 'SUCCESS', 'ETL Completed Successfully');

    COMMIT;

END//

DELIMITER ;

call sp_incremental_sales_etl();
SELECT * FROM etl_log;

desc fact_sales;
desc dim_product;
desc dim_customer;
desc dim_region;
desc l_order;
desc l_region;
desc l_product;
desc l_customers;
desc s_order;
desc s_region;
desc s_product;
desc s_customers;

select * from etl_metadata;

-- Turn ON the MySQL Event Scheduler engine
SET GLOBAL event_scheduler = ON;

-- Drop the event if it already exists to avoid duplication
DROP EVENT IF EXISTS evt_daily_sales_incremental_etl;

-- Create the event to run daily at 00:00:01 (12:00:01 AM)
DELIMITER //

CREATE EVENT evt_daily_sales_incremental_etl
ON SCHEDULE EVERY 1 DAY
STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 1 SECOND)
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Daily Automated Event: Executes Incremental Sales ETL procedure every day right after midnight (12:00 AM)'
DO
BEGIN
    CALL sp_incremental_sales_etl();
END//

DELIMITER ;
