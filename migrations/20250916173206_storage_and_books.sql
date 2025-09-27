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
VALUES ('books_pdf', 'books_pdf', TRUE)
ON CONFLICT (id) DO NOTHING;

-- POLICIES
CREATE POLICY "Authenticated users can upload files"
ON storage.objects FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'files' AND OWNER = auth.uid()
);

CREATE POLICY "Users can view their own files"
ON storage.objects FOR SELECT TO authenticated USING (
  bucket_id = 'files' AND OWNER = auth.uid()
);

CREATE POLICY "Users can update their own files"
ON storage.objects FOR UPDATE TO authenticated WITH CHECK (
  bucket_id = 'files' AND OWNER = auth.uid()
);

CREATE POLICY "Users can delete their own files"
ON storage.objects FOR DELETE TO authenticated USING (
  bucket_id = 'files' AND OWNER = auth.uid()
);

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

ALTER TABLE public.books DROP COLUMN class_level;

ALTER TABLE public.books ADD COLUMN class_level class_level NOT NULL;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS storage_object_id uuid
    REFERENCES storage.objects(id) ON DELETE CASCADE;

-- ENABLE RLS
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;

-- POLICIES
CREATE POLICY "Users can insert books"
ON books FOR INSERT TO authenticated WITH CHECK (
  auth.uid() = uploaded_by
);

CREATE POLICY "Users can query their own books"
ON books FOR SELECT TO authenticated USING (
  auth.uid() = uploaded_by
);

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
-- 6) BOOK_LESSONS TABLE
-- ======================================

CREATE TABLE IF NOT EXISTS public.book_lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid REFERENCES public.books(id) ON DELETE CASCADE,
  lesson_index int, 
  title text, 
  start_page int, 
  end_page int,
  created_at timestamptz DEFAULT now()
);

-- ENABLE RLS
ALTER TABLE public.book_lessons ENABLE ROW LEVEL SECURITY;

-- POLICIES
CREATE POLICY "Users can insert book lessons"
ON book_lessons FOR INSERT TO authenticated WITH CHECK (
  book_id IN (
    SELECT id
    FROM books
    WHERE uploaded_by = auth.uid()
  )
);

CREATE POLICY "Users can update their own book lessons"
ON book_lessons FOR UPDATE TO authenticated USING (
  book_id IN (
    SELECT id
    FROM books
    WHERE uploaded_by = auth.uid()
  )
) WITH CHECK (
  book_id IN (
    SELECT id
    FROM books
    WHERE uploaded_by = auth.uid()
  )
);

CREATE POLICY "Users can query their own book lessons"
ON book_lessons FOR SELECT TO authenticated USING (
  book_id IN (
    SELECT id
    FROM books
    WHERE uploaded_by = auth.uid()
  )
);

-- ======================================
-- 6) BOOK_CHUNKS TABLE
-- ======================================

CREATE TABLE IF NOT EXISTS public.book_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid REFERENCES public.books(id) ON DELETE CASCADE,
  lesson_id uuid REFERENCES public.book_lessons(id) ON DELETE CASCADE,
  content text NOT NULL,
  embedding vector(384),
  page_number int,
  chunk_index int,
  created_at timestamptz DEFAULT now()
);

-- INDEXES
CREATE INDEX idx_book_chunks_book_id ON public.book_chunks(book_id);
CREATE INDEX idx_book_chunks_lesson_id ON public.book_chunks(lesson_id);
CREATE INDEX idx_book_chunks_embedding ON public.book_chunks USING hnsw (embedding vector_ip_ops);

-- ENABLE RLS
ALTER TABLE public.book_chunks ENABLE ROW LEVEL SECURITY;

-- POLICIES
CREATE POLICY "Users can insert book chunks"
ON book_chunks FOR INSERT TO authenticated WITH CHECK (
  book_id IN (
    SELECT id
    FROM books
    WHERE uploaded_by = auth.uid()
  )
);

CREATE POLICY "Users can update their own book chunks"
ON book_chunks FOR UPDATE TO authenticated USING (
  book_id IN (
    SELECT id
    FROM books
    WHERE uploaded_by = auth.uid()
  )
) WITH CHECK (
  book_id IN (
    SELECT id
    FROM books
    WHERE uploaded_by = auth.uid()
  )
);

CREATE POLICY "Users can query their own book chunks"
ON book_chunks FOR SELECT TO authenticated USING (
  book_id IN (
    SELECT id
    FROM books
    WHERE uploaded_by = auth.uid()
  )
);

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
  INSERT INTO public.books (name, storage_object_id, uploaded_by)
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
