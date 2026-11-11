import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { supabaseConfig } from './config.js';

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const date = (value) => value ? new Date(value).toLocaleString() : '—';
const shortDate = (value) => value ? new Date(value).toLocaleDateString() : '—';
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]));
const statusText = (value) => ({
  in_review: 'In review',
  seen: 'Seen',
  in_progress: 'In progress',
}[value] ?? value);
const badge = (value) => `<span class="pill ${esc(value)}">${esc(statusText(value))}</span>`;

let client;
let actor;
let account;
let role;
let users = [];
let reports = [];
const selectedReportIds = new Set();
let admins = [];
let auditEntries = [];
let announcements = [];
let editingAnnouncementId = null;
let appSettings = null;
let currentPage = 'dashboard';
const featureDefinitions = [
  ['offline_ai', 'AI assistant', 'Show the offline AI chat'],
  ['quiz_generator', 'Quiz generator', 'Allow quiz creation'],
  ['study_guides', 'Study guides', 'Allow study guide creation'],
  ['document_conversion', 'Document conversion', 'Allow document conversion'],
  ['qr_code', 'QR code', 'Allow QR code scanning and creation'],
  ['text_to_file', 'Text to file', 'Allow creating files from text'],
  ['my_materials', 'My materials', 'Allow access to saved files and outputs'],
];

function notice(message, isError = false) {
  const node = $('#notice');
  node.textContent = message;
  node.classList.toggle('error', isError);
  node.hidden = !message;
  if (message) window.setTimeout(() => { if (node.textContent === message) node.hidden = true; }, 6500);
}

function setTheme(choice) {
  localStorage.setItem('c2f-admin-theme', choice);
  const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  document.documentElement.dataset.theme = choice === 'system' ? (dark ? 'night' : 'day') : choice;
  $('#appearance').value = choice;
}

function showLogin(message = '') {
  $('#portal').hidden = true;
  $('#login').hidden = false;
  $('#login-error').textContent = message;
}

function showPortal() {
  $('#login').hidden = true;
  $('#portal').hidden = false;
  $('#identity').textContent = account.display_name || account.email;
  $('#role-label').textContent = role === 'owner' ? 'Owner' : 'Admin / Support';
  $$('.owner-only').forEach((node) => { node.hidden = role !== 'owner'; });
  if (currentPage === 'team' && role !== 'owner') showPage('dashboard');
}

async function loadActor() {
  const { data: { user }, error: authError } = await client.auth.getUser();
  if (authError || !user) { actor = account = null; role = null; showLogin(); return false; }
  actor = user;
  const { data: profile, error: profileError } = await client.from('profiles')
    .select('id,email,display_name,account_status').eq('id', user.id).maybeSingle();
  if (profileError || !profile) throw profileError ?? new Error('Your profile is not set up yet.');
  if (profile.account_status !== 'active') {
    await client.auth.signOut();
    actor = account = null; role = null;
    showLogin('This account is suspended. Contact the project Owner.');
    return false;
  }
  const { data: adminRow, error: adminError } = await client.from('admin_users')
    .select('role').eq('user_id', user.id).maybeSingle();
  if (adminError) throw adminError;
  if (!adminRow) {
    await client.auth.signOut();
    actor = account = null; role = null;
    showLogin('This account does not have admin access.');
    return false;
  }
  account = profile;
  role = adminRow.role;
  await client.rpc('record_my_login');
  showPortal();
  await refreshData();
  return true;
}

async function queryRows(table, fields, orderField = 'created_at') {
  const { data, error } = await client.from(table).select(fields).order(orderField, { ascending: false }).limit(500);
  if (error) throw error;
  return data ?? [];
}

