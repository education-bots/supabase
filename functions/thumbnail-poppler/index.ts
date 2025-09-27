import { createClient } from '@supabase/supabase-js';
import { Database } from '../_types/database.types.ts';

// These are automatically injected
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

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

    // Download the PDF file
    const pdfResponse = await fetch(pdf_url);
    if (!pdfResponse.ok) {
      throw new Error(`Failed to download PDF: ${pdfResponse.statusText}`);
    }

    const pdfBuffer = await pdfResponse.arrayBuffer();
    
    // Convert PDF first page to image using poppler-utils
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
});

// Function to convert PDF to image using poppler-utils
async function convertPdfToImage(pdfBuffer: ArrayBuffer): Promise<Uint8Array> {
  try {
    // Use poppler-utils to convert PDF to image
    // This requires poppler-utils to be installed in the Deno environment
    
    // Create a temporary file for the PDF
    const tempPdfPath = `/tmp/temp_${Date.now()}.pdf`;
    const tempImagePath = `/tmp/temp_${Date.now()}.jpg`;
    
    // Write PDF buffer to temporary file
    await Deno.writeFile(tempPdfPath, new Uint8Array(pdfBuffer));
    
    // Use pdftoppm command to convert first page to JPEG
    const command = new Deno.Command('pdftoppm', {
      args: [
        '-jpeg',
        '-f', '1',  // First page
        '-l', '1',  // Last page (only first page)
        '-scale-to', '200',  // Scale to 200px width
        tempPdfPath,
        tempImagePath.replace('.jpg', '')  // Remove extension as pdftoppm adds it
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
    
    // Fallback: Create a placeholder image
    return await createPlaceholderThumbnail();
  }
}

// Fallback function to create a placeholder thumbnail
async function createPlaceholderThumbnail(): Promise<Uint8Array> {
  const canvas = new OffscreenCanvas(200, 300);
  const ctx = canvas.getContext('2d');
  
  if (!ctx) {
    throw new Error('Failed to get canvas context');
  }
  
  // Draw a placeholder thumbnail
  ctx.fillStyle = '#f0f0f0';
  ctx.fillRect(0, 0, 200, 300);
  
  ctx.fillStyle = '#333';
  ctx.font = '16px Arial';
  ctx.textAlign = 'center';
  ctx.fillText('PDF Thumbnail', 100, 150);
  ctx.fillText('Page 1', 100, 180);
  
  // Convert canvas to JPEG
  const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.8 });
  const arrayBuffer = await blob.arrayBuffer();
  
  return new Uint8Array(arrayBuffer);
}
