create database sales_db;
USE SALES_DB;
#landing table

create table l_customers(id int,c_name varchar(50));

LOAD DATA INFILE 
"C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/customers.csv"
INTO TABLE l_customers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(
id,
c_name
);

select * from l_customers;

create table l_region(r_index int,r_suburbs varchar(50),r_city varchar(50),r_postcode varchar(20),r_longitude decimal(10,7),r_latitude decimal(9,7),r_fulladdress varchar(100));

load data infile
"C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/Region.csv"
into table l_region
fields terminated by ','
enclosed by '"'
lines terminated by '\r\n'
ignore 1 rows
(
r_index,
r_suburbs,
r_city,
r_postcode,
r_longitude,
r_latitude,
r_fulladdress
);

SELECT * from l_region;

create table l_product(p_id int,p_name varchar(50));

load data infile
"C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/products.csv"
into table l_product
fields terminated by ','
enclosed by '"'
lines terminated by '\r\n'
ignore 1 rows
(
p_id,
p_name
);

select * from l_product;

create table l_order (o_id varchar(50),order_date varchar(20),ship_date varchar(20),c_id int,channel varchar(20),currency_code varchar(20),warehouse_code varchar(20),r_id int,p_id int,o_quatity int,unitprice varchar(20),total_unit_cost varchar(20),total_revenue varchar(20));

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/Orders.csv'
INTO TABLE l_order
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(
    o_id,
    order_date,
    ship_date,
    c_id,
    channel,
    currency_code,
    warehouse_code,
    r_id,
    p_id,
    o_quatity,
    unitprice,
    total_unit_cost,
    total_revenue
);

select * from l_order;

#create stage table

create table s_order (o_id varchar(50),order_date date,ship_date date,c_id int,channel varchar(20),currency_code varchar(20),warehouse_code varchar(20),r_id int,p_id int,o_quatity int,unitprice varchar(20),total_unit_cost varchar(20),total_revenue varchar(20));

create table s_customers(id int,c_name varchar(50));

create table s_region(r_index int,r_suburbs varchar(50),r_city varchar(50),r_postcode varchar(20),r_longitude decimal(10,7),r_latitude decimal(9,7),r_fulladdress varchar(100));

create table s_product(p_id int,p_name varchar(50));

#create error table

create table e_order 
(
e_id int auto_increment primary key,
o_id varchar(50),
order_date varchar(20),
ship_date varchar(20),
c_id int,channel varchar(20),
currency_code varchar(20),
warehouse_code varchar(20),
r_id int,
p_id int,
o_quatity int,
unitprice varchar(20),
total_unit_cost varchar(20),
total_revenue varchar(20),
error_message varchar(250),
rejected_date datetime default current_timestamp
);

create table e_customers(e_id int auto_increment primary key,id int,c_name varchar(50),error_message varchar(250),rejected_date datetime default current_timestamp);

create table e_product(e_id int auto_increment primary key,p_id int,p_name varchar(50),error_message varchar(250),rejected_date datetime default current_timestamp);

create table e_region(e_id int auto_increment primary key,r_index int,r_suburbs varchar(50),r_city varchar(50),r_postcode varchar(20),r_longitude decimal(10,7),r_latitude decimal(9,7),r_fulladdress varchar(100),error_message varchar(250),rejected_date datetime default current_timestamp);

insert into e_order
(
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue,
error_message
)
select
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue,
"null values"
FROM l_order
WHERE 
o_id IS NULL
OR c_id IS NULL
OR p_id IS NULL;

select * from e_order;

insert into e_order
(
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue,
error_message
)
select
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue,
"validation error"
FROM l_order
WHERE o_quatity < 0;

insert into e_order
(
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue,
error_message
)
select
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue,
"invalid price error"
FROM l_order
WHERE CAST(replace(unitprice,",","") AS DECIMAL(12,2)) <= 0;

insert into e_order
(
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue,
error_message
)
select
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue,
"duplicate value"
FROM (
select *,row_number() over (partition by o_id order by o_id) as rn from l_order) as o where rn>1;

UPDATE l_order
SET ship_date =
DATE_FORMAT(
    CASE
        WHEN ship_date LIKE '%-%'
        THEN STR_TO_DATE(ship_date,'%d-%m-%Y')

        WHEN ship_date LIKE '%/%'
        THEN STR_TO_DATE(ship_date,'%e/%c/%Y')
    END,
'%d/%m/%Y'
);

