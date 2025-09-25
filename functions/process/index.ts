import { createClient } from '@supabase/supabase-js';
import { processMarkdown } from '../_lib/markdown-parser.ts';
import { Database } from '../_types/database.types.ts'
import { pdfToMarkdown } from '../_lib/pdf-to-markdown.ts';

// These are automatically injected
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');

Deno.serve(async (req) => {
  if (!supabaseUrl || !supabaseAnonKey) {
    return new Response(
      JSON.stringify({
        error: 'Missing environment variables.',
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
  const authorization = req.headers.get('Authorization');

  if (!authorization) {
    return new Response(
      JSON.stringify({ error: `No authorization header passed` }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        authorization,
      },
    },
    auth: {
      persistSession: false,
    },
  });

  const { book_id } = await req.json();

  const { data: book } = await supabase
    .from('books_with_storage_path')
    .select()
    .eq('id', book_id)
    .single();

  if (!book?.pdf_url) {
    return new Response(
      JSON.stringify({ error: 'Failed to find uploaded book' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  // const fileContents = await file.text();
  const markdown = await pdfToMarkdown(book.pdf_url);
  const processedMd = processMarkdown(markdown);

  const { error } = await supabase.from('book_chunks').insert(
    processedMd.sections.map(({ content }) => ({
      book_id,
      content,
    }))
  );

  if (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: 'Failed to save book chunks' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  console.log(
    `Saved ${processedMd.sections.length} chunks for ${book.subject} book of ${book.class_level}`
  );

  return new Response(null, {
    status: 204,
    headers: { 'Content-Type': 'application/json' },
  });
});