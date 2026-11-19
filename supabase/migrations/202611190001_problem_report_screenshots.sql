alter table public.problem_reports
  add column if not exists screenshot_file_path text null;
