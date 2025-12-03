FROM python:3.11-slim


# set workdir
WORKDIR /app


# install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
build-essential \
gcc \
libpq-dev \
&& rm -rf /var/lib/apt/lists/*


# copy
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt


COPY main.py ./


ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1


EXPOSE 8080


CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers"]