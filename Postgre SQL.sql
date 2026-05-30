-- table was earlier created but create query not save by postgres, this create statement was copied here from the existing table
CREATE TABLE IF NOT EXISTS public.american_bankruptcy
(
    company_name character varying(50) COLLATE pg_catalog."default",
    status_label text COLLATE pg_catalog."default",
    years numeric,
    x1 numeric,
    x2 numeric,
    x3 numeric,
    x4 numeric,
    x5 numeric,
    x6 numeric,
    x7 numeric,
    x8 numeric,
    x9 numeric,
    x10 numeric,
    x11 numeric,
    x12 numeric,
    x13 numeric,
    x14 numeric,
    x15 numeric,
    x16 numeric,
    x17 numeric,
    x18 numeric
)

-- checking for null values
SELECT *
FROM american_bankruptcy
WHERE (company_name,status_label,years,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15,x16,x17,x18) isnull;

-- check and comfirm duplicates
WITH cte AS (
SELECT *,
row_number() OVER (PARTITION BY company_name,status_label,years,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15,x16,x17,x18) AS duplicate
FROM american_bankruptcy;
)
SELECT * FROM cte
WHERE duplicate >1;

-- EXPLORATORY DATA ANALYSIS A.K.A Data profi

-- Total number of companies
SELECT COUNT(DISTINCT(company_name)) AS Total_companies
FROM american_bankruptcy;
-- OR (showing )
SELECT 
    COUNT(*) FILTER (WHERE ever_failed = 1) AS failed_companies,
    COUNT(*) FILTER (WHERE ever_failed = 0) AS always_alive
FROM (
    SELECT 
        company_name,
        MAX(CASE WHEN status_label = 'failed' THEN 1 ELSE 0 END) AS ever_failed
    FROM american_bankruptcy
    GROUP BY company_name
) t;

-- Number of companies that reportedly failed VS alive


-- Reported Failures per year
SELECT
	DISTINCT(years),
	COUNT(status_label) AS failures
FROM american_bankruptcy
WHERE status_label = 'failed'
GROUP BY years;

-- Create views 
CREATE VIEW bankruptcy_view AS
SELECT * FROM american_bankruptcy;

-- these column is not suppose to have negative value
SELECT total_assets, total_current_assets, total_receivable,inventory,total_operating_expenses
FROM bankruptcy_view
WHERE total_assets < 0 
or total_current_assets < 0
or total_receivable < 0
or inventory < 0
or total_operating_expenses < 0;

-- Data mapping
ALTER VIEW bankruptcy_view
RENAME COLUMN total_current_assets TO total_current_liabilities; -- queries wiped by postgres, this was copied for to rename other columns

select * from bankruptcy_view;
-- feature engineering (altman Z-score ratios & new flag) 
-- creating a second view to capture recent change
CREATE VIEW bankruptcy_view2 AS
WITH feature_engineering AS (
	SELECT *,
		round(1.2*(current_assets-total_current_liabilities)/total_current_liabilities,4) AS X1_liquidity, -- liquidity
		round(1.4*(retained_earnings/total_assets),4) AS X2_profitability, --profitablilty & accummulated earnings
		round(3.3*(ebit/total_assets),4) AS X3_efficiency, -- operating efficiency
		round(0.6*(market_value/total_liabilities),4) AS X4_solvency, -- solvency
		round(0.999*(net_sales/total_assets),4) AS X5_asset_turnover  --asset turnover
	FROM bankruptcy_view
)
SELECT *,
	(X1_liquidity+X2_profitability+X3_efficiency+X4_solvency+X5_asset_turnover) AS z_score,
	-- creating a model
	CASE
		WHEN (X1_liquidity+X2_profitability+X3_efficiency+X4_solvency+X5_asset_turnover) < 1.8 THEN 'high'
		WHEN (X1_liquidity+X2_profitability+X3_efficiency+X4_solvency+X5_asset_turnover) BETWEEN 1.8 AND 3.0 THEN 'moderate'
	ELSE 'low'
    END AS risk_scoring
FROM feature_engineering;

-- check status_label against risk score (confusion-matrix-style evaluation of the model)
SELECT 
    status_label,
    risk_scoring,
    COUNT(*) AS count
FROM bankruptcy_view2
GROUP BY status_label, risk_scoring;

-- factors that actually drives bankruptcy
-- regardless of other variable, on the avg, coy in both category actually has issues with profitablity, but
-- that does not cause them to fail, coy in failed category actuall failed bcos of poor liquidity to meet to meet
-- reoccuring operational expenses.
SELECT 
    AVG(X1_liquidity) AS avg_liquidity,
    AVG(X2_profitability) AS avg_profitability,
    AVG(X3_efficiency) AS avg_efficiency,
    AVG(X4_solvency) AS avg_solvency,
    AVG(X5_asset_turnover) AS avg_turnover
FROM bankruptcy_view2
WHERE risk_scoring = 'high';

SELECT 
    AVG(X1_liquidity) AS avg_liquidity,
    AVG(X2_profitability) AS avg_profitability,
    AVG(X3_efficiency) AS avg_efficiency,
    AVG(X4_solvency) AS avg_solvency,
    AVG(X5_asset_turnover) AS avg_turnover
FROM bankruptcy_view2
WHERE risk_scoring = 'low';

-- Time-based analysis
SELECT 
    years,
    AVG(z_score) AS avg_z_score,
    COUNT(*) FILTER (WHERE risk_scoring='high') AS failures
FROM bankruptcy_view2
GROUP BY years
ORDER BY years;

-- Number of companies that is alive VS grey zone VS failed
SELECT 
	Count(risk_scoring) filter (WHERE risk_scoring = 'low') AS alive,
	Count(risk_scoring) filter (WHERE risk_scoring = 'moderate') AS grey_zone,
	Count(risk_scoring) filter (WHERE risk_scoring = 'high') AS failed
FROM bankruptcy_view2;




