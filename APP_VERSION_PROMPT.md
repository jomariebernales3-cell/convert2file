# ConvertAFile / DocuForge AI App Version Prompt

Build a complete Android/mobile app version of the existing ConvertAFile / DocuForge AI web system. The app must preserve every current feature, workflow, data rule, admin function, and document generation behavior from the PHP/MySQL system.

## Product Summary

ConvertAFile is an academic document conversion and generation workspace. Users upload a structure blueprint/template file, upload a data source file, map extracted content into the selected structure, choose styling/output options, preview the generated result, optionally edit extracted images/tables, and download generated files. The app must also support a direct conversion mode where users upload one source file without a separate template.

The app must not promise exact visual cloning of uploaded files. It should clearly communicate that generated documents follow structure and style direction only, and users must review DOCX/PDF outputs before submission or printing.

## Recommended App Architecture

Use any modern mobile stack, but the preferred options are:

- Flutter Android app with REST API backend.
- React Native Android app with REST API backend.
- Capacitor/PWA wrapper if reusing the existing responsive web UI.
- Native Kotlin Android app if full native implementation is preferred.

The document parsing and generation logic should run on the server or in cloud functions, not fully on-device, unless the selected mobile stack has reliable libraries for DOCX, PDF, PPT/PPTX, images, and generated output files.

## User Roles

Implement two roles:

- `user`: can register, log in, upload own files, generate outputs, view/download own history, submit bug reports, and remove temporary uploads.
- `admin`: can log in, view all outputs/history, view all users, view logs, view all files, download/delete files, bulk delete files, delete files by date range/all, and view bug reports.

Authorization rules:

- Users can only access their own uploads and generated outputs.
- Admin can access and manage all users, files, logs, outputs, and bug reports.
- API requests must enforce session/token authentication and role checks.

## Authentication Features

Implement:

- Login with email and password.
- Register user account with name, email, and password.
- Password visibility toggle.
- Active/disabled account support.
- Role-based redirect after login.
- Logout with cleanup of unconsumed temporary uploads.
- CSRF protection for web/PWA or secure token equivalent for native apps.
- Default admin seed support from the existing database behavior.

## Database Model

Preserve these entities and fields:

### users

- `id`
- `name`
- `email`
- `password_hash`
- `role`: `admin` or `user`
- `status`: `active` or `disabled`
- `created_at`
- `updated_at`

### files

- `id`
- `user_id`
- `source_file_id`
- `kind`: `template_upload`, `data_upload`, `output_docx`, `output_pdf`, `output_txt`, `output_html`
- `original_name`
- `stored_name`
- `mime_type`
- `extension`
- `path`
- `size_bytes`
- `metadata_json`
- `created_at`

### templates

- `id`
- `user_id`
- `file_id`
- `title`
- `structure_json`
- `placeholders_json`
- `created_at`
- `updated_at`

### logs

- `id`
- `user_id`
- `level`: `info`, `warning`, `error`
- `event_type`
- `message`
- `context_json`
- `created_at`

### bug_reports

- `id`
- `user_id`
- `reporter_name`
- `reporter_email`
- `subject`
- `message`
- `screenshot_path`
- `screenshot_name`
- `status`: `new`, `reviewed`
- `created_at`

## Required Screens

### Landing / Overview

Show:

- ConvertAFile branding.
- Short explanation of structured conversion pipeline.
- CTA to open workspace.
- Feature cards for blueprint intelligence, content structuring, and styled output delivery.
- Workflow explanation: upload template, parse template, upload data, extract data, map content, generate outputs, persist metadata/logs, preview/download.

### Login / Register

Include:

- Login form.
- Registration form toggle.
- Password show/hide controls.
- Role-based navigation after login.
- Validation and inline feedback.

### User Dashboard

Include:

- Latest template ID metric.
- Latest data file ID metric.
- Warning banner about output limitations.
- Conversion mode switch:
  - With Template
  - Direct
- Upload progress indicators.
- Auto-fill IDs after successful uploads.
- Generation form and generated preview section.
- History and logout actions.
- Bug report action.

### With Template Workflow

Step 1: Upload Structure Blueprint

