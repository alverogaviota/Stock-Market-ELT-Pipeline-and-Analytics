ARG AIRFLOW_VERSION=3.3.2

FROM apache/airflow:3.3.2

COPY requirements.txt .
RUN pip install --no-cache-dir "apache-airflow==${AIRFLOW_VERSION}" -r requirements.txt