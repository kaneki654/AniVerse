#!/bin/bash
export PYTHONPATH=/home/kerby0818/app/AniVerse/libs
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