select * from l_order;
SET SQL_SAFE_UPDATES = 1;
select * from l_order;
SHOW TABLES;
insert into s_order
(
o_id,
order_date,
ship_date,
c_id , 
channel,
currency_code,
warehouse_code,
r_id,
p_id,
o_quatity,
unitprice ,
total_unit_cost,
total_revenue
)
SELECT
o_id,
STR_TO_DATE(order_date, '%d/%m/%Y'),
STR_TO_DATE(ship_date, '%d/%m/%Y'),
c_id,
TRIM(lower(channel)),
trim(UPPER(currency_code)),
trim(warehouse_code),
r_id,
p_id,
o_quatity,
CAST(replace(unitprice,",","") AS DECIMAL(10,2)),
CAST(replace(total_unit_cost,",","") AS DECIMAL(10,2)),
CAST(replace(total_revenue,",","") AS DECIMAL(10,2))
FROM
(
SELECT *,
ROW_NUMBER() OVER
(
PARTITION BY o_id
ORDER BY o_id
) rn
FROM l_order
) x
WHERE rn = 1
AND o_id IS NOT NULL
AND c_id IS NOT NULL
AND p_id IS NOT NULL
AND o_quatity > 0
AND CAST(replace(total_revenue,",","") AS DECIMAL(10,2))>0;

select * from s_order;

INSERT INTO e_region
(
r_index,
r_suburbs,
r_city,
r_postcode,
r_longitude,
r_latitude,
r_fulladdress,
error_message
)

SELECT
r_index,
r_suburbs,
r_city,
r_postcode,
r_longitude,
r_latitude,
r_fulladdress,
'NULL_ERROR'
FROM l_region
WHERE 
r_city IS NULL
OR r_postcode IS NULL;

INSERT INTO e_region
(
r_index,
r_suburbs,
r_city,
r_postcode,
error_message
)

SELECT
r_index,
r_suburbs,
r_city,
r_postcode,
'DUPLICATE_ERROR'
FROM
(
SELECT *,
ROW_NUMBER() OVER
(
PARTITION BY r_index
ORDER BY r_index
) rn

FROM l_region

) x

WHERE rn > 1;

INSERT INTO e_region
(
r_index,
r_longitude,
r_latitude,
error_message
)
SELECT
r_index,
r_longitude,
r_latitude,
'VALIDATION_ERROR'
FROM l_region

WHERE
CAST(r_latitude AS DECIMAL(10,6)) NOT BETWEEN -90 AND 90
OR
CAST(r_longitude AS DECIMAL(10,6)) NOT BETWEEN -180 AND 180;

INSERT INTO s_region
(
r_index,
r_suburbs,
r_city,
r_postcode,
r_longitude,
r_latitude,
r_fulladdress
)

SELECT
r_index,
TRIM(r_suburbs),
TRIM(r_city),
TRIM(r_postcode),
CAST(r_longitude AS DECIMAL(10,6)),
CAST(r_latitude AS DECIMAL(10,6)),
TRIM(r_fulladdress)
FROM l_region
WHERE
r_city IS NOT NULL
AND r_postcode IS NOT NULL
AND CAST(r_latitude AS DECIMAL(10,6))
BETWEEN -90 AND 90
AND CAST(r_longitude AS DECIMAL(10,6))
BETWEEN -180 AND 180;

select * from s_region;

INSERT INTO e_product
(
    p_id,
    p_name,
    error_message
)
SELECT
    p_id,
    p_name,
    'NULL_ERROR'
FROM l_product
WHERE p_id IS NULL
   OR p_name IS NULL;
   
INSERT INTO e_product
(
    p_id,
    p_name,
    error_message
)
SELECT
    p_id,
    p_name,
    'DUPLICATE_ERROR'
FROM
(
    SELECT *,
           ROW_NUMBER() OVER
           (
               PARTITION BY p_id
               ORDER BY p_id
           ) AS rn
    FROM l_product
) x
WHERE rn > 1;

INSERT INTO e_product
(
    p_id,
    p_name,
    error_message
)
SELECT
    p_id,
    p_name,
    'BLANK_ERROR'
FROM l_product
WHERE TRIM(p_name) = '';

INSERT INTO s_product
(
    p_id,
    p_name
)
SELECT
    p_id,
    TRIM(p_name)
FROM
(
    SELECT *,
           ROW_NUMBER() OVER
           (
               PARTITION BY p_id
               ORDER BY p_id
           ) AS rn
    FROM l_product
) x
WHERE rn = 1
  AND p_id IS NOT NULL
  AND p_name IS NOT NULL
  AND TRIM(p_name) <> '';
  
  select * from l_customers;
  
  INSERT INTO e_customers
