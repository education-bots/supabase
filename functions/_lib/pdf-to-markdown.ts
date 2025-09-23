import { parsePdf } from "pdf2md-js";

const apiKey = Deno.env.get('GEMINI_API_KEY');

export async function pdfToMarkdown(dataBuffer: Blob): Promise<string> {

  const result = await parsePdf(dataBuffer, {
    apiKey: apiKey,
    model: 'gemini-2.0-flash',
    useFullPage: true, // Use full page processing mode
    prompt: `Use Markdown syntax to convert the text recognized from the image into Markdown format. You must follow these rules:

1. Output the text in the **same language** as recognized in the image (e.g., if the field is in English, output it in English).
2. Do not explain or output irrelevant text — only output the content from the image.
3. Do not wrap the content in \`\`\`markdown code blocks. Use \`$$ $$\` for block formulas and \`$ $\` for inline formulas.
4. Ignore content in headers and footers.
5. Do not apply Markdown formatting to image titles — output them directly as plain text.
6. Journal names, paper titles, conference names, or book names may appear on each page. Ignore them and do not recognize them as titles.
7. Carefully analyze the text structure and visual layout of the current PDF page, and handle it as follows:

   1. Recognize all heading text and determine their levels (based on font size, boldness, position, etc.).
   2. Output as hierarchical Markdown format, strictly following these rules:

      * Level 1 heading: largest font / top-centered → prefix with \`#\`
      * Level 2 heading: larger font / left-aligned bold (may start with a number or Roman numeral) → prefix with \`##\`
      * Level 3 heading: slightly larger font / left-aligned bold → prefix with \`###\`
      * Body text: directly converted into normal paragraphs
   3. If a heading’s level is uncertain, mark it as \`[?]\`.
   4. If the document is in Chinese but contains an English title and abstract, you may omit them and not output.
8. If there are lists:

   * Ordered lists must use \`1. 2. 3.\` format (standard Markdown ordered list).
   * Unordered lists must use \`*\` for each item (standard Markdown unordered list).
9. If there are tables: convert them into proper Markdown table format with \`|\` separators and header alignment rows (\`---\`).
10. **Strict rule:** every heading must be marked with \`#\` according to its level (no skipped or plain-text headings). Page titles must also follow this.
11. Use clear spacing, do not add extra spaces, and do not break lines unless necessary.
`
  });

  return result.content;
}