- Accept DOCX, PDF, TXT.
- Analyze template into structure, headings, sections, tables, lists, placeholders.
- Return and display:
  - `template_id`
  - `file_id`
  - title
  - section count
  - table count
  - list count
  - safety report

Step 2: Upload Data Source

- Accept DOCX, PDF, TXT, PPT, PPTX.
- Extract text, headings, paragraphs, lists, tables, key-values, important points, images, diagrams, formula references, and safety report.
- Return and display:
  - `file_id`
  - structured data summary
  - safety report

Step 3: Generate Styled Document

- Require template ID and data file ID.
- Map extracted data into template placeholders.
- Apply generation options.
- Produce preview and download links.

### Direct Conversion Workflow

Implement a one-upload conversion lane:

- Accept DOCX, PDF, TXT, PPT, PPTX.
- Ignore template ID.
- Use uploaded data source to build a direct document model.
- Preserve headings, paragraphs, lists, tables, images, diagrams, and formula references.
- Use style and advanced options during generation.

### Generation Options

Include all current options:

- Output style profile:
  - `academic`: Academic Report
  - `module`: Learning Module
  - `clean`: Clean Handout
- Content warning handling:
  - `sanitize`: exclude flagged content from output
  - `continue`: include warned content anyway
- Enable content summarization.
- Disable grammar cleanup.
- Download format:
  - DOCX
  - PDF
  - HTML
  - TXT
  - All available formats
- Optional custom output file name.
- Advanced options:
  - Font family: default, Aptos, Times New Roman, Arial, Arial Narrow, Calibri, Cambria, Garamond, Georgia, Book Antiqua, Palatino Linotype, Tahoma, Verdana, Trebuchet MS, Century Gothic, Courier New.
  - Paper size: A4, Letter, Legal.
  - Orientation: Portrait, Landscape.
  - Margin preset: Normal, Narrow, Wide.
  - Line spacing: 1.15, 1.5, 2.0.

### Generated Preview

After generation, show:

- Preview HTML in an in-app WebView or native preview screen.
- Download buttons for generated formats.
- Result page link/route.
- Safety report and warning action used.
- Note that preview is approximate and final DOCX/PDF should be reviewed.

### Image Editor

After preview generation, if extracted images exist, provide:

- List of editable images with preview thumbnails.
- Move image to another section.
- Placement selection.
- Width selection: small 30%, medium 45%, balanced 60%, large 80%, full width 100%.
- Rotation selection: 0, 90, 180, 270 degrees.
- Delete image from final output.
- Bulk image size apply.
- Reset image edits.
- Apply image edits, regenerate preview and download files.

### Table Editor

After preview generation, if extracted tables exist, provide:

- List of editable tables with preview.
- Move table to another section.
- Placement selection.
- Width selection: compact 45%, balanced 60%, wide 80%, full width 100%.
- Delete table from final output.
- Bulk table size apply.
- Reset table edits.
- Apply table edits, regenerate preview and download files.

### History Screen

Show paginated generated outputs:

- ID
- File name
- Format/kind
- Owner name/email
- Created date
- Download action

Rules:

- User sees own generated outputs only.
- Admin sees all generated outputs.

### Result Screen

Show selected generated output:

- File name.
- Download action.
- History action.
- HTML preview only if extension is HTML.
- For non-HTML outputs, show a message that preview is only available for generated HTML and the file should be downloaded.

### Bug Report

Authenticated users must be able to submit bug reports to admin:

- Subject, max 180 characters, minimum 4 characters.
- Message/details, minimum 12 characters.
- Optional screenshot upload.
- Screenshot types: PNG, JPG, JPEG, GIF, WEBP.
- Screenshot max size: 5 MB.
- Store reporter name/email from logged-in user.
- Show admin contact email.

### Admin Dashboard

Include:

- Users table with ID, name, email, role, file count.
- Recent logs table with level, event, user, message.
- Bug reports table with ID, reporter, subject, details, screenshot link, created date.
- All files table with checkbox selection, ID, file, kind, owner, created date, download/delete actions.
- Bulk selected file deletion.
- Advanced deletion:
  - Delete by date range.
  - Delete all files.
- Pagination for all admin tables.

## File Support

Template uploads:

- DOCX
- PDF
- TXT

Data uploads:

- DOCX
- PDF
- TXT
- PPT
- PPTX

Generated outputs:

