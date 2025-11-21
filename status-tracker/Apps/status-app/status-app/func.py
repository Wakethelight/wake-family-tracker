from flask import Flask, request, render_template
import psycopg2

app = Flask(__name__)

def get_db_connection():
    return psycopg2.connect(
        host="your-postgres-host",
        database="your-db",
        user="your-user",
        password="your-password"
    )

@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        user_id = request.form["user_id"]
        status = request.form["status"]
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("INSERT INTO user_status (user_id, status) VALUES (%s, %s)", (user_id, status))
        conn.commit()
        cur.close()
        conn.close()
    return render_template("index.html")
