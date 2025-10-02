# Rwanda Health Intervention

## Background of the Problem
The leadership at a Rwandan health clinic has determined that a small percentage of patients account for a disproportionately high amount of healthcare costs. 
They want to launch a targeted intervention program to provide better proactive care for these individuals, but first, they need to understand who they are.

## Aim
The project is aimed at creating a detailed profile of these "high-cost patients", identifying the key clinical, demographic, and lifestyle characteristics that differentiate them from the general patient population. 

## 📁 Table of Contents
- [Background of the Problem](#background-of-the-problem)
- [Aim](#aim)  
- [Data Overview](#data-overview)  
- [Methodology](#methodology)
- [Data Cleaning](#data-cleaning)
- [Analysis and Recommendations](#analysis-and-recommendations)  
- [Overall Recommendations](#overall-recommendations)  
- [Conclusion](#conclusion)  

---

## Data Overview
- **Source:-** Four table, one each for Patients records, Doctors, Wellness activity, and Patient mapping. 
- **Key Data Points:-** doctors name, specialty, patient health_score, insurance_type, city, age, gender, diagnosis, treatment cost, treatment_type,
  activity_type, duration_minutes, and wellness_status.

---

## Methodology
- Datasets were imported into and queried in PgAdmin using **PosgreSQL-compliant SQL queries**.
- All SQL queries can be found [here]().
> [!WARNING]
> When creating the database, all column datatypes were defined as VARCHAR to avoid losing records upon import.
- High-cost patients were defined as the top 5% based on treatment_cost. This number is subject to your discretion.
- A comparative profile was drafted, separating 'high-cost' from 'non-high-cost' segments/patients across the following dimensions:
    * Clinical: What are the most common diagnoses? How many visits do they average? Which doctor specialties do they see most often?
    * Demographic: What is their average health_score? Which insurance_type and city are most common?
    * Wellness: How do their wellness habits (e.g., number of activities, types of activities, reported wellness_status) compare?
- Created agregated metrics for each high-cost patient (e.g., total cost, visit count, wellness activity count).

---

## Data Cleaning  
- All tables were checked for duplicates, null values and inconsistent entries. Duplicates were dropped, null values replaced with either a string (e.g. 'Unknown') or median of values.
  Inconsistent entries were replaced with appropriate ones. For instance...
  
  ```SQL
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
  ```
  
- Added additional columns where necessary to handle null values in integer columns. For instance...  
  
  ```SQL
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
  ```

- Changed column datatypes to the appropriate types.
- Created a View to store all high-cost patients.

---

## Analysis and Recommendations

### 1.  High-cost Patients
High-cost patients were defined as the top 5% based on treatment cost. This totalled up to **163 patients**, obtained using the query below...  

```SQL
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

```

---

### 2. Common features between high-cost and other patients
High-cost and General Population Patients both have the following in common:
- Most visited Doctor's specialty:-  General Practice
- Most common diagnosis:- Migraine and Malaria
- Most common treatment type:- Outpatient
- Most common activity type:- Hydration
- Most common Blood type:- B+

---

### 3. Cities mostly associated with high-cost patients and how they compare with the general population patients
Most high-cost patients visited doctors in Huye, while the general population patients predominantly visited doctors in Rubavu. Based on further research, this observation may be due to the presence of
the University Teaching Hospital of Butare (CHUB) which has seen most patients with serious, complicated or chronic conditions referred here. These conditions usually require surgeries and long hospital stays,
hence the higher treatment cost.

On the other hand, Rubavu may have seen more patients because of its high population density and cross-border trade.

---

### 4. Insurance type mostly associated with high-cost patients and how they compare with the general population patients 
Most high-cost patients prefer insurance schemes run by private insurance companies. The premiums are higher, but coverage is broader and may include access to private hospitals and quicker services.
Conversely, the data shows that other patients are mostly enrolled into government insurance schemes, probably because it is subsidised by the government and international donors.

---

### 5.  

---

### 6. 

|           |      |   |  
|--------------------|-------------|------------------|  
|    |    |       |  
|    |   |      |    


---

## Overall Recommendations for Intervention Program
-   

---

## Conclusion

