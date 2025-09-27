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
    
    // Convert PDF first page to image using a web service or library
    // For this example, we'll use a simple approach with a PDF-to-image service
    const thumbnailBuffer = await convertPdfFirstPageToImage(pdfBuffer);
    
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

// Function to convert PDF first page to image using pdf2pic
async function convertPdfFirstPageToImage(pdfBuffer: ArrayBuffer): Promise<Uint8Array> {
  try {
    // Use pdf2pic library for PDF to image conversion
    // This requires the pdf2pic library to be available in the Deno environment
    
    // For now, we'll use a web-based PDF to image conversion service
    // You can replace this with a more robust solution
    
    // Create a FormData to send the PDF to a conversion service
    const formData = new FormData();
    const pdfBlob = new Blob([pdfBuffer], { type: 'application/pdf' });
    formData.append('file', pdfBlob, 'document.pdf');
    formData.append('format', 'jpeg');
    formData.append('page', '1');
    formData.append('width', '200');
    formData.append('height', '300');
    
    // Use a PDF conversion service (you might want to use a different service)
    const response = await fetch('https://api.pdf.co/v1/pdf/convert/to/jpg', {
      method: 'POST',
      headers: {
        'x-api-key': Deno.env.get('PDF_CO_API_KEY') || '', // You'll need to set this
      },
      body: formData
    });
    
    if (!response.ok) {
      throw new Error(`PDF conversion failed: ${response.statusText}`);
    }
    
    const result = await response.json();
    
    if (result.error) {
      throw new Error(`PDF conversion error: ${result.error}`);
    }
    
    // Download the converted image
    const imageResponse = await fetch(result.url);
    if (!imageResponse.ok) {
      throw new Error(`Failed to download converted image: ${imageResponse.statusText}`);
    }
    
    const imageBuffer = await imageResponse.arrayBuffer();
    return new Uint8Array(imageBuffer);
    
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
