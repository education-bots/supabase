-- ======================================
-- QUIZZES TABLE MIGRATION
-- ======================================

-- Create quizzes table with lesson reference and type-based conditional fields
CREATE TABLE IF NOT EXISTS public.quizzes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid REFERENCES public.lessons(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('blanks', 'mcqs', 'short_answer')),
  question text NOT NULL,
  
  -- Conditional fields for MCQs
  options jsonb, -- Array of options for MCQ type: ["Option A", "Option B", "Option C", "Option D"]
  correct_answer text, -- Required for all types
  
  -- Metadata
  created_by uuid REFERENCES public.profiles(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  
  -- Constraints to ensure correct_answer is provided for all types
  CONSTRAINT check_correct_answer_required CHECK (correct_answer IS NOT NULL AND correct_answer != ''),
  
  -- Constraint to ensure options are provided for MCQ type
  CONSTRAINT check_mcq_options_required CHECK (
    (type = 'mcqs' AND options IS NOT NULL AND jsonb_array_length(options) > 0)
    OR (type != 'mcqs')
  )
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_quizzes_lesson_id ON public.quizzes (lesson_id);
CREATE INDEX IF NOT EXISTS idx_quizzes_type ON public.quizzes (type);
CREATE INDEX IF NOT EXISTS idx_quizzes_created_by ON public.quizzes (created_by);

-- ======================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ======================================

-- Enable RLS on quizzes table
ALTER TABLE public.quizzes ENABLE ROW LEVEL SECURITY;

-- Policy: Authenticated users can view quizzes
CREATE POLICY "quizzes_select_authenticated" ON public.quizzes 
  FOR SELECT TO authenticated 
  USING (TRUE);

-- Policy: Only admins can insert quizzes
CREATE POLICY "quizzes_insert_admin_only" ON public.quizzes 
  FOR INSERT TO authenticated 
  WITH CHECK (public.is_admin(auth.uid()));

-- Policy: Only admins can update quizzes
CREATE POLICY "quizzes_update_admin_only" ON public.quizzes 
  FOR UPDATE TO authenticated 
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- Policy: Only admins can delete quizzes
CREATE POLICY "quizzes_delete_admin_only" ON public.quizzes 
  FOR DELETE TO authenticated 
  USING (public.is_admin(auth.uid()));

-- ======================================
-- TRIGGER FOR UPDATED_AT
-- ======================================

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_quizzes_updated_at
  BEFORE UPDATE ON public.quizzes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

--------------------------------------------------------------------------------
-- DROP PARENTS TABLE
--------------------------------------------------------------------------------
DROP TABLE IF EXISTS public.parent_children CASCADE;

--------------------------------------------------------------------------------
-- END OF QUIZZES MIGRATION
--------------------------------------------------------------------------------
