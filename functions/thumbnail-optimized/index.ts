import { createClient } from '@supabase/supabase-js';
import { Database } from '../_types/database.types.ts';

// These are automatically injected
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

// Configuration for handling large PDFs
const MAX_PDF_SIZE = 10 * 1024 * 1024; // 10MB limit
const THUMBNAIL_WIDTH = 200;
const THUMBNAIL_HEIGHT = 300;

Deno.serve(async (req) => {
  if (!supabaseUrl || !supabaseServiceKey) {
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

  const { book_id, pdf_url } = await req.json();

  if (!book_id || !pdf_url) {
    return new Response(
      JSON.stringify({ error: 'Missing book_id or pdf_url' }),
      {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  try {
    // Create Supabase client with service role key for admin operations
    const supabase = createClient<Database>(supabaseUrl, supabaseServiceKey, {
      auth: {
        persistSession: false,
      },
    });

    // Check PDF size before downloading
    const headResponse = await fetch(pdf_url, { method: 'HEAD' });
    const contentLength = headResponse.headers.get('content-length');
    
    if (contentLength && parseInt(contentLength) > MAX_PDF_SIZE) {
      console.log(`PDF too large (${contentLength} bytes), creating placeholder thumbnail`);
      return await createPlaceholderThumbnail(supabase, book_id);
    }

    // Download the PDF file with timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000); // 30 second timeout

    const pdfResponse = await fetch(pdf_url, { 
      signal: controller.signal,
      headers: {
        'Range': 'bytes=0-1048576' // Only download first 1MB for thumbnail
      }
    });
    
    clearTimeout(timeoutId);

    if (!pdfResponse.ok) {
      throw new Error(`Failed to download PDF: ${pdfResponse.statusText}`);
    }

    const pdfBuffer = await pdfResponse.arrayBuffer();
    
    // Check if we got the full file or just a partial
    const isPartial = pdfResponse.status === 206;
    
    if (isPartial || pdfBuffer.byteLength > MAX_PDF_SIZE) {
      console.log('PDF too large or partial download, creating placeholder');
      return await createPlaceholderThumbnail(supabase, book_id);
    }

    // Convert PDF first page to image
    const thumbnailBuffer = await convertPdfToImage(pdfBuffer);
    
    // Generate a unique filename for the thumbnail
    const thumbnailFileName = `thumbnail_${book_id}.jpg`;
    
    // Upload thumbnail to the thumbnails bucket
    const { data: uploadData, error: uploadError } = await supabase.storage
      .from('book_thumbnails')
      .upload(thumbnailFileName, thumbnailBuffer, {
        contentType: 'image/jpeg',
        upsert: true
      });

    if (uploadError) {
      throw new Error(`Failed to upload thumbnail: ${uploadError.message}`);
    }

    // Get the public URL for the thumbnail
    const { data: urlData } = supabase.storage
      .from('book_thumbnails')
      .getPublicUrl(thumbnailFileName);

    const thumbnailUrl = urlData.publicUrl;

    // Update the books table with the thumbnail URL
    const { error: updateError } = await supabase
      .from('books')
      .update({ thumbnail_url: thumbnailUrl })
      .eq('id', book_id);

    if (updateError) {
      throw new Error(`Failed to update book with thumbnail URL: ${updateError.message}`);
    }

    console.log(`Successfully created thumbnail for book ${book_id}: ${thumbnailUrl}`);

    return new Response(
      JSON.stringify({
        success: true,
        thumbnail_url: thumbnailUrl,
        book_id: book_id
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );

  } catch (error) {
    console.error('Thumbnail generation error:', error);
    
    // If any error occurs, create a placeholder thumbnail
    try {
      const supabase = createClient<Database>(supabaseUrl, supabaseServiceKey, {
        auth: { persistSession: false },
      });
      return await createPlaceholderThumbnail(supabase, book_id);
    } catch (fallbackError) {
      return new Response(
        JSON.stringify({
          error: 'Failed to generate thumbnail',
          details: error.message
        }),
        {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }
  }
});

// Optimized function to convert PDF to image
async function convertPdfToImage(pdfBuffer: ArrayBuffer): Promise<Uint8Array> {
  try {
    // Use poppler-utils with optimized settings
    const tempPdfPath = `/tmp/temp_${Date.now()}.pdf`;
    const tempImagePath = `/tmp/temp_${Date.now()}.jpg`;
    
    // Write PDF buffer to temporary file
    await Deno.writeFile(tempPdfPath, new Uint8Array(pdfBuffer));
    
    // Use pdftoppm with optimized settings for large PDFs
    const command = new Deno.Command('pdftoppm', {
      args: [
        '-jpeg',
        '-f', '1',           // First page only
        '-l', '1',           // Last page (only first page)
        '-scale-to', THUMBNAIL_WIDTH.toString(),
        '-scale-to-y', THUMBNAIL_HEIGHT.toString(),
        '-r', '72',          // Lower resolution for faster processing
        '-cropbox',          // Use cropbox for better performance
        tempPdfPath,
        tempImagePath.replace('.jpg', '')
      ],
    });
    
    const { code, stderr } = await command.output();
    
    if (code !== 0) {
      throw new Error(`pdftoppm failed: ${new TextDecoder().decode(stderr)}`);
    }
    
    // Read the generated image
    const imageData = await Deno.readFile(tempImagePath);
    
    // Clean up temporary files
    try {
      await Deno.remove(tempPdfPath);
      await Deno.remove(tempImagePath);
    } catch (cleanupError) {
      console.warn('Failed to clean up temporary files:', cleanupError);
    }
    
    return imageData;
    
  } catch (error) {
    console.error('PDF conversion error:', error);
    throw error; // Re-throw to trigger fallback
  }
}

// Create a placeholder thumbnail for large PDFs
async function createPlaceholderThumbnail(supabase: any, book_id: string) {
  const thumbnailBuffer = await createPlaceholderImage();
  const thumbnailFileName = `thumbnail_${book_id}.jpg`;
  
  // Upload placeholder thumbnail
  const { error: uploadError } = await supabase.storage
    .from('book_thumbnails')
    .upload(thumbnailFileName, thumbnailBuffer, {
      contentType: 'image/jpeg',
      upsert: true
    });

  if (uploadError) {
    throw new Error(`Failed to upload placeholder thumbnail: ${uploadError.message}`);
  }

  // Get the public URL
  const { data: urlData } = supabase.storage
    .from('book_thumbnails')
    .getPublicUrl(thumbnailFileName);

  const thumbnailUrl = urlData.publicUrl;

  // Update the books table
  const { error: updateError } = await supabase
    .from('books')
    .update({ thumbnail_url: thumbnailUrl })
    .eq('id', book_id);

  if (updateError) {
    throw new Error(`Failed to update book with placeholder thumbnail: ${updateError.message}`);
  }

  return new Response(
    JSON.stringify({
      success: true,
      thumbnail_url: thumbnailUrl,
      book_id: book_id,
      placeholder: true
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// Create a placeholder image
async function createPlaceholderImage(): Promise<Uint8Array> {
  const canvas = new OffscreenCanvas(THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT);
  const ctx = canvas.getContext('2d');
  
  if (!ctx) {
    throw new Error('Failed to get canvas context');
  }
  
  // Draw a placeholder thumbnail
  ctx.fillStyle = '#f0f0f0';
  ctx.fillRect(0, 0, THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT);
  
  // Add a border
  ctx.strokeStyle = '#ddd';
  ctx.lineWidth = 2;
  ctx.strokeRect(1, 1, THUMBNAIL_WIDTH - 2, THUMBNAIL_HEIGHT - 2);
  
  // Add text
  ctx.fillStyle = '#666';
  ctx.font = 'bold 14px Arial';
  ctx.textAlign = 'center';
  ctx.fillText('PDF Document', THUMBNAIL_WIDTH / 2, THUMBNAIL_HEIGHT / 2 - 10);
  
  ctx.font = '12px Arial';
  ctx.fillText('Large File', THUMBNAIL_WIDTH / 2, THUMBNAIL_HEIGHT / 2 + 10);
  
  // Convert canvas to JPEG
  const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.8 });
  const arrayBuffer = await blob.arrayBuffer();
  
  return new Uint8Array(arrayBuffer);
}
