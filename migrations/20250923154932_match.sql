-- ======================================
-- FUNCTION: match_book_chunks
-- ======================================

CREATE OR REPLACE FUNCTION match_book_chunks(
  embedding vector(384),
  match_threshold float
)
RETURNS setof book_chunks
LANGUAGE plpgsql
AS $$
#variable_conflict use_variable
BEGIN
  RETURN query
  SELECT *
  FROM book_chunks
  WHERE book_chunks.embedding <#> embedding < -match_threshold
	ORDER BY book_chunks.embedding <#> embedding;
END;
$$;
