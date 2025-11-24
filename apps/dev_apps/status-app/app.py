from flask import Flask, request, redirect, url_for, render_template
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import os
from datetime import datetime

from models import Base, UserStatus

app = Flask(__name__)

# Build connection string from environment variables
db_url = os.getenv("DB_CONNECTION_STRING", "postgresql://postgres:password@localhost/statusdb")

# For Azure: Fetch from Key Vault if in prod
if os.getenv("AZURE_ENVIRONMENT"):  # Or check for WEBSITE_SITE_NAME env in App Service
    from azure.identity import DefaultAzureCredential
    from azure.keyvault.secrets import SecretClient
    credential = DefaultAzureCredential()
    kv_client = SecretClient(vault_url=os.getenv("KEY_VAULT_URL"), credential=credential)
    db_url = kv_client.get_secret("db-connection-string").value

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