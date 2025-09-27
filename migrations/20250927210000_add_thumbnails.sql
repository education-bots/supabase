-- ======================================
-- ADD THUMBNAIL SUPPORT FOR BOOKS
-- ======================================

-- Create thumbnails storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('book_thumbnails', 'book_thumbnails', TRUE)
ON CONFLICT (id) DO NOTHING;

-- Add thumbnail_url field to books table
ALTER TABLE public.books 
ADD COLUMN IF NOT EXISTS thumbnail_url text;

-- Create index for thumbnail_url
CREATE INDEX IF NOT EXISTS idx_books_thumbnail_url ON public.books (thumbnail_url);

-- ======================================
-- STORAGE POLICIES FOR THUMBNAILS BUCKET
-- ======================================

-- Policy: Authenticated users can view thumbnails
CREATE POLICY "book_thumbnails_select_authenticated" ON storage.objects
  FOR SELECT TO authenticated USING (
    bucket_id = 'book_thumbnails'
  );

-- Policy: Service role can upload thumbnails
CREATE POLICY "book_thumbnails_upload_service_role" ON storage.objects
  FOR INSERT TO service_role WITH CHECK (
    bucket_id = 'book_thumbnails'
  );

-- Policy: Service role can update thumbnails
CREATE POLICY "book_thumbnails_update_service_role" ON storage.objects
  FOR UPDATE TO service_role USING (
    bucket_id = 'book_thumbnails'
  ) WITH CHECK (
    bucket_id = 'book_thumbnails'
  );

-- Policy: Service role can delete thumbnails
CREATE POLICY "book_thumbnails_delete_service_role" ON storage.objects
  FOR DELETE TO service_role USING (
    bucket_id = 'book_thumbnails'
  );

-- ======================================
-- UPDATE STORAGE TRIGGER TO CALL THUMBNAIL FUNCTION
-- ======================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS on_file_upload ON storage.objects;

-- Create updated trigger function that calls both process and thumbnail functions
CREATE OR REPLACE FUNCTION private.handle_storage_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  book_id uuid;
  subject text;
  filename text;
  file_path text;
  class_level text;
  storage_url text;
  process_result int;
  thumbnail_result int;
BEGIN

  -- 
  file_path := ltrim(new.name, '/');
  class_level := split_part(file_path, '/', 1);       -- "class-3"
  filename := split_part(file_path, '/', 2);  -- "english.pdf"
  subject := split_part(filename, '.', 1);      -- "english"
  storage_url := supabase_url() || '/storage/v1/object/public/books_pdf' || '/' || file_path;

  -- Insert book record
  INSERT INTO public.books (class_level, subject, title, supabase_path, pdf_url, storage_object_id, uploaded_by)
    VALUES (
      class_level::class_level, 
      subject, 
      new.path_tokens[2], 
      new.name,
      storage_url,
      new.id, 
      new.owner
    )
    RETURNING id INTO book_id;

  -- Call the process function for PDF processing
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
  INTO process_result;

  -- Call the optimized thumbnail function for thumbnail generation
  SELECT
    net.http_post(
      url := supabase_url() || '/functions/v1/thumbnail-optimized',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', current_setting('request.headers')::json->>'authorization'
      ),
      body := jsonb_build_object(
        'book_id', book_id,
        'pdf_url', supabase_url() || '/storage/v1/object/public/book_thumbnails' || '/thumbnail_' || book_id || '.jpg'
      )
    )
  INTO thumbnail_result;

  RETURN NULL;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER on_file_upload
  AFTER INSERT ON storage.objects
  FOR EACH ROW
  WHEN (new.bucket_id = 'books_pdf')
  EXECUTE PROCEDURE private.handle_storage_update();

--------------------------------------------------------------------------------
-- END OF THUMBNAIL MIGRATION
--------------------------------------------------------------------------------
