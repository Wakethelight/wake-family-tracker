from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import os

from models import Base, UserStatus

# Build connection string from environment variables
db_url = os.getenv("DB_CONNECTION_STRING", "postgresql://postgres:password@localhost/statusdb")

engine = create_engine(db_url)
SessionLocal = sessionmaker(bind=engine)

# Ensure schema exists
Base.metadata.create_all(engine)

def seed_data():
    session = SessionLocal()

    # Check if table already has data
    if session.query(UserStatus).count() == 0:
        demo_users = [
            UserStatus(user_id="alice", status="remote"),
            UserStatus(user_id="bob", status="office"),
            UserStatus(user_id="carol", status="home"),
        ]
        session.add_all(demo_users)
        session.commit()
        print("Seeded demo users.")
    else:
        print("Users already exist, skipping seed.")

    session.close()

if __name__ == "__main__":
    seed_data()
