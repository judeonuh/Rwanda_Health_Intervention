-- ############################# CREATING DATABASE #################################
-- Create Doctors Table
DROP TABLE IF EXISTS rwanda_db.doctors;
CREATE TABLE IF NOT EXISTS rwanda_db.doctors(
doctors_id VARCHAR(10) PRIMARY KEY,
doctors_name VARCHAR(100),
specialty VARCHAR(50)
);

-- Import datasets into the table

-- Preview Doctors table
SELECT *
FROM rwanda_db.doctors;


-- Create Patient Mapping Table
DROP TABLE IF EXISTS mapping;
CREATE TABLE IF NOT EXISTS mapping(
patient_id VARCHAR(10),
patient_name VARCHAR(100),
health_score VARCHAR(20),
insurance_type VARCHAR(20),
physician_id VARCHAR(10),
blood_type VARCHAR(5),
city VARCHAR(20)
);

-- Import datasets into the table using the import wizard

-- Preview mapping table
SELECT *
FROM mapping;


-- Create Patient Records Fact Table. Declare all initial datatypes as varchar to account for inconsistencies in data entry
DROP TABLE IF EXISTS records_fact;
CREATE TABLE IF NOT EXISTS records_fact(
patient_id VARCHAR(10),
visit_date VARCHAR(20),
age VARCHAR(50),
gender VARCHAR(10),
diagnosis VARCHAR(100),
treatment_cost VARCHAR(50),
doctor_id VARCHAR(10),
treatment_type VARCHAR(20)
);

-- Import datasets into table (Duplicates removed during import) using import wizard

-- Preview table
SELECT *
FROM records_fact;


-- Create Wellness Activity Table
DROP TABLE IF EXISTS activity;
CREATE TABLE IF NOT EXISTS activity(
patient_id VARCHAR(10),
activity_type VARCHAR(20),
activity_date VARCHAR(20),
duration_minutes VARCHAR(20),
wellness_status VARCHAR(20)
);

-- Import datasets into table

-- Preview activity table
SELECT *
FROM activity;


-- ############################# DATA CLEANING #################################

-- MANAGE TRANSACTION 

BEGIN;

ROLLBACK;

COMMIT;

-- ################################# Cleaning Doctors table #########
SELECT *
FROM doctors;

UPDATE doctors
SET doctors_name = trim(INITCAP(doctors_name))


-- ################################# Cleaning Records_fact table #########

SELECT *
FROM records_fact;


-- Check for Duplicates on records_fact table
SELECT 
	patient_id,
	visit_date,
	age,
	gender,
	diagnosis,
	treatment_cost,
	doctor_id,
	treatment_type,
	COUNT(*) AS num
FROM records_fact
GROUP BY 
	patient_id,
	visit_date,
	age,
	gender,
	diagnosis,
	treatment_cost,
	doctor_id,
	treatment_type
HAVING COUNT(*) > 1
ORDER BY num DESC;


-- Remove Duplicates from records_fact table
DELETE FROM records_fact a
USING records_fact b
WHERE a.ctid < b.ctid
  	AND a.patient_id = b.patient_id
  	AND a.visit_date = b.visit_date
	AND a.age = b.age
	AND a.gender = b.gender
	AND a.diagnosis = b.diagnosis
	AND a.treatment_cost = b.treatment_cost
	AND a.doctor_id = b.doctor_id
	AND a.treatment_type = b.treatment_type
  ;


-- Clean treatment_type Column
SELECT 
	DISTINCT treatment_type
FROM records_fact;


SELECT 
	COUNT(*)  -- Check number of null values
FROM records_fact
WHERE treatment_type IS NULL;


-- Clean doctor_id Column
SELECT 
	DISTINCT doctor_id
FROM records_fact;


SELECT 
	COUNT(*)  -- Check number of null values
FROM records_fact
WHERE doctor_id IS NULL;


-- Clean treatment cost column
SELECT
	DISTINCT treatment_cost
FROM records_fact
WHERE treatment_cost !~ '^[0-9]+(\.[0-9]+)?$';  -- Filters out integers and decimals


