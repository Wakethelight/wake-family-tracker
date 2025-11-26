# init_db.py — now only seeds data, assumes Alembic has created schema
import os
import sys
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from models import UserStatus

db_url = os.getenv("DB_CONNECTION_STRING")
if not db_url:
    print("DB_CONNECTION_STRING missing — skipping seeding")
    sys.exit(0)

engine = create_engine(db_url, pool_pre_ping=True)

seed_data = [
    {"user_id": "alice", "status": "remote", "team": "team1"},
    {"user_id": "bob", "status": "office", "team": "team2"},
    {"user_id": "carol", "status": "leave", "team": "team1"},
]

with Session(engine) as session:
    for row in seed_data:
        exists = session.query(UserStatus).filter_by(
            user_id=row["user_id"], team=row["team"]
        ).first()
        if not exists:
            session.add(UserStatus(**row))
    session.commit()

print("Seed data applied successfully")