(
    id,
    c_name,
    error_message
)
SELECT
    id,
    c_name,
    'NULL_ERROR'
FROM l_customers
WHERE id IS NULL
   OR c_name IS NULL;
   
INSERT INTO e_customers
(
    id,
    c_name,
    error_message
)
SELECT
    id,
    c_name,
    'DUPLICATE_ERROR'
FROM
(
    SELECT *,
           ROW_NUMBER() OVER
           (
               PARTITION BY id
               ORDER BY id
           ) AS rn
    FROM l_customers
) x
WHERE rn > 1;

INSERT INTO e_customers
(
    id,
    c_name,
    error_message
)
SELECT
    id,
    c_name,
    'BLANK_ERROR'
FROM l_customers
WHERE TRIM(c_name) = '';

INSERT INTO s_customers
(
    id,
    c_name
)
SELECT
    id,
    TRIM(c_name)
FROM
(
    SELECT *,
           ROW_NUMBER() OVER
           (
               PARTITION BY id
               ORDER BY id
           ) AS rn
    FROM l_customers
) x
WHERE rn = 1
  AND id IS NOT NULL
  AND c_name IS NOT NULL
  AND TRIM(c_name) <> '';
  
  #dim table 
  
  CREATE TABLE dim_customer
(
    customer_id INT primary key,
    customer_name VARCHAR(100)
);

INSERT INTO dim_customer
(
    customer_id,
    customer_name
)
SELECT
    id,
    c_name
FROM s_customers;

CREATE TABLE dim_product
(
    product_id INT primary key,
    product_name VARCHAR(100)
);

INSERT INTO dim_product
(
    product_id,
    product_name
)
SELECT
    p_id,
    p_name
FROM s_product;

CREATE TABLE dim_region
(
    region_id INT primary key,
    suburb VARCHAR(100),
    city VARCHAR(100),
    postcode VARCHAR(20),
    longitude DECIMAL(10,6),
    latitude DECIMAL(10,6),
    full_address VARCHAR(255)
);
  
CREATE TABLE fact_sales
(
    order_id VARCHAR(50) primary key,
    customer_id INT,
    product_id INT,
    region_id INT,
    order_date DATE,
    ship_date DATE,
    channel VARCHAR(20),
    currency_code VARCHAR(20),
    warehouse_code VARCHAR(20),
    quantity INT,
    unit_price DECIMAL(10,2),
    total_unit_cost DECIMAL(10,2),
    total_revenue DECIMAL(10,2),
    CONSTRAINT fk_customer
        FOREIGN KEY (customer_id)
        REFERENCES dim_customer(customer_id),
    CONSTRAINT fk_product
        FOREIGN KEY (product_id)
        REFERENCES dim_product(product_id),
    CONSTRAINT fk_region
        FOREIGN KEY (region_id)
        REFERENCES dim_region(region_id)
);

CREATE TABLE etl_metadata
(
    job_id INT AUTO_INCREMENT PRIMARY KEY,
    job_name VARCHAR(100),
    start_time DATETIME,
    end_time DATETIME,
    status VARCHAR(20),
    records_loaded INT,
    records_rejected INT
);

CREATE TABLE etl_log
(
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    job_id INT,
    step_name VARCHAR(100),
    message VARCHAR(255),
    log_time DATETIME DEFAULT CURRENT_TIMESTAMP
);

use sales_db;

ALTER TABLE fact_sales
ADD CONSTRAINT fk1_customer
FOREIGN KEY (customer_id)
REFERENCES dim_customer(customer_id);

ALTER TABLE fact_sales
ADD CONSTRAINT fk1_product
FOREIGN KEY (product_id)
REFERENCES dim_product(product_id);

ALTER TABLE fact_sales
ADD CONSTRAINT fk1_region
FOREIGN KEY (region_id)
REFERENCES dim_region(region_id);


SHOW TABLES;
USE SALES_DB;

ALTER TABLE etl_metadata
ADD COLUMN last_load_time DATETIME;

ALTER TABLE etl_log
ADD COLUMN status VARCHAR(20);

ALTER TABLE l_order
ADD COLUMN load_time DATETIME DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE l_customers
ADD COLUMN load_time DATETIME DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE l_product
ADD COLUMN load_time DATETIME DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE l_region
ADD COLUMN load_time DATETIME DEFAULT CURRENT_TIMESTAMP;




