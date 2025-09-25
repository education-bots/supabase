const apiKey = Deno.env.get('API_KEY');
/**
 * Send a PDF (Buffer or Blob) to pdf-to-md API and return converted Markdown string
 */
export async function pdfToMarkdown(file: Buffer | Blob): Promise<string> {
  // Decide how to create the body
  let body: FormData | Buffer;
  let headers: HeadersInit = {};

  if (typeof Blob !== "undefined" && file instanceof Blob) {
    // Browser: use FormData
    body = new FormData();
    body.append("file", file, "document.pdf");
    // fetch will handle headers automatically
  } else {
    // Node.js Buffer: still send as multipart/form-data
    const formData = new FormData();
    formData.append("file", new Blob([file]), "document.pdf");
    body = formData;
  }

  const res = await fetch("https://pdf2md-api.vercel.app/api/pdf-to-md", {
    method: "POST",
    body,
    headers: {"x-api-key": apiKey}
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API error ${res.status}: ${text}`);
  }

  const data = await res.json();
  return data.markdown;
}
