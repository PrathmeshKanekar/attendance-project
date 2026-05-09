import psycopg2

db_url = "postgres://avnadmin:AVNS_zdHgsqT11ArkhNcxWVX@pg-a61f93-atharv-d048.g.aivencloud.com:20672/defaultdb?sslmode=require"
try:
    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("DROP SCHEMA IF EXISTS public CASCADE;")
    cur.execute("CREATE SCHEMA public;")
    cur.close()
    conn.close()
    print("Public schema recreated successfully.")
except Exception as e:
    print(f"Error recreating public schema: {e}")
