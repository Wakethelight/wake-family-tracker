from flask import Flask, request, redirect, url_for, render_template
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import os
from datetime import datetime

from models import Base, UserStatus

app = Flask(__name__)

# Build connection string from environment variables
db_url = os.getenv("DB_CONNECTION_STRING", "postgresql://postgres:password@localhost/statusdb")

engine = create_engine(db_url)
SessionLocal = sessionmaker(bind=engine)

# ✅ Ensure tables exist at startup
Base.metadata.create_all(engine)

# --- Helper: time ago ---
def time_ago(dt: datetime) -> str:
    now = datetime.utcnow()
    diff = now - dt

    seconds = diff.total_seconds()
    minutes = int(seconds // 60)
    hours = int(seconds // 3600)
    days = int(seconds // 86400)

    if seconds < 60:
        return f"{int(seconds)} seconds ago"
    elif minutes < 60:
        return f"{minutes} minutes ago"
    elif hours < 24:
        return f"{hours} hours ago"
    else:
        return f"{days} days ago"

# Register as Jinja filter
@app.template_filter("timeago")
def timeago_filter(dt):
    return time_ago(dt)

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

    # Count summary
    summary = {
        "remote": session.query(UserStatus).filter_by(status="remote").count(),
        "home": session.query(UserStatus).filter_by(status="home").count(),
        "office": session.query(UserStatus).filter_by(status="office").count()
    }
    
    last_updated = None
    if statuses:
        latest = statuses[0].updated_at
        if isinstance(latest, datetime):
            formatted = latest.strftime("%b %d, %Y %I:%M %p")
            last_updated = f"{formatted} ({time_ago(latest)})"
        else:
            last_updated = str(latest)

    session.close()
    return render_template("dashboard.html", statuses=statuses, last_updated=last_updated)