UPDATE records_fact
SET treatment_cost = CASE
	WHEN treatment_cost = '1,250.00' THEN '1250.0'
	WHEN treatment_cost = 'error' THEN NULL
	WHEN treatment_cost = 'missing' THEN NULL
	WHEN treatment_cost = 'two hundred' THEN '200.0'
	WHEN treatment_cost = 'free' THEN '0.00'
	ELSE treatment_cost
END;


ALTER TABLE records_fact  -- Change data type for cost column
ALTER COLUMN treatment_cost TYPE NUMERIC
USING treatment_cost::NUMERIC;  -- 'USING' casts values before changing the column datatype


SELECT 
	COUNT(*)  -- Check number of null values (~ 1800)
FROM records_fact
WHERE treatment_cost IS NULL;


ALTER TABLE records_fact  -- Add a new column to handle null values in the treatment_cost column
ADD COLUMN IF NOT EXISTS cost_imputed NUMERIC;


WITH medn  -- Calculate median
	AS (SELECT percentile_cont(0.5) 
		WITHIN GROUP (ORDER BY treatment_cost) AS median_cost
  		FROM records_fact
  		WHERE treatment_cost IS NOT NULL
		)
UPDATE records_fact -- Update the new column with median inputation while keeping the original data
SET cost_imputed = COALESCE(treatment_cost, medn.median_cost)
FROM medn
WHERE cost_imputed IS NULL;   -- optional: update only rows not yet set


-- Clean diagnosis Column
SELECT 
	DISTINCT diagnosis
FROM records_fact;

SELECT 
	COUNT(*)  -- Check number of null values
FROM records_fact
WHERE diagnosis IS NULL;


-- Clean gender Column
SELECT 
	DISTINCT gender
FROM records_fact;


UPDATE records_fact  -- Standardise Gender entries
SET gender = CASE
	WHEN gender = 'M' THEN 'Male'
	WHEN gender = 'F' THEN 'Female'
	WHEN gender IN ('123', '?') THEN NULL
ELSE gender
END;


SELECT 
	COUNT(*)  -- Check number of null values (over 10,000)
FROM records_fact
WHERE gender IS NULL;


UPDATE records_fact -- Handle null values
SET gender = 'Unknown'
WHERE gender IS NULL;


-- Clean Age Column
SELECT 
	COUNT(*)
FROM records_fact
WHERE age IS NULL;

SELECT 
	DISTINCT	age
FROM records_fact
WHERE age !~ '^[0-9]+$';  -- Filter out integers and decimals;


UPDATE records_fact  -- Replace invalid age entries
SET age = CASE
	WHEN age = 'thirty-five' THEN '35'
	WHEN age = '-5' THEN '5'
ELSE age
END;


UPDATE records_fact  -- Replace 'unknown' with NULL to aid casting
SET age = NULL
WHERE age = 'unknown';


ALTER TABLE records_fact  -- Change column datatype
ALTER age TYPE INT
USING age::INT;


UPDATE records_fact  -- Substitute null values with median age, as there are outliers
SET age = sub.median_age
FROM (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY age) AS median_age
    FROM records_fact
    WHERE age IS NOT NULL
) AS sub
WHERE age IS NULL;


-- Clean Visit_Date Column
SELECT 
	DISTINCT visit_date
FROM records_fact;


SELECT 
	visit_date  -- Check for Null values
FROM records_fact
WHERE visit_date IS NULL;


ALTER TABLE records_fact  -- Add Column for cleaned Dates
ADD COLUMN visit_date_clean DATE;

