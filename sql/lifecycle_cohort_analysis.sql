-- ============================================================================
-- E-COMMERCE CUSTOMER LIFECYCLE & COHORT RETENTION ANALYSIS (SQL)
-- Covers: Acquisition Funnel, 2nd-Order Conversion, Cohort Retention & CLV
-- Compatible with PostgreSQL / MySQL 8.0+ / BigQuery
-- ============================================================================

-- 1. Create Base Tables
CREATE TABLE IF NOT EXISTS ecommerce_customers (
    customer_id VARCHAR(20) PRIMARY KEY,
    acquisition_date DATE NOT NULL,
    acquisition_cohort VARCHAR(10) NOT NULL,
    city VARCHAR(50),
    acquisition_channel VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS ecommerce_orders (
    order_id VARCHAR(20) PRIMARY KEY,
    customer_id VARCHAR(20) NOT NULL,
    order_date DATE NOT NULL,
    order_month VARCHAR(10) NOT NULL,
    order_sequence INT,
    category VARCHAR(50),
    order_value_inr DECIMAL(12, 2),
    discount_pct INT
);

-- 2. Customer Lifecycle Stage Classification & CLV Summary
WITH snapshot AS (
    SELECT DATE '2026-10-31' AS analysis_date
),
customer_activity AS (
    SELECT
        c.customer_id,
        c.acquisition_date,
        c.acquisition_cohort,
        c.city,
        c.acquisition_channel,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(SUM(o.order_value_inr), 2) AS total_clv_inr,
        ROUND(AVG(o.order_value_inr), 2) AS avg_order_value_inr,
        DATEDIFF(s.analysis_date, MAX(o.order_date)) AS days_since_last_order,
        DATEDIFF(s.analysis_date, c.acquisition_date) AS tenure_days
    FROM ecommerce_customers c
    LEFT JOIN ecommerce_orders o ON c.customer_id = o.customer_id
    CROSS JOIN snapshot s
    GROUP BY c.customer_id, c.acquisition_date, c.acquisition_cohort, c.city, c.acquisition_channel, s.analysis_date
),
lifecycle_tagged AS (
    SELECT
        *,
        CASE
            WHEN total_orders = 1 AND tenure_days <= 45 THEN '1. New / Onboarding (0-45d)'
            WHEN total_orders >= 8 AND days_since_last_order <= 60 THEN '3. VIP Champions'
            WHEN total_orders >= 2 AND days_since_last_order <= 75 THEN '2. Active Repeat / Loyal'
            WHEN total_orders >= 2 AND days_since_last_order BETWEEN 76 AND 135 THEN '4. At-Risk (Lapsing)'
            WHEN total_orders = 1 AND tenure_days > 45 THEN '5. One-Time Churned'
            ELSE '6. Churned Repeaters'
        END AS lifecycle_stage
    FROM customer_activity
)
SELECT
    lifecycle_stage,
    COUNT(customer_id) AS customer_count,
    ROUND(COUNT(customer_id) * 100.0 / SUM(COUNT(customer_id)) OVER (), 1) AS customer_share_pct,
    ROUND(AVG(total_orders), 1) AS avg_orders,
    ROUND(AVG(total_clv_inr), 2) AS avg_clv_inr,
    ROUND(SUM(total_clv_inr), 2) AS total_revenue_inr,
    ROUND(SUM(total_clv_inr) * 100.0 / SUM(SUM(total_clv_inr)) OVER (), 1) AS revenue_share_pct
FROM lifecycle_tagged
GROUP BY lifecycle_stage
ORDER BY lifecycle_stage;

-- 3. Time-to-Second-Order Conversion Velocity (Activation Metric)
WITH ranked_orders AS (
    SELECT
        customer_id,
        order_date,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS order_num,
        LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS prev_order_date
    FROM ecommerce_orders
)
SELECT
    COUNT(CASE WHEN order_num = 1 THEN 1 END) AS total_acquired_customers,
    COUNT(CASE WHEN order_num = 2 THEN 1 END) AS converted_to_2nd_order,
    ROUND(COUNT(CASE WHEN order_num = 2 THEN 1 END) * 100.0 /
          NULLIF(COUNT(CASE WHEN order_num = 1 THEN 1 END), 0), 2) AS repeat_conversion_rate_pct,
    ROUND(AVG(CASE WHEN order_num = 2 THEN DATEDIFF(order_date, prev_order_date) END), 1) AS avg_days_to_2nd_order
FROM ranked_orders;

-- 4. Acquisition Channel Quality (CLV & Repeat Rate by Channel)
SELECT
    c.acquisition_channel,
    COUNT(DISTINCT c.customer_id) AS acquired_customers,
    ROUND(SUM(o.order_value_inr) / COUNT(DISTINCT c.customer_id), 2) AS avg_clv_per_customer_inr,
    ROUND(COUNT(DISTINCT o.order_id) * 1.0 / COUNT(DISTINCT c.customer_id), 2) AS avg_orders_per_customer
FROM ecommerce_customers c
LEFT JOIN ecommerce_orders o ON c.customer_id = o.customer_id
GROUP BY c.acquisition_channel
ORDER BY avg_clv_per_customer_inr DESC;
