-- =============================================
-- RENAME BUCKET: "books" → "books_pdf"
-- =============================================

UPDATE storage.buckets
SET id = 'books_pdf'
WHERE id = 'books';

-- =============================================
-- UPDATE TRIGGER
-- =============================================

CREATE OR REPLACE TRIGGER on_file_upload
  AFTER INSERT ON storage.objects
  FOR EACH ROW
  WHEN (new.bucket_id = 'books_pdf')
  EXECUTE PROCEDURE private.handle_storage_update();

-- =============================================
-- UPDATE TRIGGER FUNCTION
-- =============================================

CREATE OR REPLACE FUNCTION private.handle_storage_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  book_id uuid;
  result int;
  class_level text;
  filename text;
  file_path text;
  subject text;
  storage_url text;
BEGIN
  RAISE NOTICE '%', new;
  RAISE NOTICE 'New book added: %', new.id;

  -- remove leading slash just in case
  file_path := ltrim(new.name, '/');
  class_level := split_part(file_path, '/', 1);       -- "class-3"
  filename := split_part(file_path, '/', 2);  -- "english.pdf"
  subject := split_part(filename, '.', 1);      -- "english"
  storage_url := supabase_url() || '/storage/v1/object/public/books_pdf' || '/' || file_path;

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

