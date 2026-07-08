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
  SUM(net_sales) AS attributed_revenue_adj
FROM NAVA_clean.sales
GROUP BY
order_id),

marketing_conversion AS ( -- Calculate conversion and revenue metrics by campaign
SELECT
  mc.order_date,
  mc.country,
  mc.channel,
  mc.campaign_id,
  LEFT(mc.campaign_name, LENGTH(mc.campaign_name) - 3) AS campaign_name, -- Remove country suffix (FR, ES, PT) from campaign name
  COUNT(DISTINCT mc.order_id) AS orders,
  SUM(s.attributed_revenue_adj) AS net_sales
FROM NAVA_clean.marketing_conversion mc
LEFT JOIN sales_by_order s
  ON mc.order_id = s.order_id
WHERE mc.order_id NOT LIKE '%ORD-INVALID%' -- Exclude intentionally invalid orders used for data quality demonstrations
GROUP BY
mc.order_date,
mc.country,
mc.channel,
mc.campaign_id,
mc.campaign_name) -- Aggregate conversions at campaign and daily level

SELECT
  mc.order_date,
  mc.country,
  mc.channel,
  mc.campaign_id,
  mc.campaign_name,
  mc.orders,
  mc.net_sales,
  mm.spend,
  mm.impressions,
  mm.clicks,
  -- Marketing performance KPIs
  ROUND(COALESCE(mm.clicks, 0) / NULLIF(mm.impressions, 0), 4) AS ctr, -- Calculate click-through rate
  ROUND(COALESCE(mm.spend, 0) / NULLIF(mm.clicks, 0), 2) AS cpc, -- Calculate cost per click
  ROUND(COALESCE(mc.net_sales, 0) / NULLIF(mm.spend, 0), 2) AS roas, -- Calculate return on ad spend
  ROUND(COALESCE(mm.spend, 0) / NULLIF(mc.orders, 0), 2) AS cpa -- Calculate acquisition cost per order/acquisition
FROM marketing_conversion mc
LEFT JOIN NAVA_clean.marketing mm -- Enrich conversion metrics with campaign spend and traffic data
  ON mc.order_date = mm.date
  AND mc.country = mm.country
  AND mc.channel = mm.channel
  AND mc.campaign_id = mm.campaign_id;