- DOCX
- PDF
- HTML
- TXT
- All formats in one run.

Bug report screenshots:

- PNG
- JPG/JPEG
- GIF
- WEBP

## Document Parsing Requirements

Implement or preserve server-side parsing behavior:

- TXT: normalize raw text.
- DOCX: read OpenXML document text; preserve paragraph/table boundaries where possible.
- PDF: extract text from literal/hex text chunks and decoded streams; detect pages; repair spacing for slide-like PDFs; fallback to raw text extraction if needed.
- PPTX: parse slides, titles, body text, bullets, and tables from OpenXML.
- PPT: best-effort binary text extraction.
- Normalize line endings, spaces, repeated blank lines, HTML entities, and control characters.
- Detect and ignore likely binary artifacts.

## Data Extraction Requirements

Extract a structured data model containing:

- `title`
- `headings`
- `paragraphs`
- `lists`
- `tables`
- `important_points`
- `key_values`
- `blocks`
- `meta`

The `blocks` array must preserve ordered document structure with block types:

- `heading`
- `paragraph`
- `list`
- `table`
- `key_value`

Also extract:

- Emphasized lines and terms from DOCX/PPTX bold, color, and larger text.
- Structured tables from DOCX/PPTX.
- Images from DOCX/PPTX/PDF when possible.
- Diagram metadata from DOCX/PPTX.
- Formula references from PDFs, including page/crop images when renderer is available.

## Template Engine Requirements

Template analysis must:

- Detect headings using chapter/module/lesson/section/unit prefixes, numeric headings, uppercase headings, and similar academic heading patterns.
- Detect table rows by pipes or tab-separated content.
- Detect list items by hyphen, asterisk, or numbered bullets.
- Build placeholders:
  - `{{TITLE}}`
  - `{{SECTION_*}}`
  - `{{CONTENT_*}}`
  - `{{TABLE_*}}`
  - `{{LIST_*}}`
- Build fallback sections if no headings are found.

Direct mode must:

- Build a document model directly from extracted data blocks.
- Merge duplicate sections.
- Attach images/diagrams to best matching sections.
- Add Visual References section for unplaced images.
- Add Diagram Notes section for unplaced diagrams.
- Add Formula References section for formula-heavy PDFs.
- Deduplicate repeated paragraphs, lists, tables, images, and diagrams.

## Mapping Engine Requirements

Map source data into template sections:

- Match headings by similarity and containment.
- Assign important points, key-values, lists, tables, images, and diagrams to best matching template sections.
- Preserve tables as table blocks.
- Preserve images as image blocks with path, caption, width percent, and rotation metadata.
- Preserve diagrams as diagram blocks with title, summary, points, and diagram type.
- Support grammar cleanup unless disabled.
- Support summarization when enabled.
- Highlight emphasized terms for module style.

## Output Generation Requirements

Generate:

- HTML preview.
- TXT output.
- DOCX output using PHPWord or equivalent.
- PDF output using Dompdf or equivalent.
- Fallback DOCX builder if full DOCX library is unavailable.

Output must persist generated files in the database and storage with:

- user ID
- source data file ID
- output kind
- original/stored names
- MIME type
- extension
- path
- file size
- metadata

Output file naming:

- Use custom output name if provided.
- Otherwise derive from title/template/source.
- Sanitize invalid filename characters.
- Default to `converted-file` if blank.

## Content Safety Requirements

Scan uploaded template and data text for:

- PDF artifacts: `obj`, `endobj`, `xref`, `startxref`, `trailer`, `stream`, `endstream`.
- Emoji and pictographic characters.
- Uncommon/decorative symbols.
- Broken replacement character.
- Artifact-only lines.

If safety issues exist:

- Show warning before generation unless user selected a preference.
- Allow user to sanitize/exclude flagged content.
- Allow user to continue with warned content.
- Include safety report in API response and UI.

## API Contract To Preserve

If building on top of the current backend, call these endpoints:

- `POST /api/login.php`: login, returns user and redirect.
- `POST /api/register.php`: create user account.
- `POST /api/upload-template.php`: upload DOCX/PDF/TXT template, returns template ID and analysis summary.
- `POST /api/upload-data.php`: upload DOCX/PDF/TXT/PPT/PPTX data file, returns file ID and structured data.
- `POST /api/remove-upload.php`: remove temporary template/data upload.
- `POST /api/generate-document.php`: generate outputs.
- `POST /api/apply-preview-edits.php`: regenerate after image/table edits.
- `GET /api/history.php`: paginated output history.
- `GET /api/preview.php?id=...`: HTML preview for generated HTML outputs.
- `GET /api/download.php?id=...`: authenticated file download.
- `POST /api/report-bug.php`: submit bug report with optional screenshot.
- `GET /api/admin-users.php`: admin user list.
- `GET /api/admin-logs.php`: admin logs.
- `GET /api/admin-files.php`: admin all-files list.
- `GET /api/admin-bug-reports.php`: admin bug reports.
- `POST /api/admin-delete-output.php`: delete one generated output.
- `POST /api/admin-delete-files.php`: delete one or more file IDs.
- `POST /api/admin-delete-files-advanced.php`: delete by date range or delete all files.

For native Android, replace PHP sessions/CSRF with secure access tokens only if the backend is rebuilt. If using the current backend, preserve cookies and CSRF token handling through the app WebView/API client.

## Generate Document Request Fields

Send:

- `template_id`
- `data_file_id`
- `direct_convert`
- `style_profile`
- `warning_action`
- `summarize`
- `disable_cleanup`
- `output_format`
- `output_name`
- `font_family`
- `paper_size`
- `page_orientation`
- `margin_preset`
- `line_spacing`

Rules:

- `data_file_id` is always required.
- `template_id` is required only when `direct_convert` is false.
- `output_format=all` generates DOCX, PDF, HTML, and TXT.
- Valid style profiles: `academic`, `module`, `clean`.
- Valid warning actions: `sanitize`, `continue`.

## Apply Preview Edits Request Fields

Send:

- `data_file_id`
- `template_model_json`
- `mapping_json`
- `generation_options_json`

Use this after image/table edits and regenerate all selected formats.

## UX Requirements

- Mobile-first layout.
- Touch-friendly upload controls.
- Progress indicators during upload and generation.
- Clear empty/loading/error/success states.
- Use bottom navigation or dashboard tabs for common app areas.
- Use cards only for repeated items and functional panels.
- Avoid marketing-only screens after login; show the usable workspace immediately.
- Keep warnings visible but not obstructive.
- Make download/share/open-file actions native-feeling on Android.
- Support preview in WebView for generated HTML.
- Use Android file picker and share/download intents where applicable.

## Offline / Mobile Requirements

At minimum:

- Cache login/session state securely.
- Cache recent history metadata.
- Cache generated preview metadata where safe.
- Queue bug report drafts and failed uploads only if secure local storage is available.
- Do not pretend document generation is offline if server processing is required.
- Show clear offline state and retry actions.

## Security Requirements

- Hash passwords server-side.
- Never store plain passwords.
- Restrict file access by user ownership and role.
- Validate file extensions and MIME types.
- Restrict screenshot size and image MIME types.
- Sanitize output filenames.
- Protect downloads from unauthorized access.
- Log important user/admin actions.
- Do not expose admin credentials in the app UI.

## Logging Events To Preserve

Log:

- `auth.login`
- `auth.login_failed`
- `auth.register`
- `auth.logout`
- `template.uploaded`
- `template.upload_failed`
- `data.uploaded`
- `data.upload_failed`
- `document.generated`
- `document.generate_failed`
- `preview.images_edited`
- `preview.images_edit_failed`
- `bug_report.created`
- `bug_report.create_failed`
- `admin.output_deleted`
- `admin.files_deleted`
- upload cleanup/removal events

## Acceptance Criteria

The app is complete only when:

- A normal user can register, log in, upload a template, upload data, generate DOCX/PDF/HTML/TXT, preview, download, edit images/tables, view history, and submit bug reports.
- A normal user can use direct conversion without a template.
- An admin can view users, logs, bug reports, all files, all output history, download files, delete selected files, delete by date range, and delete all files.
- File ownership restrictions work correctly.
- Safety warnings and sanitize/continue behavior work.
- All generation options are available in the app.
- The mobile UI clearly warns that generated documents are not exact visual clones.
- The app supports Android file picking, upload progress, preview, download, and share/open behavior.