UPDATE records_fact  -- Populate Column with cleaned Dates
SET visit_date_clean =
    CASE
		WHEN visit_date ~ '^[A-Za-z]{3}\s\d{1,2},\s\d{4}$' -- Format: jan 14, 2025
			THEN TO_DATE(TRIM(visit_date), 'Mon DD, YYYY')
		WHEN visit_date ~ '^[A-Za-z]{3,9}\s\d{1,2},\s\d{4}$' -- Format: january 14, 2025
			THEN TO_DATE(TRIM(visit_date), 'Month DD, YYYY')
		WHEN visit_date ~ '^\d{1,2}-[A-Za-z]{3}-\d{4}$'  -- Format: 01-jan-2024
			THEN TO_DATE(TRIM(visit_date), 'DD-Mon-YYYY')
		WHEN visit_date ~ '^\d{1,2}-\d{1,2}-\d{4}$'  -- Format: DD-MM-YYYY
			THEN TO_DATE(TRIM(visit_date), 'DD-MM-YYYY')
		WHEN visit_date ~ '^\d{4}-\d{2}-\d{2}$'  -- Format: YYYY-MM-DD
			THEN TO_DATE(TRIM(visit_date), 'YYYY-MM-DD')
		WHEN visit_date ~ '^\d{4}/\d{2}/\d{2}$'  -- Format: YYYY/MM/DD
			THEN TO_DATE(TRIM(visit_date), 'YYYY-MM-DD')
		ELSE visit_date::DATE
    END;


-- ################################ Cleaning activity table ###############
SELECT *
FROM activity;

-- Check inconsistency in columns
SELECT 
	DISTINCT activity_type
FROM activity;

SELECT 
	DISTINCT wellness_status
FROM activity;

-- Clean Activity_Date column
SELECT 
	DISTINCT activity_date
FROM activity;

ALTER TABLE activity  -- Create Column for clean Dates
ADD COLUMN activity_date_clean DATE;


UPDATE activity  -- Populate Column with cleaned Dates
SET activity_date_clean =
    CASE
		WHEN activity_date ~ '^[A-Za-z]{3}\s\d{1,2},\s\d{4}$' -- Format: jan 14, 2025
			THEN TO_DATE(TRIM(activity_date), 'Mon DD, YYYY')
		WHEN activity_date ~ '^[A-Za-z]{3,9}\s\d{1,2},\s\d{4}$' -- Format: january 14, 2025 
			THEN TO_DATE(TRIM(activity_date), 'Month DD, YYYY')
		WHEN activity_date ~ '^\d{1,2}-[A-Za-z]{3}-\d{4}$'  -- Format: 01-jan-2024
			THEN TO_DATE(TRIM(activity_date), 'DD-Mon-YYYY')
		WHEN activity_date ~ '^\d{1,2}-\d{1,2}-\d{4}$'  -- Format: DD-MM-YYYY
			THEN TO_DATE(TRIM(activity_date), 'DD-MM-YYYY')
		WHEN activity_date ~ '^\d{4}-\d{2}-\d{2}$'  -- Format: YYYY-MM-DD
			THEN TO_DATE(TRIM(activity_date), 'YYYY-MM-DD')
		WHEN activity_date ~ '^\d{4}/\d{2}/\d{2}$'  -- Format: YYYY/MM/DD
			THEN TO_DATE(TRIM(activity_date), 'YYYY-MM-DD')
		ELSE activity_date::DATE
    END;


ALTER TABLE activity  -- Drop messy Date Column
DROP COLUMN activity_date;


-- Check for Duplicates on the activity table
SELECT 
	patient_id,
	activity_type,
	activity_date_clean,
	duration_minutes,
	wellness_status,
	COUNT(*) AS num
FROM activity
GROUP BY
	patient_id,
	activity_type,
	activity_date_clean,
	duration_minutes,
	wellness_status
HAVING COUNT(*) > 1
ORDER BY num;


-- Delete Duplicate records from the activity table
DELETE FROM activity a
USING activity b
WHERE a.ctid < b.ctid
	AND a.patient_id = b.patient_id
	AND a.activity_type = b.activity_type
	AND a.activity_date_clean = b.activity_date_clean
	AND a.duration_minutes = b.duration_minutes
	AND a.wellness_status = b.wellness_status
	;


ALTER TABLE activity
ALTER COLUMN duration_minutes TYPE INT
USING duration_minutes::INT;

-- ############################# Cleaning Mapping Table #############

SELECT *
FROM mapping;

