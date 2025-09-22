supabase login  
supabase link --project-ref qotoihqktcxolhymvbup  
supabase migration new <filename>  
supabase db push  
npx supabase functions deploy  

<!-- TypeScript -->
<!-- Generate types -->

supabase gen types typescript --project-id qotoihqktcxolhymvbup > src/lib/database.types.ts

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