async function refreshData() {
  if (!actor) return;
  $('#refresh').disabled = true;
  try {
    const { data: selfProfile, error: selfError } = await client.from('profiles')
      .select('account_status').eq('id', actor.id).maybeSingle();
    if (selfError || !selfProfile || selfProfile.account_status !== 'active') {
      await client.auth.signOut();
      actor = account = null; role = null;
      showLogin('This account is no longer active.');
      return;
    }
    const { data: selfAdmin, error: selfAdminError } = await client.from('admin_users')
      .select('role').eq('user_id', actor.id).maybeSingle();
    if (selfAdminError || !selfAdmin) {
      await client.auth.signOut();
      actor = account = null; role = null;
      showLogin('This account no longer has admin access.');
      return;
    }
    role = selfAdmin.role;
    showPortal();
    [users, reports, auditEntries] = await Promise.all([
      queryRows('profiles', 'id,email,display_name,account_status,created_at,last_seen_at'),
      queryRows('problem_reports', 'id,user_id,reporter_email,area,description,app_version,platform,device_info,context,status,admin_note,created_at'),
      queryRows('admin_audit_log', 'id,actor_id,action,target_type,target_id,details,created_at'),
    ]);
    [announcements, appSettings] = await Promise.all([
      queryRows('announcements', 'id,title,body,kind,starts_at,ends_at,is_active,link_url,link_label,created_at,updated_at'),
      (async () => {
        const { data, error } = await client.from('app_control_settings').select('*').eq('id', true).single();
        if (error) throw error;
        return data;
      })(),
    ]);
    admins = role === 'owner'
      ? await queryRows('admin_users', 'user_id,role,created_by,created_at')
      : [];
    drawDashboard(); drawUsers(); drawReports(); drawTeam(); drawAudit(); drawAnnouncements(); drawAppControl();
    notice('Data refreshed.');
  } catch (error) {
    notice(`Could not load portal data: ${error.message}`, true);
  } finally { $('#refresh').disabled = false; }
}

function drawDashboard() {
  const now = new Date();
  const week = new Date(now.getTime() - 7 * 86400000);
  const newUsers = users.filter((u) => new Date(u.created_at) >= week);
  const openReports = reports.filter((r) => r.status !== 'resolved');
  $('#stat-users').textContent = users.length;
  $('#stat-new').textContent = newUsers.length;
  $('#stat-open').textContent = openReports.length;
  $('#stat-suspended').textContent = users.filter((u) => u.account_status === 'suspended').length;

  const days = Array.from({ length: 7 }, (_, i) => {
    const day = new Date(); day.setHours(0, 0, 0, 0); day.setDate(day.getDate() - (6 - i));
    return { date: day, label: day.toLocaleDateString(undefined, { weekday: 'short' }), count: 0 };
  });
  newUsers.forEach((u) => {
    const created = new Date(u.created_at); created.setHours(0, 0, 0, 0);
    const match = days.find((d) => d.date.getTime() === created.getTime()); if (match) match.count++;
  });
  const max = Math.max(1, ...days.map((d) => d.count));
  $('#signup-chart').innerHTML = days.map((d) => `<div class="bar" title="${d.count} signups" style="height:${Math.max(8, d.count / max * 130)}px"><span>${esc(d.label)}</span></div>`).join('');
  $('#latest-reports').innerHTML = reports.slice(0, 5).map((r) => `<div class="row"><div><b>${esc(r.area.replaceAll('_', ' '))}</b><small>${esc(r.description.slice(0, 90))}${r.description.length > 90 ? '…' : ''}</small></div>${badge(r.status)}</div>`).join('') || '<p class="empty">No reports yet.</p>';
}

function drawUsers() {
  const q = $('#user-search').value.trim().toLowerCase();
  const status = $('#user-status').value;
  const matches = users.filter((u) => (!status || u.account_status === status) &&
    `${u.display_name} ${u.email}`.toLowerCase().includes(q));
  $('#users-body').innerHTML = matches.map((u) => `<tr class="clickable" data-user="${esc(u.id)}"><td><b>${esc(u.display_name || 'Unnamed account')}</b></td><td>${esc(u.email)}</td><td>${badge(u.account_status)}</td><td>${esc(shortDate(u.created_at))}</td><td>${esc(date(u.last_seen_at))}</td></tr>`).join('') || '<tr><td colspan="5" class="empty">No accounts found.</td></tr>';
}