-- Check for Nulls
SELECT *
FROM mapping
WHERE patient_id IS NULL OR
	patient_name IS NULL OR
	health_score IS NULL OR
	insurance_type IS NULL OR
	physician_id IS NULL OR
	blood_type IS NULL OR
	city IS NULL;


-- Change health_score column data type
ALTER TABLE mapping
ALTER COLUMN health_score TYPE INT
USING health_score::INT;


-- Clean patient_name column
SELECT 
	DISTINCT patient_name
FROM mapping;

UPDATE mapping
SET patient_name = trim(INITCAP(patient_name));


-- Clean insurance_type column
SELECT 
	DISTINCT insurance_type
FROM mapping;

UPDATE mapping
SET insurance_type = CASE
	WHEN insurance_type = 'privatte' THEN 'Private'
	WHEN insurance_type = 'GOV' THEN 'Government'
	WHEN insurance_type = 'PUBLic' THEN 'Public'
	WHEN insurance_type = 'Govt' THEN 'Government'
	WHEN insurance_type = 'N/A' THEN 'None'
	ELSE insurance_type
END;


-- Clean blood_type Column
SELECT 
	DISTINCT blood_type
FROM mapping;


-- Cleaning city column
SELECT 
	DISTINCT city
FROM mapping;

-- ############################################# TASKS #################################
-- Step 1: Calculate total annual cost per patient to produce the set of high-cost patients (top 5%)
WITH patient_costs AS (
    SELECT mp.patient_id,
           SUM(rf.cost_imputed) AS total_cost
    FROM mapping AS mp
    JOIN records_fact AS rf 
		ON mp.patient_id = rf.patient_id
    GROUP BY mp.patient_id
),
ranked_costs AS (
    SELECT patient_id,
           total_cost,
           NTILE(20) OVER (ORDER BY total_cost DESC) AS cost_percentile
    FROM patient_costs
)
SELECT 
	patient_id AS high_cost_patient, 
	total_cost
FROM ranked_costs
WHERE cost_percentile = 1  -- top 5% high-cost patients
ORDER BY total_cost DESC;


-- *********************** TRY ********************************** 
-- Create a view to store all high-cost patients
BEGIN;
ROLLBACK;
COMMIT;


CREATE OR REPLACE VIEW high_cost_patients_vw AS
WITH patient_costs AS (
    SELECT mp.patient_id,
           SUM(rf.cost_imputed) AS total_cost
    FROM mapping AS mp
    JOIN records_fact AS rf 
      ON mp.patient_id = rf.patient_id
    GROUP BY mp.patient_id
),
ranked_costs AS (
    SELECT patient_id,
           total_cost,
           NTILE(20) OVER (ORDER BY total_cost DESC) AS cost_percentile
    FROM patient_costs
)
SELECT patient_id, total_cost
FROM ranked_costs
WHERE cost_percentile = 1;   -- top 5%


-- Preview View 
SELECT *
FROM high_cost_patients_vw;


-- This shows one patient can have several visits, diagnosis, treatment_type, etc.
SELECT *
FROM records_fact
WHERE patient_id = 'P2450';


-- Aggregated Metrics for High-cost patients (total cost, visit count, wellness activity count)
SELECT
	h.patient_id,
	h.total_cost,
	ROUND(AVG(m.health_score), 2) AS avg_health_score,
	COUNT(rf.visit_date_clean) AS visit_count,
	COUNT(a.activity_type) AS activity_count,
	ROUND(AVG(a.duration_minutes), 2) AS avg_activity_duration
FROM high_cost_patients_vw AS h
JOIN records_fact AS rf
	ON rf.patient_id = h.patient_id
JOIN mapping AS m
	ON m.patient_id = h.patient_id
JOIN activity AS a
	ON a.patient_id = h.patient_id
GROUP BY h.patient_id, h.total_cost
ORDER BY h.total_cost DESC;


-- Doctor specialty mostly associated with high-cost patients
SELECT d.specialty,
       COUNT(DISTINCT h.patient_id) AS num_high_cost_patients,
       ROUND(AVG(rf.cost_imputed), 2) AS avg_cost_per_visit
