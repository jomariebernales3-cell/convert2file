-- Editable public App Info content controlled by active admin portal users.
create table if not exists public.app_info_content (
  id boolean primary key default true check (id),
  sections jsonb not null default '[]'::jsonb,
  release_notes jsonb not null default '[]'::jsonb,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint app_info_sections_array check (jsonb_typeof(sections) = 'array'),
  constraint app_info_release_notes_array check (jsonb_typeof(release_notes) = 'array')
);

alter table public.app_info_content enable row level security;
drop policy if exists app_info_public_read on public.app_info_content;
create policy app_info_public_read on public.app_info_content
  for select to anon, authenticated using (true);

revoke all on public.app_info_content from anon, authenticated;
grant select on public.app_info_content to anon, authenticated;

insert into public.app_info_content (id, sections, release_notes)
values (
  true,
  '[
    {"id":"purpose","title":"App Purpose","icon":"school","details":["Convert2File helps students and teachers turn lesson files and notes into usable documents, study guides, and quiz drafts on Android.","It combines on-device tools with optional online account and service features. You can also use a local guest workspace."]},
    {"id":"supported_files","title":"Supported Files","icon":"files","details":["Source files: PDF, DOCX, PPTX, legacy PPT, and TXT. Legacy PPT files have limited extraction support.","Create and conversion outputs: DOCX, PDF, HTML, and TXT. QR codes can be saved as PNG images.","Scanned or image-only PDFs may have little or no extractable text because OCR is not currently provided. Complex layouts may change during conversion."]},
    {"id":"privacy","title":"Privacy","icon":"privacy","details":["Selected source files are processed by the app and saved materials/history are stored on this device. Core conversion does not upload your documents to Convert2File storage.","If you sign in, Supabase handles account authentication and account profile data. The app also connects to Supabase for announcements, app controls, and submitted problem reports.","Problem reports are sent to the Convert2File project. Depending on your choices, a report may include your description, email, app/device details, technical context, and attached files. Chosen attachments are uploaded to private report storage.","Guest workspace files stay on this device. Web links and online services need an internet connection; offline AI runs on-device after you import a compatible model."]},
    {"id":"credits","title":"Credits","icon":"credits","details":["Project creator: Despair(0_0).","Built with Flutter and Dart. Local workspace data uses SQLite; account and app-management services use Supabase.","Development was AI-assisted with OpenAI Codex. The project creator is responsible for the app and its published content."]},
    {"id":"capabilities","title":"Capabilities","icon":"capabilities","details":["Convert documents, create files from typed text, build study guides, and draft quizzes. Review generated content and formatting before using it.","Study guides and quizzes can be created manually. AI-assisted actions require a compatible GGUF model imported on the device; model output can be incorrect.","The QR tool scans codes and creates QR images. Camera access is needed for scanning.","My Materials and History let you find and manage locally saved files and outputs. Android may ask for permission when saving images or accessing selected files.","Sharing offers the installed APK when Android exposes it, the public website link, or a QR code for that link. Installing APKs may require Android to allow installs from the app you use to open the file.","Online source links require internet access. Offline AI is performed on the device with the imported model, but speed and quality depend on the phone and model."]},
    {"id":"disclaimer","title":"Disclaimer","icon":"disclaimer","details":["Conversion and extraction can omit or rearrange content, especially in scanned PDFs, complex layouts, tables, and formulas. OCR is not available in this build.","AI-generated summaries, study guides, and quiz drafts may contain mistakes or invented details. Check facts, answers, and source material yourself.","Convert2File is a study and document utility, not a substitute for professional advice or the original course material. Review outputs before relying on, submitting, or sharing them."]}
  ]'::jsonb,
  '[
    {"version":"1.0.26.29","date":"Current build","is_latest":true,"features":["Refreshed App Info with current supported formats, privacy disclosures, capabilities, and limitations.","Added APK, website-link, and QR-code choices to Share App in Settings."],"fixes":["Corrected outdated text that described the app as local-only while it still uses Supabase for online services.","Updated release notes to reflect current account, guest, and online-service behavior."]},
    {"version":"1.0.25.28","date":"June 4, 2026","is_latest":false,"features":["Audited the Direct Workspace extraction pipeline after external file changes."],"fixes":["Prevented duplicate DOCX table rows and improved structured XML parsing."]},
    {"version":"1.0.24.27","date":"June 4, 2026","is_latest":false,"features":["Improved DOCX extraction for academic instruction files."],"fixes":["Preserved paragraph boundaries and table rows during extraction."]},
    {"version":"1.0.23.26","date":"June 4, 2026","is_latest":false,"features":["Added PDF extraction notes for layouts that may need review."],"fixes":["Reduced repeated header and footer text in extracted PDF content."]},
    {"version":"1.0.22.25","date":"June 4, 2026","is_latest":false,"features":["Added PDF-to-DOCX comparison and quality notes."],"fixes":["Improved formula warnings and numbering in extracted content."]},
    {"version":"1.0.21.24","date":"June 3, 2026","is_latest":false,"features":["Added formula-aware handling and App Info tool explanations."],"fixes":["Improved output filenames and preview export behavior."]},
    {"version":"1.0.20.23","date":"May 26, 2026","is_latest":false,"features":["Added password reset support."],"fixes":["Fixed the password reset cancel flow."]},
    {"version":"1.0.19.22","date":"May 25, 2026","is_latest":false,"features":["Improved DOCX output formatting, preview editing, and History search/filter controls."],"fixes":["Improved custom filenames and preview copy/export behavior."]},
    {"version":"1.0.18.21","date":"May 25, 2026","is_latest":false,"features":["Enabled Android internet access for online account services."],"fixes":["Fixed release account access configuration."]},
    {"version":"1.0.17.20","date":"May 25, 2026","is_latest":false,"features":["Improved account error messages."],"fixes":["Added clearer confirmation and rate-limit guidance."]},
    {"version":"1.0.16.19","date":"May 25, 2026","is_latest":false,"features":["Added direct sharing of the installed APK on supported Android devices."],"fixes":["Replaced the unpublished Play Store link."]},
    {"version":"1.0.15.18","date":"May 24, 2026","is_latest":false,"features":["Added Share App entry points to navigation and App Info."],"fixes":["Centralized app-sharing behavior."]},
    {"version":"1.0.14.17","date":"May 24, 2026","is_latest":false,"features":["Added online account profiles while retaining a local SQLite user mirror."],"fixes":["Preserved local history and files during account migration."]},
    {"version":"1.0.13.16","date":"May 24, 2026","is_latest":false,"features":["Updated workspace labels and version-history navigation."],"fixes":["Improved theme contrast and removed a duplicate dashboard title."]},
    {"version":"1.0.12.15","date":"May 24, 2026","is_latest":false,"features":["Simplified dashboard upload card labels."],"fixes":["Kept upload labels consistent."]},
    {"version":"1.0.11.14","date":"May 20, 2026","is_latest":false,"features":["Updated password visibility controls."],"fixes":["Corrected show/hide eye icons."]},
    {"version":"1.0.10.13","date":"May 20, 2026","is_latest":false,"features":["Renamed the app to Convert2File and expanded theme accents."],"fixes":["Improved visible theme updates."]},
    {"version":"1.0.9.12","date":"May 20, 2026","is_latest":false,"features":["Updated Convert2File app metadata and theme accents."],"fixes":["Improved theme color updates."]},
    {"version":"1.0.8.11","date":"May 20, 2026","is_latest":false,"features":["Improved theme selection and app version formatting."],"fixes":["Fixed stale selected theme states."]},
    {"version":"1.0.7.10","date":"May 20, 2026","is_latest":false,"features":["Updated DBZ theme placement and theme controls."],"fixes":["Limited accent choices to supported presets."]},
    {"version":"1.0.6.9","date":"May 20, 2026","is_latest":false,"features":["Added DBZ theme options and version selection in Update History."],"fixes":["Show the latest update by default."]},
    {"version":"1.0.5.8","date":"May 20, 2026","is_latest":false,"features":["Added App Info, creator details, and version history."],"fixes":["Added a place to record release notes."]},
    {"version":"1.0.4.7","date":"May 20, 2026","is_latest":false,"features":["Set Direct Workspace as the default app view.","Moved workspace choices below the user header."],"fixes":["Updated Android app version metadata."]},
    {"version":"1.0.3.6","date":"May 20, 2026","is_latest":false,"features":["Added a Profile screen, user activity graph, and Day/Night theme controls."],"fixes":["Added the profile-fields database migration."]},
    {"version":"1.0.2.5","date":"May 20, 2026","is_latest":false,"features":["Separated workspace entries in navigation."],"fixes":["Removed the old in-workspace mode switch."]},
    {"version":"1.0.1.4","date":"May 20, 2026","is_latest":false,"features":["Added hamburger navigation and grouped user actions."],"fixes":["Cleaned up dashboard app bar actions."]}
  ]'::jsonb
)
on conflict (id) do nothing;

