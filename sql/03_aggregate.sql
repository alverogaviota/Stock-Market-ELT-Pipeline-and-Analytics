-- Aggregate data marts according to business metrics
BEGIN;

CREATE SCHEMA IF NOT EXISTS gold;

-- Fact Stock Daily Prices
DROP TABLE IF EXISTS gold.fct_daily_prices;

CREATE TABLE gold.fct_daily_prices AS 
WITH base AS (
    SELECT
        symbol,
        trade_date,
        close_price,
        LAG(close_price) OVER (PARTITION BY symbol ORDER BY trade_date) AS prev_close
    FROM silver.stocks_daily
) 
SELECT
    symbol,
    trade_date,
    close_price,
    COALESCE(prev_close, 0) AS prev_close,
    COALESCE(close_price - prev_close, 0) AS daily_change,
    COALESCE(ROUND((close_price - prev_close) / prev_close * 100, 3), 0) AS daily_change_pct
FROM base;

-- NOT NULL Constraint to prevent any missing values
ALTER TABLE gold.fct_daily_prices
    ALTER COLUMN close_price SET NOT NULL,  
    ALTER COLUMN prev_close SET NOT NULL,    
    ALTER COLUMN daily_change SET NOT NULL,    
    ALTER COLUMN daily_change_pct SET NOT NULL;    

-- Key Constraint to enforce uniqueness
ALTER TABLE gold.fct_daily_prices
    ADD PRIMARY KEY (symbol, trade_date);


-- Stocks Weekly Summary Prices
DROP TABLE IF EXISTS gold.weekly_summary;

CREATE TABLE gold.weekly_summary AS
WITH daily AS (
    SELECT 
        symbol,
        open_price,
        low_price,
        high_price,
        close_price,
        volume,
        DATE_TRUNC('week', trade_date) AS week_start,
        ROW_NUMBER() OVER (PARTITION by DATE_TRUNC('week', trade_date) ORDER BY trade_date) AS rn_first,
        ROW_NUMBER() OVER (PARTITION by DATE_TRUNC('week', trade_date) ORDER BY trade_date DESC) AS rn_last
    FROM silver.stocks_daily
)
SELECT
    symbol,
    week_start,
    MAX(CASE WHEN rn_first = 1 THEN open_price END) AS week_open,
    MAX(high_price) AS week_high,
    MIN(low_price) AS week_low,
    MAX(CASE WHEN rn_last = 1 THEN close_price END) AS week_close,
    SUM(volume) AS week_volume
FROM daily
GROUP by symbol, week_start
ORDER BY week_start;

-- NOT NULL Constraint to prevent any missing values
ALTER TABLE gold.weekly_summary    
    ALTER COLUMN week_open SET NOT NULL,   
    ALTER COLUMN week_close SET NOT NULL,    
    ALTER COLUMN week_high SET NOT NULL, 
    ALTER COLUMN week_low SET NOT NULL,
    ALTER COLUMN week_close SET NOT NULL,
    ALTER COLUMN week_volume SET NOT NULL;

-- Key Constraint to enforce uniqueness
ALTER TABLE gold.weekly_summary
    ADD PRIMARY KEY (symbol, week_start);

-- Check Constraint enforcing column to fit business requirements
ALTER TABLE gold.weekly_summary
    ADD CHECK (week_open > 0),
    ADD CHECK (week_close > 0),
    ADD CHECK (week_high > 0),
    ADD CHECK (week_low > 0),
    ADD CHECK (week_volume > 0),
    ADD CHECK (week_high > week_low);

COMMIT;