FROM doctors d
JOIN records_fact AS rf
	ON rf.doctor_id = d.doctors_id
JOIN high_cost_patients_vw AS h
	ON h.patient_id = rf.patient_id
GROUP BY specialty
ORDER BY num_high_cost_patients DESC;


-- Doctor specialty mostly associated with other patients
SELECT d.specialty,
       COUNT(DISTINCT rf.patient_id) AS total_patients,
       ROUND(AVG(rf.cost_imputed), 2) AS avg_cost_per_visit
FROM doctors AS d
JOIN records_fact AS rf
	ON rf.doctor_id = d.doctors_id
WHERE rf.patient_id NOT IN (
	SELECT patient_id
	FROM high_cost_patients_vw
	)
GROUP BY specialty
ORDER BY total_patients DESC;


-- Comparison between high-cost and non-high-cost patients based on doctor's specialty
(
	-- High cost patients
	SELECT d.specialty AS top_specialty,
	       COUNT(DISTINCT h.patient_id) AS total_patients,
	       ROUND(AVG(rf.cost_imputed), 2) AS avg_cost_per_visit,
		   'High_cost' AS patient_group
	FROM doctors d
	JOIN records_fact AS rf
		ON rf.doctor_id = d.doctors_id
	JOIN high_cost_patients_vw AS h
		ON h.patient_id = rf.patient_id
	GROUP BY specialty
	ORDER BY total_patients DESC
	LIMIT 2
)
UNION ALL
(
	-- Other patients
	SELECT d.specialty AS top_specialty,
	       COUNT(DISTINCT rf.patient_id) AS total_patients,
	       ROUND(AVG(rf.cost_imputed), 2) AS avg_cost_per_visit,
		   'Other' AS patient_group
	FROM doctors AS d
	JOIN records_fact AS rf
		ON rf.doctor_id = d.doctors_id
	WHERE rf.patient_id NOT IN (
		SELECT patient_id
		FROM high_cost_patients_vw
		)
GROUP BY specialty
ORDER BY total_patients DESC
LIMIT 2
);


-- Diagnosis mostly associated with high-cost patients
SELECT
	rf.diagnosis,
	COUNT(DISTINCT h.patient_id) AS num_high_cost_patients,
	ROUND(AVG(rf.cost_imputed), 2) AS avg_cost_per_visit
FROM records_fact AS rf
JOIN high_cost_patients_vw AS h
	ON h.patient_id = rf.patient_id
GROUP BY rf.diagnosis
ORDER BY num_high_cost_patients DESC;


-- Diagnosis mostly associated with other patients
SELECT
	diagnosis,
	COUNT(DISTINCT patient_id) AS total_patients,
	ROUND(AVG(cost_imputed), 2) AS avg_cost_per_visit
FROM records_fact
WHERE patient_id NOT IN (
	SELECT patient_id
	FROM high_cost_patients_vw
)
GROUP BY diagnosis
ORDER BY total_patients DESC;


/*
-- Horizontal Comparison between high-cost and non-high-cost patients based on diagnosis
SELECT
    rf.diagnosis,
    COUNT(DISTINCT CASE WHEN h.patient_id IS NOT NULL THEN h.patient_id END) AS total_high_cost_patients,
    COUNT(DISTINCT CASE WHEN h.patient_id IS NULL THEN rf.patient_id END) AS total_other_patients
FROM records_fact rf
LEFT JOIN high_cost_patients_vw h
    ON rf.patient_id = h.patient_id
GROUP BY rf.diagnosis
ORDER BY total_high_cost_patients DESC;
*/


-- Comparison between high-cost and non-high-cost patients based on diagnosis
(
	-- High-cost patients
	SELECT
		rf.diagnosis AS top_diagnosis,
		COUNT(DISTINCT h.patient_id) AS num_patients,
		'High_cost' AS patient_group
	FROM records_fact rf
	JOIN high_cost_patients_vw h
		ON rf.patient_id = h.patient_id
	GROUP BY rf.diagnosis
	ORDER BY num_patients DESC
	LIMIT 3
)
UNION ALL
(
    -- Other patients
    SELECT
        rf.diagnosis AS top_diagnosis,
        COUNT(DISTINCT rf.patient_id) AS num_patients,
        'Other' AS patient_group
    FROM records_fact rf
    WHERE rf.patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
    GROUP BY rf.diagnosis
    ORDER BY num_patients DESC
    LIMIT 3
);