create or replace function public.admin_update_app_info(
  p_sections jsonb,
  p_release_notes jsonb
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  section_item jsonb;
  release_item jsonb;
  latest_count integer;
  current_release_version text;
begin
  if not public.is_active_admin() then
    raise exception 'Administrator access required';
  end if;
  if coalesce(jsonb_typeof(p_sections), '') <> 'array' then
    raise exception 'App Info sections must be an array';
  end if;
  if jsonb_array_length(p_sections) not between 1 and 30 then
    raise exception 'Add between 1 and 30 App Info sections';
  end if;
  if coalesce(jsonb_typeof(p_release_notes), '') <> 'array' then
    raise exception 'Release history must be an array';
  end if;
  if jsonb_array_length(p_release_notes) not between 1 and 100 then
    raise exception 'Add between 1 and 100 release entries';
  end if;
  for section_item in select value from jsonb_array_elements(p_sections) loop
    if jsonb_typeof(section_item) <> 'object'
       or char_length(btrim(coalesce(section_item->>'title', ''))) not between 1 and 80
       or coalesce(jsonb_typeof(section_item->'details'), '') <> 'array'
       or jsonb_array_length(section_item->'details') < 1 then
      raise exception 'Each section needs a title and at least one detail';
    end if;
  end loop;
  for release_item in select value from jsonb_array_elements(p_release_notes) loop
    if jsonb_typeof(release_item) <> 'object'
       or char_length(btrim(coalesce(release_item->>'version', ''))) not between 1 and 32
       or char_length(btrim(coalesce(release_item->>'date', ''))) not between 1 and 64
       or coalesce(jsonb_typeof(release_item->'features'), '') <> 'array'
       or coalesce(jsonb_typeof(release_item->'fixes'), '') <> 'array' then
      raise exception 'Each release entry needs a version, date, features, and fixes';
    end if;
  end loop;
  select count(*), max(item->>'version') into latest_count, current_release_version
    from jsonb_array_elements(p_release_notes) as releases(item)
    where item->>'is_latest' = 'true';
  if latest_count <> 1 then
    raise exception 'Mark exactly one release entry as the current version';
  end if;
  update public.app_info_content
    set sections = p_sections,
        release_notes = p_release_notes,
        updated_by = (select auth.uid()),
        updated_at = now()
    where id = true;
  update public.app_control_settings
    set latest_version = current_release_version,
        updated_by = (select auth.uid()),
        updated_at = now()
    where id = true and latest_version is distinct from current_release_version;
  if found then
    perform public.write_admin_audit(
      'app_settings.updated', 'app_settings', 'global',
      jsonb_build_object('latest_version', current_release_version, 'source', 'app_info')
    );
  end if;
  perform public.write_admin_audit(
    'app_info.updated', 'app_info', 'global',
    jsonb_build_object(
      'section_count', jsonb_array_length(p_sections),
      'release_count', jsonb_array_length(p_release_notes),
      'current_version', current_release_version
    )
  );
end;
$$;

revoke all on function public.admin_update_app_info(jsonb, jsonb) from public, anon;
grant execute on function public.admin_update_app_info(jsonb, jsonb) to authenticated;
