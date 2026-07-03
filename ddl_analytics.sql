/*
======================================================================
SCRIPT - Create Analytics Views 
======================================================================
Project     : NAVA Data Warehouse
Script      : load_analytics.sql

Description :

Creates analytics-ready views in the NAVA_analytics database.

The analytics layer combines cleaned data into business-oriented views
designed for reporting and dashboarding.

These views provide the curated datasets used by the Sales Performance,
Budget Performance and Marketing Performance dashboards.

WARNING:

Existing analytics views will be dropped and recreated.
======================================================================
*/

-- ====================================================================
-- 01 Sales Performance view
-- ====================================================================

CREATE OR REPLACE VIEW NAVA_analytics.v_sales_net AS
  
SELECT
  s.order_id,
  s.order_line_id,
  s.order_date,
  s.customer_id,
  s.product_id,
  l.country,
  s.ship_date,
  s.delivery_date,
  s.ship_mode,
  s.quantity,
  s.unit_price,
  s.discount,
  s.quantity * s.unit_price AS gross_sales, -- Calculate gross sales before discounts
  (s.quantity * s.unit_price) * s.discount AS discount_amount, -- Calculate discount amount
  s.net_sales,
  s.quantity * p.standard_cost AS cogs, -- Calculate cost of goods sold
  COALESCE(r.return_amount, 0) AS return_amount,
  COALESCE(r.return_quantity, 0) AS return_quantity,
  s.net_sales - COALESCE(r.return_amount, 0) AS net_revenue_after_returns,  -- Calculate net revenue after returns
  (s.net_sales - COALESCE(r.return_amount, 0)) - (s.quantity * p.standard_cost) AS adjusted_gross_profit -- Calculate gross profit after returns
FROM NAVA_clean.fact_sales s
LEFT JOIN NAVA_clean.dim_products p
  ON s.product_id = p.product_id
LEFT JOIN NAVA_clean.fact_returns r
  ON s.order_line_id = r.order_line_id
LEFT JOIN NAVA_clean.dim_location l
  ON s.postal_code = l.postal_code;

-- ====================================================================
-- 02 Budget Performance view
-- ====================================================================

WITH actuals AS ( -- Combine revenue and expense actuals into a single monthly dataset
SELECT
  DATE_FORMAT(order_date, '%Y-%m-01') AS budget_month,
  country,
  'revenue' AS budget_type,
  NULL AS cost_category,
  SUM(net_sales) AS actual_amount
FROM NAVA_analytics.v_sales_net
WHERE order_date >= '2025-01-01' -- Include actual revenue from FY2025 onwards
GROUP BY
DATE_FORMAT(order_date, '%Y-%m-01'),
country

UNION ALL

SELECT
  DATE_FORMAT(invoice_date, '%Y-%m-01') AS budget_month,
  country,
  department AS budget_type,
  cost_category,
  SUM(amount_actual) AS actual_amount
FROM NAVA_clean.fact_expenses
GROUP BY 
DATE_FORMAT(invoice_date, '%Y-%m-01'),
country,
department,
cost_category
)

SELECT
  b.budget_month,
  b.country,
  b.budget_type,
  a.cost_category,
  b.budget_amount,
  COALESCE(a.actual_amount, 0) AS actual_amount, -- Replace missing actuals with zero
  COALESCE(a.actual_amount, 0) - b.budget_amount AS variance_amount -- Calculate budget variance
FROM NAVA_clean.fact_budget b
LEFT JOIN actuals a
  ON CAST(b.budget_month AS DATE) = a.budget_month
  AND b.country = a.country
  AND b.budget_type = a.budget_type; -- Match budget and actual values by month, country and budget type


-- ====================================================================
-- 03 Marketing Performance tables
-- ====================================================================

CREATE OR REPLACE VIEW NAVA_analytics.v_marketing_conversion AS

WITH sales_by_order AS ( -- Aggregate sales at order level before joining with conversions
SELECT
  order_id,
  SUM(net_sales) AS net_sales
FROM NAVA_clean.fact_sales
GROUP BY order_id
),

conversion_metrics AS ( -- Calculate conversion and revenue metrics by campaign
SELECT
  mc.order_date AS date,
  mc.country,
  mc.channel,
  mc.campaign_id,
  mc.campaign_name,
  COUNT(DISTINCT mc.order_id) AS orders,
  COUNT(DISTINCT mc.customer_id) AS customers,
  SUM(mc.attributed_revenue) AS attributed_revenue,
  SUM(s.net_sales) AS net_sales
FROM NAVA_clean.fact_marketing_conversion mc
LEFT JOIN sales_by_order s
  ON mc.order_id = s.order_id
GROUP BY
mc.order_date,
mc.country,
mc.channel,
mc.campaign_id,
mc.campaign_name
),

marketing_metrics AS ( -- Aggregate marketing spend and traffic metrics by campaign
SELECT
  date,
  country,
  channel,
  campaign_id,
  campaign_name,
  SUM(spend) AS spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks
FROM NAVA_clean.fact_marketing
GROUP BY
date,
country,
channel,
campaign_id,
campaign_name
),

base AS ( -- Create a complete campaign base including spend-only and conversion-only records
SELECT
  date,
  country,
  channel,
  campaign_id,
  campaign_name
FROM marketing_metrics

UNION

SELECT
  date,
  country,
  channel,
  campaign_id,
  campaign_name
FROM conversion_metrics
)

SELECT
  b.date,
  b.country,
  b.channel,
  b.campaign_id,
  b.campaign_name,
  COALESCE(m.spend, 0) AS spend,
  COALESCE(m.impressions, 0) AS impressions,
  COALESCE(m.clicks, 0) AS clicks,
  COALESCE(c.orders, 0) AS orders,
  COALESCE(c.customers, 0) AS customers,
  COALESCE(c.attributed_revenue, 0) AS attributed_revenue,
  COALESCE(c.net_sales, 0) AS net_sales,
  ROUND(COALESCE(m.clicks, 0) / NULLIF(m.impressions, 0), 2) AS ctr, -- Calculate click-through rate
  ROUND(COALESCE(m.spend, 0) / NULLIF(m.clicks, 0), 2) AS cpc, -- Calculate cost per click
  ROUND(COALESCE(c.attributed_revenue, 0) / NULLIF(m.spend, 0), 2) AS roas, -- Calculate return on ad spend
  ROUND(COALESCE(m.spend, 0) / NULLIF(c.orders, 0), 2) AS cost_per_order, -- Calculate acquisition cost per order
  ROUND(COALESCE(c.attributed_revenue, 0) / NULLIF(c.orders, 0), 2) AS revenue_per_order -- Calculate attributed revenue per order
FROM base b
LEFT JOIN marketing_metrics m
  ON b.date = m.date
  AND b.country = m.country
  AND b.channel = m.channel
  AND b.campaign_id = m.campaign_id
  AND b.campaign_name = m.campaign_name
LEFT JOIN conversion_metrics c
  ON b.date = c.date
  AND b.country = c.country
  AND b.channel = c.channel
  AND b.campaign_id = c.campaign_id
  AND b.campaign_name = c.campaign_name;

