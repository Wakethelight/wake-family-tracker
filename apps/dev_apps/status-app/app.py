from flask import Flask, request, redirect, url_for, render_template
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import os
from datetime import datetime

from models import Base, UserStatus

app = Flask(__name__)

# === DATABASE CONNECTION (Azure + Local Dev) ===
db_url = os.getenv("DB_CONNECTION_STRING")

# Only fall back for local development
if not db_url:
    print("DB_CONNECTION_STRING not found → using local dev fallback")
    db_url = "postgresql://postgres:password@localhost:5432/statusdb"

# Optional: confirm we're in Azure
if os.getenv("WEBSITE_SITE_NAME"):
    print(f"Azure App Service detected: {os.getenv('WEBSITE_SITE_NAME')}")
    print("DB connection string loaded securely from Key Vault")

engine = create_engine(db_url, pool_pre_ping=True)  # pool_pre_ping helps with ACI restarts
SessionLocal = sessionmaker(bind=engine)

# Ensure tables exist
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

# Routes (unchanged, but tweak query for latest per user if desired)
@app.route("/dashboard")
def dashboard():
    session = SessionLocal()
    # For latest per user: Use subquery or DISTINCT ON (Postgres-specific)
    statuses = session.query(UserStatus).distinct(UserStatus.user_id).order_by(UserStatus.user_id, UserStatus.updated_at.desc()).all()  # Add this for unique latest

    # Summary: Tweak to count unique
    summary = {
        "remote": session.query(UserStatus).distinct(UserStatus.user_id).filter(UserStatus.status=="remote").count(),
        "home": session.query(UserStatus).distinct(UserStatus.user_id).filter(UserStatus.status=="home").count(),
        "office": session.query(UserStatus).distinct(UserStatus.user_id).filter(UserStatus.status=="office").count()
    }
    
    #show last updated
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

# Add for local dev
if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.getenv("PORT", 8000)))