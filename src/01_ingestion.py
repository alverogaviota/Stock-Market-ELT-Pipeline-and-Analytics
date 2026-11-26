import os, logging, requests, psycopg

from pathlib import Path
from dotenv import load_dotenv
from psycopg.types.json import Jsonb

load_dotenv()

log_dir = Path(__file__).parent.parent / "logs"
log_dir.mkdir(parents=True, exist_ok=True)

# Logger info config
logging.basicConfig(
    level=logging.INFO,  
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler(log_dir / "pipeline.log"),  
        logging.StreamHandler(),  # Stream log into console
    ],
)

logger = logging.getLogger("Data Ingestion")

# API & Databases Variable from env
DATABASE_URL = os.getenv("DATABASE_URL")
SYMBOL = "JPM"
API_KEY = os.getenv("API_KEY")

def extract(api_url):
    try:
        params={
            "function": "TIME_SERIES_DAILY",
            "symbol": SYMBOL,
            "apikey": API_KEY
        }

        logger.info(f"Requesting data from: {api_url}.")
        response = requests.get(api_url, params=params, timeout=30)
        response.raise_for_status()

        json_data = response.json()

        with psycopg.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    CREATE SCHEMA IF NOT EXISTS bronze;

                    CREATE TABLE IF NOT EXISTS bronze.stocks_daily (
                        id SERIAL PRIMARY KEY,
                        symbol TEXT NOT NULL,
                        last_refreshed DATE NOT NULL,
                        ingested_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
                        raw_data JSONB NOT NULL,
                        UNIQUE (symbol, last_refreshed)
                    );
                """)

                logger.info(f"Staging raw data into database...")

                # UPSERT Data on last refreshed conflict to ensure idempotent ingestion
                query = """
                    INSERT INTO bronze.stocks_daily (symbol, last_refreshed, raw_data)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (symbol, last_refreshed)
                    DO UPDATE SET
                        raw_data = EXCLUDED.raw_data,
                        ingested_at = CURRENT_TIMESTAMP
                """

                last_refreshed = json_data['Meta Data']['3. Last Refreshed']
                cur.execute(query, (SYMBOL, last_refreshed, Jsonb(json_data)))

                logger.info(f"Successfully Staged Data into Database.")
    except requests.exceptions.RequestException as e:
        logger.error(f"API request failed: {e}")

    except Exception as e:
        logger.error(f" Ingestion Error {e}")

if __name__ == "__main__":
    try:
        extract("https://www.alphavantage.co/query")
    except Exception as e:
        logger.error(f"Ingestion Error {e}")