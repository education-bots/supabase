import os
from supabase_pydantic.utils import generate_models

# Replace with your Supabase URL and service role key
SUPABASE_URL = os.getenv("SUPABASE_PROJECT_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_API_KEY")


# Generate models from your public schema
# You can specify other schemas if needed
models_code = generate_models(
    url=SUPABASE_URL,
    key=SUPABASE_KEY,
    schema="public"
)

# The 'models_code' variable now contains a string with the generated Python code
# You can then save this to a file (e.g., models.py) and import it into your application.
with open("models.py", "w") as f:
    f.write(models_code)
