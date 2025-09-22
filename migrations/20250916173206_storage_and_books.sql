-- 0) SCHEMA
CREATE SCHEMA IF NOT EXISTS private;

-- ======================================
-- 1) EXTENSIONS
-- ======================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- ======================================
-- 2) STORAGE BUCKET: BOOKS
-- ======================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('books', 'books', TRUE)
ON CONFLICT (id) DO NOTHING;

-- ======================================
-- 3) ENUM: CLASS_LEVEL
-- ======================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'class_level') THEN
    CREATE TYPE class_level AS ENUM (
      'class-1', 'class-2', 'class-3', 'class-4',
      'class-5', 'class-6', 'class-7', 'class-8'
    );
  END IF;
END$$;

-- ======================================
-- 4) UPDATE BOOKS TABLE
-- ======================================

ALTER TABLE public.books
  ALTER COLUMN class_level TYPE class_level USING class_level::class_level;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS storage_object_id uuid
    REFERENCES storage.objects(id) ON DELETE CASCADE;

-- ENABLE RLS
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;

-- POLICIES
CREATE POLICY "books_select_policy" ON public.books FOR SELECT USING (TRUE);

CREATE POLICY "books_admin_policy" ON public.books FOR ALL USING (auth.role() = 'admin')
  WITH CHECK (auth.role() = 'admin');

-- ======================================
-- 5) BOOKS_WITH_STORAGE_PATH VIEW
-- ======================================

CREATE VIEW books_with_storage_path
WITH (security_invoker=true)
AS
  SELECT books.*, storage.objects.name AS storage_object_path
  FROM books
  JOIN storage.objects
    ON storage.objects.id = books.storage_object_id;

-- ======================================
-- 6) BOOK_CHUNKS TABLE
-- ======================================

CREATE TABLE IF NOT EXISTS public.book_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid REFERENCES public.books(id) ON DELETE CASCADE,
  content text NOT NULL,
  embedding vector(384),
  page_number int,
  created_at timestamptz DEFAULT now()
);

-- INDEXES
CREATE INDEX idx_book_chunks_book_id ON public.book_chunks(book_id);
CREATE INDEX idx_book_chunks_embedding ON public.book_chunks USING hnsw (embedding vector_ip_ops);

-- ENABLE RLS
ALTER TABLE public.book_chunks ENABLE ROW LEVEL SECURITY;

-- POLICIES
CREATE POLICY "book_chunks_select" ON public.book_chunks FOR SELECT USING (TRUE);
CREATE POLICY "book_chunks_admin" ON public.book_chunks FOR ALL 
  USING (auth.role() = 'admin') WITH CHECK (auth.role() = 'admin');

-- ======================================
-- 6) STORAGE OBJECT POLICIES
-- ======================================

-- AUTHENTICATED USERS CAN READ
CREATE POLICY "Allow authenticated read access" ON storage.objects FOR SELECT
  USING (bucket_id = 'books' AND auth.role() IS NOT NULL);

-- ONLY ADMIN CAN UPLOAD
CREATE POLICY "Allow admin upload" ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'books'
    AND auth.role() = 'admin'
    AND RIGHT(LOWER(storage.filename(name)), 4) = '.pdf'
    AND name ~ '^class-[1-8]/[a-zA-Z0-9_-]+\.pdf$'
  );

-- ONLY ADMIN CAN DELETE
CREATE POLICY "Allow admin delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'books' AND auth.role() = 'admin');

-- ======================================
-- 7) FUNCTIONS
-- ======================================

CREATE OR REPLACE FUNCTION supabase_url()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  secret_value text;
BEGIN
  SELECT decrypted_secret
  INTO secret_value
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_url';

  RETURN secret_value;
END;
$$;

-- TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION private.handle_storage_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  book_id uuid;
  result int;
BEGIN
  INSERT INTO public.books (name, storage_object_id, created_by)
    VALUES (new.path_tokens[2], new.id, new.owner)
    RETURNING id INTO book_id;

  SELECT
    net.http_post(
      url := supabase_url() || '/functions/v1/process',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', current_setting('request.headers')::json->>'authorization'
      ),
      body := jsonb_build_object(
        'book_id', book_id
      )
    )
  INTO result;

  RETURN NULL;
END;
$$;

-- TRIGGER
CREATE TRIGGER on_file_upload
  AFTER INSERT ON storage.objects
  FOR EACH ROW
  WHEN (new.bucket_id = 'books')
  EXECUTE PROCEDURE private.handle_storage_update();

--------------------------------------------------------------------------------
-- END OF FILE
--------------------------------------------------------------------------------