function openUser(id) {
  const user = users.find((item) => item.id === id); if (!user) return;
  const admin = admins.find((item) => item.user_id === id);
  const canManage = !admin || role === 'owner';
  const suspend = user.account_status === 'active';
  $('#user-detail').innerHTML = `<h2>${esc(user.display_name || 'Unnamed account')}</h2>${badge(user.account_status)}${admin ? ` ${badge(admin.role)}` : ''}<div class="kv"><span>Email</span><b>${esc(user.email)}</b></div><div class="kv"><span>Joined</span><b>${esc(date(user.created_at))}</b></div><div class="kv"><span>Last seen</span><b>${esc(date(user.last_seen_at))}</b></div><p class="muted">This portal only manages the online account. Local-only files and workspaces stay on the user’s device.</p><div class="detail-actions">${canManage && user.id !== actor.id ? `<button id="user-status-action" class="button ${suspend ? 'danger' : 'primary'}">${suspend ? 'Suspend account' : 'Reactivate account'}</button>` : ''}<button class="button" onclick="document.querySelector('#user-dialog').close()">Close</button></div>`;
  $('#user-dialog').showModal();
  $('#user-status-action')?.addEventListener('click', async () => {
    if (!window.confirm(`${suspend ? 'Suspend' : 'Reactivate'} ${user.email}? This changes access to online services.`)) return;
    const { error } = await client.rpc('admin_set_user_status', { p_user_id: id, p_status: suspend ? 'suspended' : 'active' });
    if (error) { notice(error.message, true); return; }
    $('#user-dialog').close(); await refreshData();
  });
}

function drawReports() {
  const status = $('#report-status').value;
  const matches = reports.filter((r) => !status || r.status === status);
  const allSelected = matches.length > 0 && matches.every((r) => selectedReportIds.has(r.id));
  $('#reports-body').innerHTML = matches.map((r) => `<tr class="clickable" data-report="${esc(r.id)}"><td><input class="report-select" type="checkbox" data-report-select="${esc(r.id)}" aria-label="Select report" ${selectedReportIds.has(r.id) ? 'checked' : ''}></td><td><b>${esc(r.area.replaceAll('_', ' '))}</b><small>${esc(r.description.slice(0, 90))}${r.description.length > 90 ? '…' : ''}</small></td><td>${esc(r.reporter_email || users.find((u) => u.id === r.user_id)?.email || 'Guest')}<small>${esc(r.app_version || 'App version unknown')} · ${esc(r.platform || r.device_info || 'Device not provided')}</small></td><td>${esc(shortDate(r.created_at))}</td><td>${badge(r.status)}</td></tr>`).join('') || '<tr><td colspan="5" class="empty">No reports found.</td></tr>';
  $('#select-all-reports').checked = allSelected;
  $('#delete-selected-reports').disabled = selectedReportIds.size === 0;
  $('#delete-selected-reports').textContent = `Delete selected (${selectedReportIds.size})`;
}

async function deleteProblemReports(reportIds, { all = false, confirmMessage } = {}) {
  if (!window.confirm(confirmMessage)) return false;
  const { data, error } = await client.rpc('admin_delete_problem_reports', {
    p_report_ids: all ? null : reportIds,
  });
  if (error) { notice(error.message, true); return false; }
  selectedReportIds.clear();
  await refreshData();
  const count = Number(data) || 0;
  notice(`Deleted ${count} report${count === 1 ? '' : 's'}.`);
  return true;
}

function openReport(id) {
  const report = reports.find((item) => item.id === id); if (!report) return;
  const reporter = users.find((item) => item.id === report.user_id);
  const context = JSON.stringify(report.context ?? {}, null, 2);
  $('#report-detail').innerHTML = `<h2>${esc(report.area.replaceAll('_', ' '))}</h2><p class="muted">${esc(reporter?.email ?? report.reporter_email ?? 'Guest')} · ${esc(date(report.created_at))}</p><div class="kv"><span>App version</span><b>${esc(report.app_version || 'Unknown')}</b></div><div class="kv"><span>Device</span><b>${esc(report.platform || report.device_info || 'Not provided')}</b></div><p>${esc(report.description)}</p><details><summary>Technical context</summary><pre>${esc(context)}</pre></details><label class="appearance-label">Status<select id="detail-status"><option value="new">New</option><option value="seen">Seen</option><option value="in_progress">In progress</option><option value="resolved">Resolved</option></select></label><label class="appearance-label">Admin notes<textarea id="detail-notes" rows="4" maxlength="8000" placeholder="Internal notes for the admin team">${esc(report.admin_note)}</textarea></label><div class="detail-actions"><button id="save-report" class="button primary">Save report</button><button id="delete-report" class="button danger">Delete report</button><button class="button" onclick="document.querySelector('#report-dialog').close()">Close</button></div>`;
  $('#detail-status').value = report.status;
  $('#report-dialog').showModal();
  $('#save-report').addEventListener('click', async () => {
    const { error } = await client.from('problem_reports').update({
      status: $('#detail-status').value,
      admin_note: $('#detail-notes').value,
    }).eq('id', report.id);
    if (error) { notice(error.message, true); return; }
    $('#report-dialog').close(); await refreshData();
  });
  $('#delete-report').addEventListener('click', async () => {
    const title = report.area.replaceAll('_', ' ');
    const deleted = await deleteProblemReports([report.id], {
      confirmMessage: `Delete this ${title} report permanently? This action will be recorded in the audit log.`,
    });
    if (deleted) $('#report-dialog').close();
  });
}

