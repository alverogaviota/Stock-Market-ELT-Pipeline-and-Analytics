--  Transform data to keep data Integrity, Validity, and quality
BEGIN;

CREATE SCHEMA IF NOT EXISTS silver;

DROP TABLE IF EXISTS silver.stocks_daily;

CREATE TABLE silver.stocks_daily AS
WITH parsed_data AS (
    SELECT
        id, 
        symbol,
        ingested_at,
        CURRENT_TIMESTAMP AS transformed_at,
        ts.key::date AS trade_date,
        (ts.value->>'1. open')::numeric AS open_price,
        (ts.value->>'2. high')::numeric AS high_price,
        (ts.value->>'3. low')::numeric AS low_price,
        (ts.value->>'4. close')::numeric AS close_price,
        (ts.value->>'5. volume')::bigint AS volume
    FROM bronze.stocks_daily b 
    CROSS JOIN LATERAL jsonb_each(b.raw_data->'Time Series (Daily)') AS ts
    WHERE b.ingested_at >= CURRENT_DATE
), 
ranked_data AS (    
    SELECT *, 
        ROW_NUMBER() OVER (
            -- Partition by BOTH symbol and trade_date so different stocks aren't wiped out
            PARTITION BY symbol, trade_date 
            -- Order by when it was ingested (or id DESC) to keep the latest/oldest record
            ORDER BY ingested_at DESC, id DESC
        ) AS row_num
    FROM parsed_data
)
SELECT 
    id, 
    symbol,
    ingested_at,
    transformed_at,
    trade_date,
    open_price,
    high_price,
    low_price,
    close_price,
    volume
FROM ranked_data
WHERE row_num = 1;

-- NOT NULL Constraint to prevent any missing values
ALTER TABLE silver.stocks_daily
    ALTER COLUMN open_price SET NOT NULL,
    ALTER COLUMN high_price SET NOT NULL,
    ALTER COLUMN low_price SET NOT NULL,
    ALTER COLUMN close_price SET NOT NULL,
    ALTER COLUMN volume SET NOT NULL;

-- Key Constraint to enforce uniqueness
ALTER TABLE silver.stocks_daily
    ADD PRIMARY KEY (id, symbol, trade_date); 

-- Check Rule Constraint for enforcing column to fit business requirements
ALTER TABLE silver.stocks_daily
    ADD CHECK (open_price > 0),
    ADD CHECK (high_price > 0),
    ADD CHECK (low_price > 0),
    ADD CHECK (close_price > 0),
    ADD CHECK (volume >= 0),
    ADD CHECK (high_price >= low_price);

COMMIT;