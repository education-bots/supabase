-- supabase_schema.sql
-- Schema for: profiles, agents, conversations, messages, lessons, books, book_chunks, progress, parent-child mapping
-- Includes RLS policies and helper functions
-- Run on your Supabase Postgres instance

-- 0) Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- provides gen_random_uuid()

--------------------------------------------------------------------------------
-- 1) PROFILES (app users: students, parents, teachers, admins)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE, -- link to Supabase auth user
  full_name text,
  role text NOT NULL DEFAULT 'student' CHECK (role IN ('student','parent','teacher','admin')),
  language_preference text DEFAULT 'ur',
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles (role);

--------------------------------------------------------------------------------
-- 2) AGENTS (AI Tutors)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  subject text,
  language text DEFAULT 'ur',
  description text,
  is_active boolean DEFAULT true,
  created_by uuid REFERENCES public.profiles(id),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agents_subject ON public.agents (subject);

--------------------------------------------------------------------------------
-- 3) PARENT-CHILD mapping (so parents can view/act for their children)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parent_children (
  parent_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  child_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (parent_id, child_id)
);

--------------------------------------------------------------------------------
-- 4) LESSONS (optional content)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  grade_level text,
  subject text,
  content jsonb,          -- structured content (slides, steps, quiz meta etc)
  language text DEFAULT 'ur',
  created_by uuid REFERENCES public.profiles(id),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lessons_grade_sub ON public.lessons (grade_level, subject);

--------------------------------------------------------------------------------
-- 5) BOOKS (pdf metadata pointing to Supabase Storage)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_level int NOT NULL,                  -- e.g. 1, 2, 3...
  subject text NOT NULL,
  title text NOT NULL,
  supabase_path text,                        -- path in storage bucket: "<bucket>/<path>"
  pdf_url text,                              -- public URL or signed URL
  is_public boolean DEFAULT false,           -- if true, anyone authenticated can view
  uploaded_by uuid REFERENCES public.profiles(id),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_books_class_subject ON public.books (class_level, subject);

--------------------------------------------------------------------------------
-- 6) Book chunk index (safe metadata visible to clients)
--    This table contains lightweight info (pinecone id, page, index).
--    The actual chunk_text (sensitive) is kept in book_chunks below (admin-only).
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.book_chunk_index (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid REFERENCES public.books(id) ON DELETE CASCADE,
  chunk_index int NOT NULL,   -- order of chunk
  page_number int,
  pinecone_id text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bci_book ON public.book_chunk_index (book_id);

--------------------------------------------------------------------------------
-- 7) Book chunks (full text -> admin / server only)
--    Keep the heavy/sensitive chunk_text here (RLS will restrict).
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.book_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid REFERENCES public.books(id) ON DELETE CASCADE,
  chunk_index int NOT NULL,
  page_number int,
  chunk_text text,            -- full text chunk (sensitive)
  pinecone_id text,           -- id returned by Pinecone for this chunk
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_book_chunks_book ON public.book_chunks (book_id);

--------------------------------------------------------------------------------
-- 8) CONVERSATIONS (session-level)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE, -- the student
  agent_id uuid REFERENCES public.agents(id),
  started_at timestamptz DEFAULT now(),
  ended_at timestamptz,
  status text DEFAULT 'active' CHECK (status IN ('active','ended'))
);

CREATE INDEX IF NOT EXISTS idx_conversations_user ON public.conversations (user_id);

--------------------------------------------------------------------------------
-- 9) MESSAGES (chat history)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender text NOT NULL CHECK (sender IN ('user','agent','system')),
  sender_profile_id uuid,      -- if sender = 'user', points to profiles.id
  sender_agent_id uuid,        -- if sender = 'agent', points to agents.id
  message_text text,
  message_audio_url text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  CHECK (
    (sender = 'user' AND sender_profile_id IS NOT NULL AND sender_agent_id IS NULL)
    OR (sender = 'agent' AND sender_agent_id IS NOT NULL AND sender_profile_id IS NULL)
    OR (sender = 'system' AND sender_profile_id IS NULL AND sender_agent_id IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_messages_conv_created ON public.messages (conversation_id, created_at);

--------------------------------------------------------------------------------
-- 10) PROGRESS TRACKING
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.progress_tracking (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  subject text,
  lesson_id uuid REFERENCES public.lessons(id),
  score int,
  completed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_progress_user ON public.progress_tracking (user_id);

--------------------------------------------------------------------------------
-- 11) Helper functions for RLS checks
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin(uid uuid) RETURNS boolean LANGUAGE SQL STABLE AS $$
  SELECT CASE WHEN uid IS NULL THEN false
    ELSE (SELECT role FROM public.profiles WHERE id = uid) = 'admin'
  END;
$$;

CREATE OR REPLACE FUNCTION public.is_parent_of(parent_uuid uuid, child_uuid uuid) RETURNS boolean LANGUAGE SQL STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM public.parent_children pc WHERE pc.parent_id = parent_uuid AND pc.child_id = child_uuid);
$$;

--------------------------------------------------------------------------------
-- 12) ROW LEVEL SECURITY (RLS) POLICIES
--   - Profiles: users manage own, admins can do all
--   - Conversations/messages: user OR parent OR admin can read; inserts limited to owner/parent/admin
--   - Books: students/parents/teachers/admin can SELECT; manage by admin/teacher
--   - Book_chunks: full text only admin/teacher (server uses service_role)
--------------------------------------------------------------------------------

-- PROFILES RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_select_own" ON public.profiles FOR SELECT USING ( auth.uid() = id );
CREATE POLICY "profiles_insert_own" ON public.profiles FOR INSERT WITH CHECK ( auth.uid() = id );
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE USING ( auth.uid() = id ) WITH CHECK ( auth.uid() = id );