function drawTeam() {
  $('#team-body').innerHTML = admins.map((admin) => {
    const user = users.find((item) => item.id === admin.user_id);
    return `<tr><td>${esc(user?.email ?? 'Account unavailable')}</td><td>${esc(user?.display_name ?? '—')}</td><td>${badge(admin.role)}</td><td>${esc(shortDate(admin.created_at))}</td></tr>`;
  }).join('') || '<tr><td colspan="4" class="empty">No admins found.</td></tr>';
}

function drawAudit() {
  $('#audit-body').innerHTML = auditEntries.map((entry) => {
    const user = users.find((item) => item.id === entry.actor_id);
    return `<tr><td><b>${esc(entry.action)}</b></td><td>${esc(user?.email ?? 'System / removed account')}</td><td>${esc(entry.target_type)} ${esc(entry.target_id)}</td><td>${esc(JSON.stringify(entry.details ?? {}))}</td><td>${esc(date(entry.created_at))}</td></tr>`;
  }).join('') || '<tr><td colspan="5" class="empty">No audit entries yet.</td></tr>';
}

function drawAnnouncements() {
  $('#announcement-history').innerHTML = announcements.map((item) => `<div class="row"><div><b>${esc(item.title)}</b><small>${esc(item.kind)} · ${item.is_active ? 'Active' : 'Inactive'} · Starts ${esc(date(item.starts_at))} · Ends ${esc(date(item.ends_at))}</small><small>${esc(item.body)}</small></div><div class="announcement-actions"><button class="button" data-edit-announcement="${esc(item.id)}">Edit</button><button class="button danger" data-delete-announcement="${esc(item.id)}">Delete</button></div></div>`).join('') || '<p class="empty">No announcements yet.</p>';
}

