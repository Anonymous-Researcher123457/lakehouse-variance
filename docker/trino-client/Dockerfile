FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
  && rm -RF /var/lib/apt/lists/*

WORKDIR /src

COPY src/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r ./requirements.txt

COPY src/ /src/
COPY queries/ /queries/

USER root

ENTRYPOINT []
