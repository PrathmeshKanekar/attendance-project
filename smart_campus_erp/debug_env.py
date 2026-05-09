import os
import environ
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent / 'backend'
env = environ.Env()
env_path = os.path.join(BASE_DIR.parent, '.env')
print(f"Reading env from: {env_path}")
environ.Env.read_env(env_path)

db_config = env.db('DATABASE_URL')
print(f"DB Config: {db_config}")
