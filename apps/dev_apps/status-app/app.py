# app.py — FINAL PRODUCTION VERSION (Nov 2025)
from flask import Flask, request, redirect, url_for, render_template
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, scoped_session
from sqlalchemy.exc import OperationalError
import os
from datetime import datetime

# Import models AFTER engine is ready (prevents import-time crashes)
from models import Base, UserStatus

app = Flask(__name__)

# === DATABASE CONNECTION ===
db_url = os.getenv("DB_CONNECTION_STRING")

if not db_url:
    # This should NEVER happen in Azure — fail fast and loud
    app.logger.critical("DB_CONNECTION_STRING is missing! Check Key Vault reference.")
    raise RuntimeError("Database connection string not configured")

app.logger.info("DB connection string loaded from Key Vault")
masked = db_url.split("@")[0].rsplit(":", 1)[0] + ":***@" + db_url.split("@")[1] if "@" in db_url else "****"
app.logger.info(f"Connecting to DB at: {masked}")

# Create engine with resilience
engine = create_engine(
    db_url,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    connect_args={"connect_timeout": 10},
    echo=False  # Set True temporarily if debugging SQL
)

# Use scoped_session for thread safety
SessionLocal = scoped_session(sessionmaker(bind=engine))

# === Helper: time ago ===
def time_ago(dt: datetime) -> str:
    if not dt:
        return "never"
    now = datetime.utcnow()
    diff = now - dt
    seconds = int(diff.total_seconds())

    if seconds < 60:
        return f"{seconds}s ago"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m ago"
    hours = minutes // 60
    if hours < 24:
        return f"{hours}h ago"
    days = hours // 24
    return f"{days}d ago"

app.jinja_env.filters['timeago'] = time_ago

# === Routes ===
@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        user_id = request.form.get("user_id")
        status = request.form.get("status")
        team = request.form.get("team")

        if not user_id or not status:
            return "Missing user_id or status", 400

        session = SessionLocal()
        try:
            # Check if this user already exists
            existing = session.query(UserStatus).filter_by(user_id=user_id).first()
            if existing:
                existing.status = status
                existing.updated_at = datetime.utcnow()
                existing.team = team
            else:
                new_status = UserStatus(
                    user_id=user_id,
                    status=status,
                    team=team,
                    updated_at=datetime.utcnow()
                )
                session.add(new_status)

            session.commit()
        finally:
            session.close()

        return redirect(url_for("dashboard"))

    return render_template("index.html")

@app.route("/dashboard")
def dashboard():
    session = SessionLocal()
    try:
        # Get latest status per user (PostgreSQL DISTINCT ON)
        statuses = session.query(UserStatus).from_statement(
            text("""
                SELECT DISTINCT ON (user_id) *
                FROM user_status
                ORDER BY user_id, updated_at DESC
            """)
        ).all()

        # Summary counts
        summary = {
            "remote": session.query(UserStatus.user_id).filter(UserStatus.status == "remote").distinct().count(),
            "home": session.query(UserStatus.user_id).filter(UserStatus.status == "home").distinct().count(),
            "office": session.query(UserStatus.user_id).filter(UserStatus.status == "office").distinct().count(),
        }

        last_updated = None
        if statuses:
            last_updated = f"{statuses[0].updated_at.strftime('%b %d, %Y %I:%M %p')} ({time_ago(statuses[0].updated_at)})"
        team = request.args.get("team")
        if team:
            statuses = [s for s in statuses if s.team == team]
        return render_template("dashboard.html", statuses=statuses, last_updated=last_updated, summary=summary, team=team)

    except OperationalError as e:
        app.logger.error(f"Database unreachable: {e}")
        return "Database is starting up... please wait 60 seconds and refresh.", 503
    except Exception as e:
        app.logger.exception("Unexpected error in dashboard")
        return f"Error: {e}", 500
    finally:
        session.close()

# === Health check ===
@app.route("/health")
def health():
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return "OK", 200
    except Exception as e:
        app.logger.error(f"Health check failed: {e}")
        return f"DB Error: {e}", 503

# === Graceful shutdown ===
@app.teardown_appcontext
def cleanup(resp_or_exc):
    SessionLocal.remove()

# === Run locally only ===
if __name__ == "__main__":
    # Only for local dev
    app.run(debug=True, host="0.0.0.0", port=int(os.getenv("PORT", 8000)))