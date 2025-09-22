import { createClient } from '@supabase/supabase-js';
import { processMarkdown } from '../_lib/markdown-parser.ts';
import { Database } from '../_types/database.types.ts'

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

  if (!book?.storage_object_path) {
    return new Response(
      JSON.stringify({ error: 'Failed to find uploaded book' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  const { data: file } = await supabase.storage
    .from('files')
    .download(book.storage_object_path);

  if (!file) {
    return new Response(
      JSON.stringify({ error: 'Failed to download storage object' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  const fileContents = await file.text();

  const processedMd = processMarkdown(fileContents);

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