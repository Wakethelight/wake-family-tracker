from flask import Flask, request, redirect, url_for, render_template
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import os

from models import Base, UserStatus

app = Flask(__name__)

# Build connection string from environment variables
db_url = os.getenv("DB_CONNECTION_STRING", "postgresql://postgres:password@localhost/statusdb")

engine = create_engine(db_url)
SessionLocal = sessionmaker(bind=engine)

# ✅ Ensure tables exist at startup
Base.metadata.create_all(engine)

from seed import seed_data
seed_data()  # Seed demo data if needed

@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        user_id = request.form["user_id"]
        status = request.form["status"]

        session = SessionLocal()
        new_status = UserStatus(user_id=user_id, status=status)
        session.add(new_status)
        session.commit()
        session.close()

        return redirect(url_for("dashboard"))

    return render_template("index.html")

@app.route("/dashboard")
def dashboard():
    session = SessionLocal()
    statuses = session.query(UserStatus).order_by(UserStatus.updated_at.desc()).all()
    session.close()
    return render_template("dashboard.html", statuses=statuses)
