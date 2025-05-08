#!/bin/bash
apt-get update
apt-get install -y msodbcsql18
gunicorn --bind=0.0.0.0:$PORT app:app