CREATE POLICY "profiles_admin_full" ON public.profiles FOR ALL TO authenticated USING ( public.is_admin(auth.uid()) ) WITH CHECK ( public.is_admin(auth.uid()) );

-- CONVERSATIONS RLS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "conversations_select_owner_parent_admin" ON public.conversations FOR SELECT USING (
  auth.uid() = user_id
  OR public.is_parent_of(auth.uid(), user_id)
  OR public.is_admin(auth.uid())
);

CREATE POLICY "conversations_insert_owner_or_parent_or_admin" ON public.conversations FOR INSERT WITH CHECK (
  auth.uid() = user_id
  OR public.is_parent_of(auth.uid(), user_id)
  OR public.is_admin(auth.uid())
);

CREATE POLICY "conversations_update_owner_or_admin" ON public.conversations FOR UPDATE USING (
  auth.uid() = user_id OR public.is_admin(auth.uid())
) WITH CHECK (
  auth.uid() = user_id OR public.is_admin(auth.uid())
);

CREATE POLICY "conversations_delete_admin_only" ON public.conversations FOR DELETE USING (
  public.is_admin(auth.uid())
);

-- MESSAGES RLS
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Allow reading messages if you own the conversation, are the parent of the conversation user, or an admin
CREATE POLICY "messages_select_participant_parent_admin" ON public.messages FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_id
      AND (
        c.user_id = auth.uid()
        OR public.is_parent_of(auth.uid(), c.user_id)
        OR public.is_admin(auth.uid())
      )
  )
);

-- Insert messages: user can insert own messages (and only for their own conversations), admin can insert as well.
CREATE POLICY "messages_insert_user_or_admin" ON public.messages FOR INSERT WITH CHECK (
  (
    sender = 'user'
    AND sender_profile_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.conversations c WHERE c.id = conversation_id AND c.user_id = auth.uid())
  )
  OR public.is_admin(auth.uid())
);

-- Allow admins to update/delete messages; no normal user update/delete
CREATE POLICY "messages_admin_crud" ON public.messages FOR UPDATE USING ( public.is_admin(auth.uid()) ) WITH CHECK ( public.is_admin(auth.uid()) );
CREATE POLICY "messages_admin_delete" ON public.messages FOR DELETE USING ( public.is_admin(auth.uid()) );

-- BOOKS RLS
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;

-- Allow SELECT to authenticated users (students/parents/teachers/admin); or public books
CREATE POLICY "books_select_authenticated_or_public" ON public.books FOR SELECT USING (
  is_public
  OR (SELECT role FROM public.profiles WHERE id = auth.uid()) IS NOT NULL
);

-- Manage books only by admin or teacher
CREATE POLICY "books_manage_admin_teacher" ON public.books FOR ALL TO authenticated USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('admin','teacher')
) WITH CHECK ( (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('admin','teacher') );

-- BOOK CHUNK INDEX (safe metadata)
ALTER TABLE public.book_chunk_index ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bci_select_authenticated" ON public.book_chunk_index FOR SELECT USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IS NOT NULL
);

-- BOOK CHUNKS (full text) - admin/teacher only (server/service_role should be used for ingestion/QA)
ALTER TABLE public.book_chunks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "book_chunks_admin_only" ON public.book_chunks FOR ALL USING ( public.is_admin(auth.uid()) OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'teacher' ) WITH CHECK ( public.is_admin(auth.uid()) OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'teacher' );

-- LESSONS RLS
ALTER TABLE public.lessons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "lessons_select_authenticated" ON public.lessons FOR SELECT USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) IS NOT NULL );
CREATE POLICY "lessons_manage_admin_teacher" ON public.lessons FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('admin','teacher') ) WITH CHECK ( (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('admin','teacher') );

-- PROGRESS TRACKING RLS
ALTER TABLE public.progress_tracking ENABLE ROW LEVEL SECURITY;
CREATE POLICY "progress_select_owner_or_parent_or_admin" ON public.progress_tracking FOR SELECT USING (
  user_id = auth.uid()
  OR public.is_parent_of(auth.uid(), user_id)
  OR public.is_admin(auth.uid())
);
CREATE POLICY "progress_insert_owner_or_admin" ON public.progress_tracking FOR INSERT WITH CHECK (
  user_id = auth.uid()
  OR public.is_admin(auth.uid())
);
CREATE POLICY "progress_update_owner_or_admin" ON public.progress_tracking FOR UPDATE USING (
  user_id = auth.uid() OR public.is_admin(auth.uid())
) WITH CHECK (
  user_id = auth.uid() OR public.is_admin(auth.uid())
);

--------------------------------------------------------------------------------
-- 13) Useful sample inserts (replace <AUTH_USER_UUID> placeholders with real ids)
--------------------------------------------------------------------------------
-- Example: create an admin profile for an existing auth user
-- INSERT INTO public.profiles (id, full_name, role) VALUES ('<AUTH_USER_UUID>', 'Admin Name', 'admin');

-- Example: create a sample book (after uploading to storage)
-- INSERT INTO public.books (class_level, subject, title, supabase_path, pdf_url, is_public, uploaded_by)
-- VALUES (1, 'Math', 'Class 1 Mathematics', 'books/class1/math.pdf', 'https://<YOUR-PROJECT>.supabase.co/storage/v1/object/public/books/class1/math.pdf', true, '<AUTH_USER_UUID>');

--------------------------------------------------------------------------------
-- END OF FILE
--------------------------------------------------------------------------------