function announcementDateInput(value) {
  if (!value) return '';
  const parsed = new Date(value);
  const local = new Date(parsed.getTime() - parsed.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

function resetAnnouncementForm() {
  editingAnnouncementId = null;
  $('#announcement-form').reset();
  $('#announcement-form-title').textContent = 'New announcement';
  $('#announcement-submit').textContent = 'Publish';
  $('#announcement-cancel').hidden = true;
  $('#announcement-active').checked = true;
  $('#announcement-starts').value = announcementDateInput(new Date().toISOString());
}

function editAnnouncement(id) {
  const item = announcements.find((announcement) => announcement.id === id);
  if (!item) return;
  editingAnnouncementId = item.id;
  $('#announcement-form-title').textContent = 'Edit announcement';
  $('#announcement-submit').textContent = 'Save changes';
  $('#announcement-cancel').hidden = false;
  $('#announcement-title').value = item.title;
  $('#announcement-message').value = item.body;
  $('#announcement-kind').value = item.kind;
  $('#announcement-starts').value = announcementDateInput(item.starts_at);
  $('#announcement-ends').value = announcementDateInput(item.ends_at);
  $('#announcement-active').checked = item.is_active;
  $('#announcement-link-url').value = item.link_url ?? '';
  $('#announcement-link-label').value = item.link_label ?? '';
  $('#announcement-form-title').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function drawAppControl() {
  if (!appSettings) return;
  $('#maintenance-enabled').checked = appSettings.maintenance_enabled;
  $('#latest-version').value = appSettings.latest_version;
  $('#minimum-version').value = appSettings.minimum_supported_version;
  const flags = appSettings.feature_flags ?? {};
  $('#feature-switches').innerHTML = featureDefinitions.map(([key, title, description]) => `<div class="control-row"><div><b>${esc(title)}</b><small>${esc(description)}</small></div><label class="switch"><input type="checkbox" data-feature="${esc(key)}" ${flags[key] !== false ? 'checked' : ''}><span></span></label></div>`).join('');
}

async function saveAppSettings(changes, auditLabel) {
  const { error } = await client.rpc('admin_update_app_settings', {
    p_maintenance_enabled: changes.maintenance_enabled ?? appSettings.maintenance_enabled,
    p_latest_version: changes.latest_version ?? appSettings.latest_version,
    p_minimum_supported_version: changes.minimum_supported_version ?? appSettings.minimum_supported_version,
    p_feature_flags: changes.feature_flags ?? appSettings.feature_flags,
  });
  if (error) { notice(error.message, true); return false; }
  await refreshData();
  notice(auditLabel);
  return true;
}

function showPage(page) {
  if (page === 'team' && role !== 'owner') page = 'dashboard';
  currentPage = page;
  $$('.page').forEach((node) => { node.hidden = node.id !== `page-${page}`; });
  $$('.nav').forEach((node) => node.classList.toggle('active', node.dataset.page === page));
  $('#page-title').textContent = ({ dashboard: 'Dashboard', users: 'Users', reports: 'Bug reports', announcements: 'Announcements', 'app-control': 'App control', team: 'Admin team', audit: 'Audit log' })[page];
}

function initTheme() {
  const saved = localStorage.getItem('c2f-admin-theme') || 'system';
  setTheme(saved);
  $('#appearance').addEventListener('change', () => setTheme($('#appearance').value));
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if ((localStorage.getItem('c2f-admin-theme') || 'system') === 'system') setTheme('system');
  });
}

async function init() {
  initTheme();
  if (!supabaseConfig?.url || supabaseConfig.url.includes('YOUR_PROJECT') || !supabaseConfig.anonKey || supabaseConfig.anonKey.includes('YOUR_SUPABASE')) {
    showLogin('Set up docs/admin/config.js from config.example.js with the new project URL and anon key.');
    $('#login-form').querySelectorAll('input,button').forEach((node) => { node.disabled = true; });
    return;
  }
  client = createClient(supabaseConfig.url, supabaseConfig.anonKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } });
  $('#login-form').addEventListener('submit', async (event) => {
    event.preventDefault(); $('#login-error').textContent = '';
    const { error } = await client.auth.signInWithPassword({ email: $('#email').value.trim(), password: $('#password').value });
    if (error) { $('#login-error').textContent = error.message; return; }
    try { await loadActor(); } catch (e) { await client.auth.signOut(); showLogin(e.message); }
  });
  $('#signout').addEventListener('click', async () => { await client.auth.signOut(); actor = account = null; role = null; showLogin(); });
  $('#refresh').addEventListener('click', refreshData);
  $$('.nav').forEach((node) => node.addEventListener('click', () => showPage(node.dataset.page)));
  $('#user-search').addEventListener('input', drawUsers);
  $('#user-status').addEventListener('change', drawUsers);
  $('#report-status').addEventListener('change', drawReports);
  $('#reports-body').addEventListener('change', (event) => {
    const checkbox = event.target.closest('[data-report-select]');
    if (!checkbox) return;
    if (checkbox.checked) selectedReportIds.add(checkbox.dataset.reportSelect);
    else selectedReportIds.delete(checkbox.dataset.reportSelect);
    drawReports();
  });
  $('#select-all-reports').addEventListener('change', (event) => {
    const status = $('#report-status').value;
    reports.filter((r) => !status || r.status === status).forEach((r) => {
      if (event.target.checked) selectedReportIds.add(r.id);
      else selectedReportIds.delete(r.id);
    });
    drawReports();
  });
  $('#delete-selected-reports').addEventListener('click', () => {
    const ids = [...selectedReportIds];
    if (ids.length) deleteProblemReports(ids, {
      confirmMessage: `Permanently delete ${ids.length} selected report${ids.length === 1 ? '' : 's'}? Each deletion will be recorded in the audit log.`,
    });
  });
  $('#delete-all-reports').addEventListener('click', () => deleteProblemReports([], {
    all: true,
    confirmMessage: 'Permanently delete all reports? Each deletion will be recorded in the audit log.',
  }));
  resetAnnouncementForm();
  $('#announcement-cancel').addEventListener('click', resetAnnouncementForm);
  $('#announcement-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const linkUrl = $('#announcement-link-url').value.trim();
    if (linkUrl && new URL(linkUrl).protocol !== 'https:') {
      notice('Announcement links must use https.', true); return;
    }
    const values = {
      title: $('#announcement-title').value.trim(),
      body: $('#announcement-message').value.trim(),
      kind: $('#announcement-kind').value,
      starts_at: new Date($('#announcement-starts').value).toISOString(),
      ends_at: $('#announcement-ends').value ? new Date($('#announcement-ends').value).toISOString() : null,
      is_active: $('#announcement-active').checked,
      link_url: linkUrl || null,
      link_label: $('#announcement-link-label').value.trim() || null,
      updated_at: new Date().toISOString(),
    };
    const result = editingAnnouncementId
      ? await client.from('announcements').update(values).eq('id', editingAnnouncementId)
      : await client.from('announcements').insert(values);
    if (result.error) { notice(result.error.message, true); return; }
    resetAnnouncementForm(); await refreshData();
    showPage('announcements'); notice('Announcement saved.');
  });
  $('#announcement-history').addEventListener('click', async (event) => {
    const editButton = event.target.closest('[data-edit-announcement]');
    if (editButton) { editAnnouncement(editButton.dataset.editAnnouncement); return; }
    const deleteButton = event.target.closest('[data-delete-announcement]');
    if (!deleteButton) return;
    const item = announcements.find((announcement) => announcement.id === deleteButton.dataset.deleteAnnouncement);
    if (!item || !window.confirm(`Delete “${item.title}”?`)) return;
    const { error } = await client.from('announcements').delete().eq('id', item.id);
    if (error) { notice(error.message, true); return; }
    await refreshData(); showPage('announcements'); notice('Announcement deleted.');
  });
  $('#maintenance-enabled').addEventListener('change', async () => {
    await saveAppSettings({ maintenance_enabled: $('#maintenance-enabled').checked }, 'Maintenance setting saved.');
  });
  $('#app-settings-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    await saveAppSettings({ latest_version: $('#latest-version').value.trim(), minimum_supported_version: $('#minimum-version').value.trim() }, 'Version settings saved.');
    showPage('app-control');
  });
  $('#feature-switches').addEventListener('change', async (event) => {
    const input = event.target.closest('[data-feature]'); if (!input) return;
    const featureFlags = { ...(appSettings.feature_flags ?? {}), [input.dataset.feature]: input.checked };
    await saveAppSettings({ feature_flags: featureFlags }, 'Feature setting saved.');
    showPage('app-control');
  });
  $('#users-body').addEventListener('click', (e) => { const row = e.target.closest('[data-user]'); if (row) openUser(row.dataset.user); });
  $('#reports-body').addEventListener('click', (e) => { if (e.target.closest('[data-report-select]')) return; const row = e.target.closest('[data-report]'); if (row) openReport(row.dataset.report); });
  $('#team-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = $('#team-email').value.trim().toLowerCase();
    const user = users.find((item) => item.email.toLowerCase() === email);
    if (!user) { notice('That account is not in this project yet. Ask the person to sign up first.', true); return; }
    const { error } = await client.rpc('owner_set_admin_role', { p_user_id: user.id, p_role: $('#team-role').value });
    if (error) { notice(error.message, true); return; }
    $('#team-email').value = ''; await refreshData();
  });

  client.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT' || !session) { actor = account = null; role = null; showLogin(); }
  });
  const { data: { session } } = await client.auth.getSession();
  if (!session) { showLogin(); return; }
  try { await loadActor(); } catch (error) { await client.auth.signOut(); showLogin(error.message); }
}

init().catch((error) => showLogin(`Portal initialization failed: ${error.message}`));