-- Treatment type mostly associated with high-cost patients
SELECT
	rf.treatment_type,
	COUNT(DISTINCT h.patient_id) AS num_high_cost_patients,
	ROUND(AVG(rf.cost_imputed), 2) AS avg_cost_per_visit
FROM records_fact AS rf
JOIN high_cost_patients_vw AS h
	ON h.patient_id = rf.patient_id
GROUP BY rf.treatment_type
ORDER BY num_high_cost_patients DESC;


-- Treatment type mostly associated with other patients
SELECT
	treatment_type,
	COUNT(DISTINCT patient_id) AS total_patients,
	ROUND(AVG(cost_imputed), 2) AS avg_cost_per_visit
FROM records_fact
WHERE patient_id NOT IN (
	SELECT patient_id
	FROM high_cost_patients_vw
)
GROUP BY treatment_type
ORDER BY total_patients DESC;


-- Comparison between high-cost and non-high-cost patients based on treatment type
(
	-- High-cost patients
	SELECT
		rf.treatment_type AS top_treatment_type,
		COUNT(DISTINCT h.patient_id) AS num_patients,
		'High_cost' AS patient_group
	FROM records_fact rf
	JOIN high_cost_patients_vw h
		ON rf.patient_id = h.patient_id
	GROUP BY rf.treatment_type
	ORDER BY num_patients DESC
	LIMIT 3
)
UNION ALL
(
    -- Other patients
    SELECT
        rf.treatment_type AS top_treatment_type,
        COUNT(DISTINCT rf.patient_id) AS num_patients,
        'Other' AS patient_group
    FROM records_fact rf
    WHERE rf.patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
    GROUP BY rf.treatment_type
    ORDER BY num_patients DESC
    LIMIT 3
);


-- Wellness activities associated with high-cost patients
SELECT
	a.activity_type,
	ROUND(AVG(a.duration_minutes), 2) AS avg_duration,
	COUNT(DISTINCT h.patient_id) AS num_high_cost_patients
FROM activity AS a
JOIN high_cost_patients_vw AS h
	ON h.patient_id = a.patient_id
GROUP BY a.activity_type
ORDER BY num_high_cost_patients DESC;


-- Wellness activities associated with non high-cost patients
SELECT
	activity_type,
	ROUND(AVG(duration_minutes), 2) AS avg_duration,
	COUNT(DISTINCT patient_id) AS total_patients
FROM activity
WHERE patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
GROUP BY activity_type
ORDER BY total_patients DESC;


-- Comparison between high-cost and non-high-cost patients based on wellness activity
(
	-- High Cost Patients
	SELECT
		a.activity_type AS top_activity_type,
		ROUND(AVG(a.duration_minutes), 2) AS avg_duration,
		COUNT(DISTINCT h.patient_id) AS total_patients,
		'High_cost' AS patient_group
	FROM activity AS a
	JOIN high_cost_patients_vw AS h
		ON h.patient_id = a.patient_id
	GROUP BY a.activity_type
	ORDER BY total_patients DESC
	LIMIT 3
)
UNION ALL
(
	-- Other Patients
	SELECT
		activity_type AS top_activity_type,
		ROUND(AVG(duration_minutes), 2) AS avg_duration,
		COUNT(DISTINCT patient_id) AS total_patients,
		'Others' AS patient_group
	FROM activity
	WHERE patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
	GROUP BY activity_type
	ORDER BY total_patients DESC
	LIMIT 3
);


-- Cities where most high-cost patients reside
SELECT
	m.city,
	COUNT(DISTINCT h.patient_id) AS num_high_cost_patients
FROM mapping AS m
JOIN high_cost_patients_vw AS h
	ON h.patient_id = m.patient_id
