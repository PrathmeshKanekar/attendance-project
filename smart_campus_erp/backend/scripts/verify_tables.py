import psycopg2

db_url = "postgres://avnadmin:AVNS_zdHgsqT11ArkhNcxWVX@pg-a61f93-atharv-d048.g.aivencloud.com:20672/defaultdb?sslmode=require"
try:
    conn = psycopg2.connect(db_url)
    cur = conn.cursor()
    cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;")
    tables = cur.fetchall()
    print("All tables found in DB:")
    for t in tables:
        print(f" - {t[0]}")
    cur.close()
    conn.close()
except Exception as e:
    print(f"Error querying tables: {e}")
