--------------------------------------------------------------------------------
-- 1) PROFILES (app users: students, parents, teachers, admins)
-- Add a new column to store the class level of the user.
--------------------------------------------------------------------------------
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS class_level text NOT NULL;

--------------------------------------------------------------------------------
-- 2) DROP AGENTS (AI Tutors)
-- Remove the agents table completely since we no longer use AI tutor records.
--------------------------------------------------------------------------------
DROP TABLE IF EXISTS public.agents CASCADE;

--------------------------------------------------------------------------------
-- 3) DROP Book chunk index 
-- Remove book_chunk_index table if it exists.
--------------------------------------------------------------------------------
DROP TABLE IF EXISTS public.book_chunk_index CASCADE;

--------------------------------------------------------------------------------
-- 4) DROP Book chunks
-- Remove book_chunks table if it exists.
--------------------------------------------------------------------------------
DROP TABLE IF EXISTS public.book_chunks CASCADE;

--------------------------------------------------------------------------------
-- 5) CONVERSATIONS (session-level)
-- Recreate the conversations table without the agent_id foreign key.
--------------------------------------------------------------------------------
DROP TABLE IF EXISTS public.conversations CASCADE;

CREATE TABLE public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE, -- the student
  topic text,
  started_at timestamptz DEFAULT now(),
  status text DEFAULT 'active' CHECK (status IN ('active','ended'))
);

--------------------------------------------------------------------------------
-- 6) MESSAGES (chat history)
-- Recreate the messages table with foreign keys to conversations and profiles.
--------------------------------------------------------------------------------
DROP TABLE IF EXISTS public.messages CASCADE;

CREATE TABLE public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('user','agent','system')),
  message_text text,
  message_audio_url text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

--------------------------------------------------------------------------------
-- END OF FILE
--------------------------------------------------------------------------------