GROUP BY m.city
ORDER BY num_high_cost_patients DESC;


-- Cities where other patients reside
SELECT
	city,
	COUNT(DISTINCT patient_id) AS total_patients
FROM mapping
WHERE patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
GROUP BY city
ORDER BY total_patients DESC;


-- Comparison between high-cost and non-high-cost patients based on City
(
	-- High Cost Patients
	SELECT
		m.city AS top_cities,
		COUNT(DISTINCT h.patient_id) AS num_high_cost_patients,
		'High_cost' AS patient_group
	FROM mapping AS m
	JOIN high_cost_patients_vw AS h
		ON h.patient_id = m.patient_id
	GROUP BY m.city
	ORDER BY num_high_cost_patients DESC
	LIMIT 3
)
UNION ALL
(
	-- Other Patients
	SELECT
		city AS top_cities,
		COUNT(DISTINCT patient_id) AS total_patients,
		'Others' AS patient_group
	FROM mapping
	WHERE patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
	GROUP BY city
	ORDER BY total_patients DESC
	LIMIT 3
);


-- Insurance type mostly associated with high-cost patients
SELECT
	m.insurance_type,
	COUNT(DISTINCT h.patient_id) AS num_high_cost_patients
FROM mapping AS m
JOIN high_cost_patients_vw AS h
	ON h.patient_id = m.patient_id
GROUP BY m.insurance_type
ORDER BY num_high_cost_patients DESC;


-- Insurance type mostly associated with non high-cost patients
SELECT
	insurance_type,
	COUNT(DISTINCT patient_id) AS total_patients
FROM mapping
WHERE patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
GROUP BY insurance_type
ORDER BY total_patients DESC;


-- Comparison between high-cost and non-high-cost patients based on Insurance type
(
	-- High Cost Patients
	SELECT
		m.insurance_type AS top_insurance_type,
		COUNT(DISTINCT h.patient_id) AS num_high_cost_patients,
		'High_cost' AS patient_group
	FROM mapping AS m
	JOIN high_cost_patients_vw AS h
		ON h.patient_id = m.patient_id
	GROUP BY m.insurance_type
	ORDER BY num_high_cost_patients DESC
	LIMIT 2
)
UNION ALL
(
	-- Other Patients
	SELECT
		insurance_type AS top_insurance_type,
		COUNT(DISTINCT patient_id) AS total_patients,
		'Others' AS patient_group
	FROM mapping
	WHERE patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
	GROUP BY insurance_type
	ORDER BY total_patients DESC
	LIMIT 2
);


-- Blood type mostly associated with high-cost patients
SELECT
	m.blood_type,
	COUNT(DISTINCT h.patient_id) AS num_high_cost_patients
FROM mapping AS m
JOIN high_cost_patients_vw AS h
	ON h.patient_id = m.patient_id
GROUP BY m.blood_type
ORDER BY num_high_cost_patients DESC;


-- Blood type mostly associated with non high-cost patients
SELECT
	blood_type,
	COUNT(DISTINCT patient_id) AS total_patients
FROM mapping
WHERE patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
GROUP BY blood_type
ORDER BY total_patients DESC;


-- Comparison between high-cost and non-high-cost patients based on Blood type
(
	-- High Cost Patients
	SELECT
		m.blood_type AS top_blood_type,
		COUNT(DISTINCT h.patient_id) AS num_high_cost_patients,
		'High_cost' AS patient_group
	FROM mapping AS m
	JOIN high_cost_patients_vw AS h
		ON h.patient_id = m.patient_id
	GROUP BY m.blood_type
	ORDER BY num_high_cost_patients DESC
	LIMIT 3
)
UNION ALL
(
	-- Other Patients
	SELECT
		blood_type AS top_blood_type,
		COUNT(DISTINCT patient_id) AS total_patients,
		'Others' AS patient_group
	FROM mapping
	WHERE patient_id NOT IN (SELECT patient_id FROM high_cost_patients_vw)
	GROUP BY blood_type
	ORDER BY total_patients DESC
	LIMIT 3
);




-- Activity days mostly associated with high-cost patients


