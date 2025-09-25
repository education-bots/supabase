const apiKey = Deno.env.get('API_KEY');
/**
 * Send a URL to pdf-to-md API and return converted Markdown string
 */
export async function pdfToMarkdown(url: string): Promise<string> {

  const res = await fetch("https://pdf2md-api.vercel.app/api/pdf-to-md", {
    method: "POST",
    body: JSON.stringify({ url }),
    headers: {
    "x-api-key": apiKey,
    "Content-Type": "application/json"
  }
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API error ${res.status}: ${text}`);
  }

  const data = await res.json();
  return data.markdown;
}
