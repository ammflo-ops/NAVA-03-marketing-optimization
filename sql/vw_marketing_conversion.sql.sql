/*
======================================================================
SCRIPT - Create Analytics Views 
======================================================================
Project     : NAVA Marketing Optimization
Script      : vw_marketing_conversion

Description :

Creates the business-ready view used by the Marketing Optimization dashboard.

This view is part of the shared SQL architecture of the 
NAVA Business Intelligence Portfolio.

WARNING:

Existing analytics views will be dropped and recreated.
======================================================================
*/

CREATE OR REPLACE VIEW NAVA_analytics.vw_marketing_conversion AS

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

