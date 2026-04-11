FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# System deps:
# - build-essential/g++/make: compile cmdstan
# - git/curl: cmdstanpy downloads cmdstan source
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN python -c "from cmdstanpy import install_cmdstan; install_cmdstan(cores=2, progress=True)"

ENV CMDSTAN=/root/.cmdstan

COPY app ./app

# Download NLTK assets (vader lexicon)
RUN python -c "import nltk; nltk.download('vader_lexicon')"

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]