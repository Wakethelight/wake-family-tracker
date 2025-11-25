# init_db.py — safe, idempotent, retrying table creation
import os
import time
import sys
from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError
from models import Base

db_url = os.getenv("DB_CONNECTION_STRING")
if not db_url:
    print("DB_CONNECTION_STRING missing — skipping table creation")
    sys.exit(0)

print("Waiting for PostgreSQL to accept connections (max 90s)...")
for attempt in range(30):
    try:
        engine = create_engine(db_url, pool_pre_ping=True, connect_args={"connect_timeout": 5})
        with engine.connect() as conn:
            conn.execute("SELECT 1")
        print("Connected! Creating tables if needed...")
        Base.metadata.create_all(engine)
        print("Tables ready")
        sys.exit(0)
    except OperationalError as e:
        print(f"Attempt {attempt + 1}/30: DB not ready yet ({e})")
        time.sleep(3)

print("Timed out waiting for DB — starting app anyway (tables may be created later)")
sys.exit(0)