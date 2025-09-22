-- ======================================
-- FUNCTION: private.embed
-- ======================================

CREATE OR REPLACE FUNCTION private.embed()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  content_column text = TG_ARGV[0];
  embedding_column text = TG_ARGV[1];
  batch_size int = CASE
    WHEN array_length(TG_ARGV, 1) >= 3 THEN TG_ARGV[2]::int
    ELSE 5
  END;
  timeout_milliseconds int = CASE
    WHEN array_length(TG_ARGV, 1) >= 4 THEN TG_ARGV[3]::int
    ELSE 5 * 60 * 1000 -- 5 minutes default
  END;
  batch_count int = CEILING((SELECT count(*) FROM inserted) / batch_size::float);
BEGIN
  -- LOOP THROUGH EACH BATCH AND CALL EDGE FUNCTION
  FOR i IN 0 .. (batch_count - 1) LOOP
    PERFORM
      net.http_post(
        url := supabase_url() || '/functions/v1/embed',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', current_setting('request.headers')::json->>'authorization'
        ),
        body := jsonb_build_object(
          'ids', (
            SELECT json_agg(ds.id)
            FROM (
              SELECT id
              FROM inserted
              LIMIT batch_size OFFSET i * batch_size
            ) ds
          ),
          'table', TG_TABLE_NAME,
          'contentColumn', content_column,
          'embeddingColumn', embedding_column
        ),
        timeout_milliseconds := timeout_milliseconds
      );
  END LOOP;

  RETURN NULL;
END;
$$;

-- ======================================
-- TRIGGER: EMBED_BOOK_CHUNKS
-- ======================================

DROP TRIGGER IF EXISTS embed_book_chunks ON public.book_chunks;

CREATE TRIGGER embed_book_chunks
  AFTER INSERT ON public.book_chunks
  REFERENCING NEW TABLE AS inserted
  FOR EACH STATEMENT
  EXECUTE PROCEDURE private.embed('content', 'embedding');

--------------------------------------------------------------------------------
-- END OF FILE
--------------------------------------------------------------------------------
