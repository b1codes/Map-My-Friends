# Use Python 3.14 slim image
FROM python:3.14-slim

# 1. Install System Dependencies
# - gdal-bin, libgdal-dev: REQUIRED for GeoDjango/PostGIS
# - libpq-dev: Required for building database drivers
# - build-essential, python3-dev: REQUIRED for Python 3.14 to compile missing wheels
# - gettext: REQUIRED for Django makemessages
RUN apt-get update && apt-get install -y \
    binutils \
    libproj-dev \
    gdal-bin \
    libgdal-dev \
    python3-gdal \
    libpq-dev \
    build-essential \
    python3-dev \
    gettext \
    && rm -rf /var/lib/apt/lists/*

# 2. Set Environment Variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
# Explicitly set C compiler flags for GDAL just in case
ENV CPLUS_INCLUDE_PATH=/usr/include/gdal
ENV C_INCLUDE_PATH=/usr/include/gdal

# 3. Work Directory
WORKDIR /app

# 4. Install Poetry 2.0+
# We need version 2.0+ to read the new [project] section in pyproject.toml
RUN pip install "poetry>=2.0.0"

# 5. Install Python Dependencies
# Copy only the dependency files first to leverage Docker caching
COPY pyproject.toml poetry.lock /app/

# Configure poetry to not create a virtualenv (since we are already in a container)
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi

# 6. Copy the rest of the backend code
COPY . /app/

# 7. Default Command
# We bind to 0.0.0.0 so the host (your machine) can access the container
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
