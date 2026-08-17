-- 002_curriculum_foundation.sql
-- Ders -> konu -> alt konu temel müfredat yapısı

CREATE TABLE IF NOT EXISTS public.subjects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  slug text NOT NULL UNIQUE,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  grade_level smallint NOT NULL CHECK (grade_level BETWEEN 1 AND 12),
  name text NOT NULL,
  slug text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (subject_id, grade_level, slug)
);

CREATE TABLE IF NOT EXISTS public.subtopics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid NOT NULL REFERENCES public.topics(id) ON DELETE CASCADE,
  name text NOT NULL,
  slug text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (topic_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_topics_subject_grade
  ON public.topics(subject_id, grade_level);

CREATE INDEX IF NOT EXISTS idx_subtopics_topic
  ON public.subtopics(topic_id);

ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subtopics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subjects_read_active ON public.subjects;
CREATE POLICY subjects_read_active
ON public.subjects
FOR SELECT
TO authenticated
USING (is_active = true);

DROP POLICY IF EXISTS topics_read_active ON public.topics;
CREATE POLICY topics_read_active
ON public.topics
FOR SELECT
TO authenticated
USING (is_active = true);

DROP POLICY IF EXISTS subtopics_read_active ON public.subtopics;
CREATE POLICY subtopics_read_active
ON public.subtopics
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_subjects_set_updated_at
ON public.subjects;

CREATE TRIGGER trigger_subjects_set_updated_at
BEFORE UPDATE ON public.subjects
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_topics_set_updated_at
ON public.topics;

CREATE TRIGGER trigger_topics_set_updated_at
BEFORE UPDATE ON public.topics
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_subtopics_set_updated_at
ON public.subtopics;

CREATE TRIGGER trigger_subtopics_set_updated_at
BEFORE UPDATE ON public.subtopics
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();