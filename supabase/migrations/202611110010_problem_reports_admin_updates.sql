-- The user ownership check is enforced by the insert RLS policy.
-- Keeping it as a table CHECK also blocks admins from updating reports
-- submitted by other users because CHECK constraints run on every update.
alter table public.problem_reports
  drop constraint if exists problem_reports_user_self;
