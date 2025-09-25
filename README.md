supabase login  
supabase link --project-ref qotoihqktcxolhymvbup  
supabase migration new <filename>  
supabase db push  
npx supabase functions deploy  
supabase secrets set GEMINI_API_KEY=your_gemini_api_key  

<!-- TypeScript -->
<!-- Generate types -->

supabase gen types typescript --project-id qotoihqktcxolhymvbup > types/database.types.ts

<!-- Python -->


```bash
├── README.md
├── migrations                # database migrations
│   └── 20250907155943_init_schema.sql
├── types                     # types
│   │   <todo>                # python pydantic models
│   └── database.types.ts     # typescript types
└── config.toml
```
