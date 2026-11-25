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
let auditPage = 1;
const auditPageSize = 20;
let announcements = [];
let editingAnnouncementId = null;
let appSettings = null;
let appInfoContent = null;
let currentPage = 'dashboard';
let appInfoActiveTab = 'sections';
let appInfoOpenSectionIndex = null;
let appInfoOpenReleaseIndex = null;
let appInfoReleasePage = 1;
const APP_INFO_RELEASES_PER_PAGE = 6;
const appInfoMobileQuery = window.matchMedia('(max-width: 700px)');
let appInfoSheetItem = null;
let appInfoSheetCloseTimer = null;
let reportRealtimeChannel = null;
let reportRefreshTimer = null;
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
  if ($('#mobile-appearance')) $('#mobile-appearance').value = choice;
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
  subscribeToProblemReports();
  return true;
}

async function queryRows(table, fields, orderField = 'created_at') {
  const { data, error } = await client.from(table).select(fields).order(orderField, { ascending: false }).limit(500);
  if (error) throw error;
  return data ?? [];
}

async function queryProblemReports() {
  return queryRows('problem_reports', 'id,user_id,reporter_email,area,description,app_version,platform,device_info,context,source_file_path,output_file_path,screenshot_file_path,status,admin_note,admin_reply,created_at');
}

function stopProblemReportSubscription() {
  if (reportRefreshTimer) window.clearTimeout(reportRefreshTimer);
  reportRefreshTimer = null;
  if (reportRealtimeChannel) client?.removeChannel(reportRealtimeChannel);
  reportRealtimeChannel = null;
}

function subscribeToProblemReports() {
  if (!actor || reportRealtimeChannel) return;
  reportRealtimeChannel = client.channel('admin-problem-report-updates')
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'problem_reports',
    }, () => {
      window.clearTimeout(reportRefreshTimer);
      reportRefreshTimer = window.setTimeout(() => refreshProblemReports(), 250);
    })
    .subscribe((status) => {
      if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        notice('Live report updates are unavailable. Use Refresh to check for new reports.', true);
      }
    });
}

async function refreshProblemReports() {
  if (!actor) return;
  try {
    reports = await queryProblemReports();
    drawReports();
    drawDashboard();
  } catch (error) {
    notice(`Could not update reports: ${error.message}`, true);
  }
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
      queryProblemReports(),
      queryRows('admin_audit_log', 'id,actor_id,action,target_type,target_id,details,created_at'),
    ]);
    [announcements, appSettings, appInfoContent] = await Promise.all([
      queryRows('announcements', 'id,title,body,kind,starts_at,ends_at,is_active,link_url,link_label,hide_after_version,created_at,updated_at'),
      (async () => {
        const { data, error } = await client.from('app_control_settings').select('*').eq('id', true).single();
        if (error) throw error;
        return data;
      })(),
      (async () => {
        const { data, error } = await client.from('app_info_content').select('sections,release_notes,updated_at').eq('id', true).maybeSingle();
        if (error) return null;
        return data;
      })(),
    ]);
    admins = role === 'owner'
      ? await queryRows('admin_users', 'user_id,role,created_by,created_at')
      : [];
    drawDashboard(); drawUsers(); drawReports(); drawTeam(); populateAuditFilters(); drawAudit(); drawAnnouncements(); drawAppControl(); drawAppInfo();
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
  $$('#user-status-pills [data-status]').forEach((button) => button.classList.toggle('active', button.dataset.status === status));
  const matches = users.filter((u) => (!status || u.account_status === status) &&
    `${u.display_name} ${u.email}`.toLowerCase().includes(q));
  $('#users-body').innerHTML = matches.map((u) => `<tr class="clickable" data-user="${esc(u.id)}"><td><b>${esc(u.display_name || 'Unnamed account')}</b></td><td>${esc(u.email)}</td><td>${badge(u.account_status)}</td><td>${esc(shortDate(u.created_at))}</td><td>${esc(date(u.last_seen_at))}</td></tr>`).join('') || '<tr><td colspan="5" class="empty">No accounts found.</td></tr>';
  $('#users-cards').innerHTML = matches.map((u) => `<button type="button" class="mobile-data-card" data-user="${esc(u.id)}"><span class="mobile-card-main"><b>${esc(u.display_name || 'Unnamed account')}</b><span class="mobile-card-chevron" aria-hidden="true">›</span></span><span class="mobile-card-sub">${esc(u.email)}</span><span class="mobile-card-meta">${badge(u.account_status)} <span>Joined ${esc(shortDate(u.created_at))}</span></span></button>`).join('') || '<p class="empty mobile-empty">No accounts found.</p>';
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
  const newReportCount = reports.filter((report) => report.status === 'new').length;
  for (const selector of ['#reports-badge-sidebar', '#reports-badge-mobile']) {
    const badgeNode = $(selector);
    badgeNode.hidden = newReportCount === 0;
    badgeNode.classList.toggle('dot', newReportCount === 1);
    badgeNode.textContent = newReportCount === 1 ? '' : newReportCount > 99 ? '99+' : String(newReportCount);
    badgeNode.setAttribute('aria-label', `${newReportCount} new report${newReportCount === 1 ? '' : 's'}`);
  }
  const status = $('#report-status').value;
  $$('#report-status-pills [data-status]').forEach((button) => button.classList.toggle('active', button.dataset.status === status));
  const matches = reports.filter((r) => !status || r.status === status);
  const allSelected = matches.length > 0 && matches.every((r) => selectedReportIds.has(r.id));
  $('#reports-body').innerHTML = matches.map((r) => `<tr class="clickable" data-report="${esc(r.id)}"><td><input class="report-select" type="checkbox" data-report-select="${esc(r.id)}" aria-label="Select report" ${selectedReportIds.has(r.id) ? 'checked' : ''}></td><td><b>${esc(r.area.replaceAll('_', ' '))}</b><small>${esc(r.description.slice(0, 90))}${r.description.length > 90 ? '…' : ''}</small></td><td>${esc(r.reporter_email || users.find((u) => u.id === r.user_id)?.email || 'Guest')}<small>${esc(r.app_version || 'App version unknown')} · ${esc(r.platform || r.device_info || 'Device not provided')}</small></td><td>${esc(shortDate(r.created_at))}</td><td>${badge(r.status)}</td></tr>`).join('') || '<tr><td colspan="5" class="empty">No reports found.</td></tr>';
  $('#reports-cards').innerHTML = matches.map((r) => `<article class="mobile-data-card report-card" data-report-card="${esc(r.id)}"><label class="report-card-check"><input class="report-select" type="checkbox" data-report-select="${esc(r.id)}" aria-label="Select report" ${selectedReportIds.has(r.id) ? 'checked' : ''}></label><button class="report-card-open" type="button" data-report="${esc(r.id)}"><span class="mobile-card-main"><b>${esc(r.area.replaceAll('_', ' '))}</b>${badge(r.status)}</span><span class="mobile-card-sub">${esc(r.description.slice(0, 120))}${r.description.length > 120 ? '…' : ''}</span><span class="mobile-card-sub">${esc(r.reporter_email || users.find((u) => u.id === r.user_id)?.email || 'Guest')}</span><span class="mobile-card-meta">${esc(r.app_version || 'App version unknown')} · ${esc(shortDate(r.created_at))}</span><span class="mobile-card-chevron" aria-hidden="true">Open report ›</span></button></article>`).join('') || '<p class="empty mobile-empty">No reports found.</p>';
  $('#select-all-reports').checked = allSelected;
  $('#delete-selected-reports').disabled = selectedReportIds.size === 0;
  $('#delete-selected-reports').textContent = `Delete selected (${selectedReportIds.size})`;
  $('#mobile-selected-count').textContent = `${selectedReportIds.size} selected`;
  $('#mobile-bulk-actions').hidden = selectedReportIds.size === 0 || currentPage !== 'reports';
}

async function deleteProblemReports(reportIds, { all = false, confirmMessage } = {}) {
  if (!window.confirm(confirmMessage)) return false;
  try {
    await deleteReportAttachments(reportIds, all);
  } catch (error) {
    notice(`Could not delete report attachments. Apply the report attachment cleanup migration, then retry. ${error.message}`, true);
    return false;
  }
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

async function deleteReportAttachments(reportIds, all) {
  const fields = 'source_file_path,output_file_path,screenshot_file_path';
  const paths = new Set();
  const addPaths = (rows) => {
    for (const row of rows ?? []) {
      for (const value of [row.source_file_path, row.output_file_path, row.screenshot_file_path]) {
        if (typeof value === 'string' && value.trim()) paths.add(value);
      }
    }
  };

  if (all) {
    const pageSize = 500;
    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await client.from('problem_reports')
        .select(fields).order('created_at', { ascending: true })
        .range(offset, offset + pageSize - 1);
      if (error) throw error;
      addPaths(data);
      if (!data || data.length < pageSize) break;
    }
  } else if (reportIds.length) {
    const { data, error } = await client.from('problem_reports')
      .select(fields).in('id', reportIds);
    if (error) throw error;
    addPaths(data);
  }

  const attachments = [...paths];
  for (let offset = 0; offset < attachments.length; offset += 100) {
    const { error } = await client.storage.from('report-files')
      .remove(attachments.slice(offset, offset + 100));
    if (error) throw error;
  }
}

async function openReport(id) {
  const report = reports.find((item) => item.id === id); if (!report) return;
  const reporter = users.find((item) => item.id === report.user_id);
  const context = JSON.stringify(report.context ?? {}, null, 2);
  let screenshotLink = '';
  if (report.screenshot_file_path) {
    try {
      const { data, error } = await client.storage.from('report-files')
        .createSignedUrl(report.screenshot_file_path, 3600);
      if (!error && data?.signedUrl) {
        screenshotLink = `<p><a href="${esc(data.signedUrl)}" target="_blank" rel="noopener">View attached screenshot</a></p>`;
      }
    } catch (_) {}
  }
  const replyHelp = report.user_id
    ? '<small class="muted">This reply appears only in this reporter’s in-app Announcements.</small>'
    : '<small class="muted">This guest report has no account recipient, so a private in-app reply cannot be sent.</small>';
  $('#report-detail').innerHTML = `<div class="report-dialog-scroll"><h2>${esc(report.area.replaceAll('_', ' '))}</h2><p class="muted">${esc(reporter?.email ?? report.reporter_email ?? 'Guest')} · ${esc(date(report.created_at))}</p><div class="kv"><span>App version</span><b>${esc(report.app_version || 'Unknown')}</b></div><div class="kv"><span>Device</span><b>${esc(report.platform || report.device_info || 'Not provided')}</b></div><p>${esc(report.description)}</p>${screenshotLink}<details><summary>Technical context</summary><pre>${esc(context)}</pre></details><label class="appearance-label">Status<select id="detail-status"><option value="new">New</option><option value="seen">Seen</option><option value="in_progress">In progress</option><option value="resolved">Resolved</option></select></label><label class="appearance-label">Admin notes<textarea id="detail-notes" rows="4" maxlength="8000" placeholder="Internal notes for the admin team">${esc(report.admin_note)}</textarea></label><label class="appearance-label">Reply to user<textarea id="detail-reply" rows="4" maxlength="8000" placeholder="Write a private reply for the reporter" ${report.user_id ? '' : 'disabled'}>${esc(report.admin_reply)}</textarea>${replyHelp}<small id="report-reply-status" class="muted" role="status" hidden></small></label></div><p id="report-save-error" class="error" role="alert" hidden></p><div class="detail-actions"><button id="send-report-reply" class="button primary" type="button" ${report.user_id && String(report.admin_reply ?? '').trim() ? '' : 'disabled'}>Send reply</button><button id="save-report" class="button" type="button">Save report</button><button id="delete-report" class="button danger" type="button">Delete report</button><button id="close-report" class="button" type="button">Close</button></div>`;
  $('#detail-status').value = report.status;
  $('#report-dialog').showModal();
  $('#close-report').addEventListener('click', () => $('#report-dialog').close());
  $('#detail-reply').addEventListener('input', () => {
    $('#send-report-reply').disabled = !report.user_id || !$('#detail-reply').value.trim();
    const statusNode = $('#report-reply-status');
    statusNode.textContent = 'Reply not sent yet.';
    statusNode.hidden = !$('#detail-reply').value.trim();
  });
  $('#send-report-reply').addEventListener('click', async () => {
    const reply = $('#detail-reply').value.trim();
    if (!report.user_id || !reply) return;
    const button = $('#send-report-reply');
    button.disabled = true;
    button.textContent = 'Sending…';
    const { error } = await client.rpc('admin_send_problem_report_reply', {
      p_report_id: report.id,
      p_admin_reply: reply,
    });
    if (error) {
      const errorNode = $('#report-save-error');
      errorNode.textContent = error.message;
      errorNode.hidden = false;
      button.disabled = false;
      button.textContent = 'Send reply';
      return;
    }
    report.admin_reply = reply;
    const statusNode = $('#report-reply-status');
    statusNode.textContent = 'Reply sent to this user’s Announcements.';
    statusNode.hidden = false;
    button.textContent = 'Reply sent';
  });
  $('#save-report').addEventListener('click', async () => {
    const { error } = await client.rpc('admin_save_problem_report', {
      p_report_id: report.id,
      p_status: $('#detail-status').value,
      p_admin_note: $('#detail-notes').value,
      p_admin_reply: report.admin_reply ?? '',
    });
    if (error) {
      const errorNode = $('#report-save-error');
      errorNode.textContent = error.message;
      errorNode.hidden = false;
      return;
    }
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
  $('#team-cards').innerHTML = admins.map((admin) => {
    const user = users.find((item) => item.id === admin.user_id);
    return `<article class="mobile-data-card"><span class="mobile-card-main"><b>${esc(user?.display_name ?? 'Account unavailable')}</b>${badge(admin.role)}</span><span class="mobile-card-sub">${esc(user?.email ?? 'Account unavailable')}</span><span class="mobile-card-meta">Added ${esc(shortDate(admin.created_at))}</span></article>`;
  }).join('') || '<p class="empty mobile-empty">No admins found.</p>';
}

function drawAudit() {
  const query = $('#audit-search').value.trim().toLowerCase();
  const action = $('#audit-action-filter').value;
  const targetType = $('#audit-target-filter').value;
  const actorId = $('#audit-actor-filter').value;
  const fromValue = $('#audit-date-from').value;
  const toValue = $('#audit-date-to').value;
  const from = fromValue ? new Date(`${fromValue}T00:00:00`) : null;
  const to = toValue ? new Date(`${toValue}T23:59:59.999`) : null;
  const matches = auditEntries.filter((entry) => {
    const user = users.find((item) => item.id === entry.actor_id);
    const searchable = `${entry.action} ${user?.email ?? 'System / removed account'} ${entry.target_type} ${entry.target_id} ${JSON.stringify(entry.details ?? {})}`.toLowerCase();
    const createdAt = new Date(entry.created_at);
    return (!query || searchable.includes(query)) && (!action || entry.action === action) &&
      (!targetType || entry.target_type === targetType) && (!actorId || (actorId === 'system' ? !entry.actor_id : entry.actor_id === actorId)) &&
      (!from || createdAt >= from) && (!to || createdAt <= to);
  });
  const pageCount = Math.max(1, Math.ceil(matches.length / auditPageSize));
  auditPage = Math.min(auditPage, pageCount);
  const startIndex = (auditPage - 1) * auditPageSize;
  const pageEntries = matches.slice(startIndex, startIndex + auditPageSize);
  $('#audit-body').innerHTML = pageEntries.map((entry) => {
    const user = users.find((item) => item.id === entry.actor_id);
    return `<tr><td><b>${esc(entry.action)}</b></td><td>${esc(user?.email ?? 'System / removed account')}</td><td>${esc(entry.target_type)} ${esc(entry.target_id)}</td><td>${esc(JSON.stringify(entry.details ?? {}))}</td><td>${esc(date(entry.created_at))}</td></tr>`;
  }).join('') || `<tr><td colspan="5" class="empty">${auditEntries.length ? 'No matching audit entries.' : 'No audit entries yet.'}</td></tr>`;
  $('#audit-cards').innerHTML = pageEntries.map((entry) => {
    const user = users.find((item) => item.id === entry.actor_id);
    const details = JSON.stringify(entry.details ?? {});
    return `<article class="mobile-data-card"><span class="mobile-card-main"><b>${esc(entry.action)}</b></span><span class="mobile-card-sub">by ${esc(user?.email ?? 'System / removed account')}</span><span class="mobile-card-sub">${esc(entry.target_type)} ${esc(entry.target_id)}</span><span class="mobile-card-meta">${esc(date(entry.created_at))}</span><details class="audit-card-details"><summary>Details</summary><pre>${esc(details)}</pre></details></article>`;
  }).join('') || `<p class="empty mobile-empty">${auditEntries.length ? 'No matching audit entries.' : 'No audit entries yet.'}</p>`;
  $('#audit-page-info').textContent = `Page ${auditPage} of ${pageCount}`;
  $('#audit-range-info').textContent = matches.length
    ? `Showing ${startIndex + 1}–${Math.min(startIndex + auditPageSize, matches.length)} of ${matches.length}`
    : 'Showing 0 of 0';
  $('#audit-prev').disabled = auditPage <= 1;
  $('#audit-next').disabled = auditPage >= pageCount;
  $('#audit-pagination').hidden = matches.length <= auditPageSize;
  $('#audit-loaded-note').textContent = auditEntries.length >= 500
    ? 'Showing the newest 500 audit entries. Use the date filter to narrow this list.'
    : `Showing all ${auditEntries.length} loaded audit entries.`;
  drawActiveAuditFilters();
}

function drawActiveAuditFilters() {
  const filters = [
    ['#audit-action-filter', 'Action'], ['#audit-target-filter', 'Target'], ['#audit-actor-filter', 'Actor'],
  ];
  const chips = filters.flatMap(([selector, label]) => {
    const select = $(selector);
    return select.value ? [{ selector, label, value: select.selectedOptions[0]?.textContent ?? select.value }] : [];
  });
  if ($('#audit-date-from').value) chips.push({ selector: '#audit-date-from', label: 'From', value: $('#audit-date-from').value });
  if ($('#audit-date-to').value) chips.push({ selector: '#audit-date-to', label: 'To', value: $('#audit-date-to').value });
  $('#active-audit-filters').innerHTML = chips.map((chip) => `<button type="button" class="active-filter-chip" data-clear-filter="${chip.selector}">${esc(chip.label)}: ${esc(chip.value)} <span aria-hidden="true">×</span></button>`).join('');
}

function populateAuditFilters() {
  const setOptions = (selector, values, placeholder) => {
    const select = $(selector);
    const selected = select.value;
    const options = [...new Set(values.filter(Boolean))].sort((a, b) => a.localeCompare(b));
    select.innerHTML = `<option value="">${placeholder}</option>${options.map((value) => `<option value="${esc(value)}">${esc(value)}</option>`).join('')}`;
    if (options.includes(selected)) select.value = selected;
  };
  setOptions('#audit-action-filter', auditEntries.map((entry) => entry.action), 'All actions');
  setOptions('#audit-target-filter', auditEntries.map((entry) => entry.target_type), 'All target types');
  const actorSelect = $('#audit-actor-filter');
  const selectedActor = actorSelect.value;
  const actors = [...new Map(auditEntries.map((entry) => {
    const user = users.find((item) => item.id === entry.actor_id);
    return [entry.actor_id || 'system', { id: entry.actor_id || 'system', label: user?.email ?? (entry.actor_id ? 'Removed account' : 'System / removed account') }];
  })).values()].sort((a, b) => a.label.localeCompare(b.label));
  actorSelect.innerHTML = `<option value="">All actors</option>${actors.map((item) => `<option value="${esc(item.id)}">${esc(item.label)}</option>`).join('')}`;
  if (actors.some((item) => item.id === selectedActor)) actorSelect.value = selectedActor;
}

function drawAnnouncements() {
  $('#announcement-history').innerHTML = announcements.map((item) => `<div class="row"><div><b>${esc(item.title)}</b><small>${esc(item.kind)} · ${item.is_active ? 'Active' : 'Inactive'} · Starts ${esc(date(item.starts_at))} · Ends ${esc(date(item.ends_at))}</small>${item.hide_after_version ? `<small>Hidden at app version ${esc(item.hide_after_version)} and newer</small>` : ''}<small>${esc(item.body)}</small></div><div class="announcement-actions"><button class="button" data-edit-announcement="${esc(item.id)}">Edit</button><button class="button danger" data-delete-announcement="${esc(item.id)}">Delete</button></div></div>`).join('') || '<p class="empty">No announcements yet.</p>';
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
  $('#announcement-hide-after-version').value = item.hide_after_version ?? '';
  $('#announcement-form-title').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function drawAppControl() {
  if (!appSettings) return;
  $('#maintenance-enabled').checked = appSettings.maintenance_enabled;
  $('#latest-version').value = appSettings.latest_version;
  $('#minimum-version').value = appSettings.minimum_supported_version;
  $('#apk-download-url').value = appSettings.apk_download_url ?? '';
  const flags = appSettings.feature_flags ?? {};
  $('#feature-switches').innerHTML = featureDefinitions.map(([key, title, description]) => `<div class="control-row"><div><b>${esc(title)}</b><small>${esc(description)}</small></div><label class="switch"><input type="checkbox" data-feature="${esc(key)}" ${flags[key] !== false ? 'checked' : ''}><span></span></label></div>`).join('');
}

function drawAppInfo() {
  const unavailable = !appInfoContent;
  $('#app-info-unavailable').hidden = !unavailable;
  $('#save-app-info').disabled = unavailable;
  $('#add-info-section').disabled = unavailable;
  $('#add-info-release').disabled = unavailable;
  $('#app-info-sections-count').textContent = unavailable ? '0' : String(appInfoContent.sections.length);
  $('#app-info-history-count').textContent = unavailable ? '0' : String(appInfoContent.release_notes.length);
  setAppInfoTab(appInfoActiveTab, false);
  if (unavailable) {
    $('#app-info-sections').innerHTML = '';
    $('#app-info-releases').innerHTML = '';
    $('#app-info-releases-empty').hidden = true;
    return;
  }
  $('#app-info-sections').innerHTML = appInfoContent.sections.map((section, index) => `
    <article class="app-info-accordion info-editor info-editor-section${appInfoOpenSectionIndex === index ? ' is-open' : ''}" data-info-section="${index}">
      <button class="app-info-accordion-header" id="app-info-section-heading-${index}" type="button" data-app-info-toggle="sections" data-index="${index}" aria-expanded="${appInfoOpenSectionIndex === index}" aria-controls="app-info-section-panel-${index}"><span class="app-info-accordion-number">${index + 1}</span><span class="app-info-accordion-summary" data-section-summary>${esc(section.title || 'Untitled section')}</span><svg class="bi-icon app-info-chevron" viewBox="0 0 16 16" aria-hidden="true"><path fill-rule="evenodd" d="M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708"/></svg></button>
      <div class="app-info-accordion-panel" id="app-info-section-panel-${index}" role="region" aria-labelledby="app-info-section-heading-${index}" aria-hidden="${appInfoOpenSectionIndex !== index}" ${appInfoOpenSectionIndex === index ? '' : 'inert'}><div class="app-info-accordion-inner">${appInfoFieldsHTML('sections', section, index)}<div class="app-info-item-actions"><button class="button danger" type="button" data-remove-info-section="${index}">Remove section</button></div></div></div>
    </article>`).join('');
  $('#app-info-releases').innerHTML = appInfoContent.release_notes.map((release, index) => `
    <article class="app-info-accordion info-editor info-editor-release${appInfoOpenReleaseIndex === index ? ' is-open' : ''}" data-info-release="${index}">
      <button class="app-info-accordion-header" id="app-info-release-heading-${index}" type="button" data-app-info-toggle="history" data-index="${index}" aria-expanded="${appInfoOpenReleaseIndex === index}" aria-controls="app-info-release-panel-${index}"><span class="app-info-accordion-number">${index + 1}</span><span class="app-info-accordion-summary"><span data-release-summary-version>${esc(release.version || 'Untitled version')}</span><span class="app-info-accordion-meta" data-release-summary-date>${esc(release.date || 'Date not set')}</span></span><span class="app-info-latest-badge" data-release-summary-latest ${release.is_latest ? '' : 'hidden'}>Latest</span><i class="bi bi-chevron-down app-info-chevron" aria-hidden="true"></i></button>
      <div class="app-info-accordion-panel" id="app-info-release-panel-${index}" role="region" aria-labelledby="app-info-release-heading-${index}" aria-hidden="${appInfoOpenReleaseIndex !== index}" ${appInfoOpenReleaseIndex === index ? '' : 'inert'}><div class="app-info-accordion-inner">${appInfoFieldsHTML('history', release, index)}<div class="app-info-item-actions"><button class="button danger" type="button" data-remove-info-release="${index}">Remove update history</button></div></div></div>
    </article>`).join('');
  $('#app-info-releases-empty').hidden = appInfoContent.release_notes.length > 0;
  filterAppInfoReleases();
}

function appInfoFieldsHTML(kind, item, index, sheet = false) {
  const detailsText = (item.details ?? []).join('\n');
  if (kind === 'sections') return `<div class="app-info-fields${sheet ? ' app-info-sheet-fields' : ''}" data-app-info-form data-kind="sections" data-index="${index}">
    <label class="app-info-field-wide">Section title<input data-app-info-field="title" maxlength="80" value="${esc(item.title)}" required></label>
    <label class="app-info-field-wide">Details <small>Put each paragraph on its own line.</small><textarea data-app-info-field="details" rows="5" required>${esc(detailsText)}</textarea></label>
  </div>`;
  return `<div class="app-info-fields${sheet ? ' app-info-sheet-fields' : ''}" data-app-info-form data-kind="history" data-index="${index}">
    <div class="version-fields app-info-version-fields"><label>Version<input data-app-info-field="version" maxlength="32" value="${esc(item.version)}" required></label><label>Date or label<input data-app-info-field="date" maxlength="64" value="${esc(item.date)}" required></label></div>
    <label class="app-info-field-wide">Date and time picker <small>Choose a date and time to fill the Date or label field. You can still type a custom label there.</small><input data-app-info-field="date_time" type="datetime-local" value="${esc(appInfoDateTimeInput(item.date, item.date_time))}"></label>
    <label class="app-info-field-wide">Features <small>One item per line.</small><textarea data-app-info-field="features" rows="4">${esc((item.features ?? []).join('\n'))}</textarea></label>
    <label class="app-info-field-wide">Fixes and updates <small>One item per line.</small><textarea data-app-info-field="fixes" rows="4">${esc((item.fixes ?? []).join('\n'))}</textarea></label>
    <label class="info-current-version"><span><b>Mark as current version</b><small>This entry gets the latest badge in the app.</small></span><input data-app-info-field="is_latest" type="checkbox" ${item.is_latest ? 'checked' : ''}></label>
  </div>`;
}

function appInfoDateTimeInput(value, dateTime = '') {
  if (!dateTime && !value) return '';
  const parsed = new Date(dateTime || value);
  if (Number.isNaN(parsed.getTime())) return '';
  const local = new Date(parsed.getTime() - parsed.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

function appInfoDateTimeLabel(value) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return '';
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'long',
    timeStyle: 'short',
  }).format(parsed);
}

function updateAppInfoField(input) {
  const form = input.closest('[data-app-info-form]');
  if (!form || !appInfoContent) return;
  const kind = form.dataset.kind;
  const index = Number(form.dataset.index);
  const item = kind === 'sections' ? appInfoContent.sections[index] : appInfoContent.release_notes[index];
  if (!item) return;
  const field = input.dataset.appInfoField;
  if (field === 'is_latest') {
    if (input.checked) appInfoContent.release_notes.forEach((release) => { release.is_latest = false; });
    item.is_latest = input.checked;
    $$('[data-app-info-field="is_latest"]').forEach((checkbox) => {
      const checkboxForm = checkbox.closest('[data-app-info-form]');
      checkbox.checked = appInfoContent.release_notes[Number(checkboxForm.dataset.index)]?.is_latest === true;
    });
  } else if (field === 'date_time') {
    item.date = input.value ? appInfoDateTimeLabel(input.value) : '';
    item.date_time = input.value ? new Date(input.value).toISOString() : '';
    const dateLabel = form.querySelector('[data-app-info-field="date"]');
    if (dateLabel) dateLabel.value = item.date;
  } else if (['details', 'features', 'fixes'].includes(field)) {
    item[field] = input.value.split('\n');
  } else {
    item[field] = input.value;
    if (field === 'date') {
      const parsed = new Date(item.date);
      item.date_time = Number.isNaN(parsed.getTime()) ? '' : parsed.toISOString();
      const dateTime = form.querySelector('[data-app-info-field="date_time"]');
      if (dateTime) dateTime.value = appInfoDateTimeInput(item.date, item.date_time);
    }
  }
  updateAppInfoHeader(input, kind, item);
  if (kind === 'history') {
    if (field === 'is_latest') updateAppInfoLatestBadges();
    if (field === 'version' || field === 'date' || field === 'date_time') filterAppInfoReleases();
  }
}

function openAppInfoSheet(kind, index, focusField = null) {
  if (!appInfoMobileQuery.matches || !appInfoContent) return;
  const item = kind === 'sections' ? appInfoContent.sections[index] : appInfoContent.release_notes[index];
  if (!item) return;
  clearTimeout(appInfoSheetCloseTimer);
  appInfoSheetItem = { kind, index };
  const sheet = $('#app-info-sheet');
  $('#app-info-sheet-title').textContent = kind === 'sections' ? (item.title || 'New section') : (item.version || 'New update history');
  $('#app-info-sheet-back-label').textContent = kind === 'sections' ? 'Sections' : 'History';
  $('#app-info-sheet-body').innerHTML = appInfoFieldsHTML(kind, item, index, true);
  $('#app-info-sheet-remove').textContent = kind === 'sections' ? 'Remove section' : 'Remove update';
  sheet.hidden = false;
  sheet.inert = false;
  sheet.setAttribute('aria-hidden', 'false');
  document.body.classList.add('app-info-sheet-open');
  requestAnimationFrame(() => sheet.classList.add('is-open'));
  window.setTimeout(() => {
    const target = focusField
      ? $('#app-info-sheet-body').querySelector(`[data-app-info-field="${focusField}"]`)
      : $('#app-info-sheet-back');
    target?.focus({ preventScroll: true });
    $('#app-info-sheet-body').scrollTop = 0;
  }, 40);
}

function closeAppInfoSheet(returnFocus = true) {
  const sheet = $('#app-info-sheet');
  if (sheet.hidden) return;
  const previous = appInfoSheetItem;
  sheet.classList.remove('is-open');
  sheet.inert = true;
  sheet.setAttribute('aria-hidden', 'true');
  document.body.classList.remove('app-info-sheet-open');
  appInfoSheetItem = null;
  clearTimeout(appInfoSheetCloseTimer);
  appInfoSheetCloseTimer = window.setTimeout(() => { sheet.hidden = true; }, 260);
  if (returnFocus && previous) window.setTimeout(() => {
    document.querySelector(`[data-app-info-toggle="${previous.kind}"][data-index="${previous.index}"]`)?.focus();
  }, 0);
}

function removeAppInfoItem(kind, index) {
  if (!appInfoContent) return false;
  const items = kind === 'sections' ? appInfoContent.sections : appInfoContent.release_notes;
  if (!items[index]) return false;
  const label = kind === 'sections' ? `information section ${index + 1}` : `update history entry ${index + 1}`;
  if (!window.confirm(`Remove ${label}? Save App Info to publish this change.`)) return false;
  items.splice(index, 1);
  if (kind === 'sections') appInfoOpenSectionIndex = null;
  else appInfoOpenReleaseIndex = null;
  if (appInfoSheetItem?.kind === kind && appInfoSheetItem.index === index) closeAppInfoSheet(false);
  drawAppInfo();
  return true;
}

function setAppInfoTab(tab, remember = true, focus = false) {
  appInfoActiveTab = tab === 'history' ? 'history' : 'sections';
  const isHistory = appInfoActiveTab === 'history';
  const sectionTab = $('#app-info-tab-sections');
  const historyTab = $('#app-info-tab-history');
  sectionTab.setAttribute('aria-selected', String(!isHistory));
  historyTab.setAttribute('aria-selected', String(isHistory));
  sectionTab.tabIndex = isHistory ? -1 : 0;
  historyTab.tabIndex = isHistory ? 0 : -1;
  $('#app-info-panel-sections').hidden = isHistory;
  $('#app-info-panel-history').hidden = !isHistory;
  if (remember) {
    try { localStorage.setItem('c2f-admin-app-info-tab', appInfoActiveTab); } catch (_) {}
  }
  if (focus) (isHistory ? historyTab : sectionTab).focus();
}

function filterAppInfoReleases() {
  const query = $('#app-info-history-search').value.trim().toLocaleLowerCase();
  const matchingRows = [...$('#app-info-releases').querySelectorAll('[data-info-release]')].filter((row) => {
    const release = appInfoContent?.release_notes[Number(row.dataset.infoRelease)];
    return release && `${release.version} ${release.date}`.toLocaleLowerCase().includes(query);
  });
  const pageCount = Math.max(1, Math.ceil(matchingRows.length / APP_INFO_RELEASES_PER_PAGE));
  appInfoReleasePage = Math.min(Math.max(1, appInfoReleasePage), pageCount);
  const firstVisibleIndex = (appInfoReleasePage - 1) * APP_INFO_RELEASES_PER_PAGE;
  const visibleRows = new Set(matchingRows.slice(firstVisibleIndex, firstVisibleIndex + APP_INFO_RELEASES_PER_PAGE));
  $('#app-info-releases').querySelectorAll('[data-info-release]').forEach((row) => { row.hidden = !visibleRows.has(row); });

  const hasEntries = Boolean(appInfoContent?.release_notes.length);
  $('#app-info-history-no-results').hidden = !hasEntries || matchingRows.length > 0;
  const pagination = $('#app-info-history-pagination');
  pagination.hidden = matchingRows.length <= APP_INFO_RELEASES_PER_PAGE;
  $('#app-info-history-previous').disabled = appInfoReleasePage <= 1;
  $('#app-info-history-next').disabled = appInfoReleasePage >= pageCount;
  const from = matchingRows.length ? firstVisibleIndex + 1 : 0;
  const to = Math.min(firstVisibleIndex + APP_INFO_RELEASES_PER_PAGE, matchingRows.length);
  $('#app-info-history-page-status').textContent = `Page ${appInfoReleasePage} of ${pageCount} · Showing ${from}–${to} of ${matchingRows.length}`;
}

function updateAppInfoHeader(input, kind, item) {
  const form = input.closest('[data-app-info-form]');
  const index = Number(form?.dataset.index);
  const row = document.querySelector(`[data-info-${kind === 'sections' ? 'section' : 'release'}="${index}"]`);
  if (kind === 'sections' && input.dataset.appInfoField === 'title' && row) {
    row.querySelector('[data-section-summary]').textContent = item.title.trim() || 'Untitled section';
  }
  if (kind === 'history') {
    if (row && input.dataset.appInfoField === 'version') row.querySelector('[data-release-summary-version]').textContent = item.version.trim() || 'Untitled version';
    if (row && ['date', 'date_time'].includes(input.dataset.appInfoField)) row.querySelector('[data-release-summary-date]').textContent = item.date.trim() || 'Date not set';
    if (input.dataset.appInfoField === 'is_latest') {
      document.querySelectorAll(`[data-info-release="${index}"] [data-release-summary-latest]`).forEach((badge) => { badge.hidden = !item.is_latest; });
    }
  }
  if (appInfoSheetItem?.kind === kind && appInfoSheetItem.index === index) {
    $('#app-info-sheet-title').textContent = kind === 'sections' ? (item.title.trim() || 'New section') : (item.version.trim() || 'New update history');
  }
}

function updateAppInfoLatestBadges() {
  $('#app-info-releases').querySelectorAll('[data-info-release]').forEach((row) => {
    const index = Number(row.dataset.infoRelease);
    row.querySelector('[data-release-summary-latest]').hidden = !appInfoContent.release_notes[index]?.is_latest;
  });
}

function editorLines(value) {
  return value.split('\n').map((line) => line.trim()).filter(Boolean);
}

function readAppInfoEditors() {
  if (!appInfoContent) return { sections: [], releaseNotes: [] };
  const sections = appInfoContent.sections.map((section) => ({
    ...section,
    title: String(section.title ?? '').trim(),
    details: editorLines((section.details ?? []).join('\n')),
  }));
  const releaseNotes = appInfoContent.release_notes.map((release) => ({
    ...release,
    version: String(release.version ?? '').trim(),
    date: String(release.date ?? '').trim(),
    features: editorLines((release.features ?? []).join('\n')),
    fixes: editorLines((release.fixes ?? []).join('\n')),
    is_latest: release.is_latest === true,
  }));
  return { sections, releaseNotes };
}

async function saveAppInfo() {
  if (!appInfoContent || $('#save-app-info').disabled) return false;
  const { sections, releaseNotes } = readAppInfoEditors();
  if (!sections.length || sections.some((item) => !item.title || !item.details.length)) {
    notice('Each App Info section needs a title and at least one detail.', true); return false;
  }
  if (!releaseNotes.length || releaseNotes.filter((item) => item.is_latest).length !== 1) {
    notice('Keep at least one release entry and mark exactly one as the current version.', true); return false;
  }
  if (releaseNotes.some((item) => !item.version || !item.date)) {
    notice('Each release entry needs a version and date or label.', true); return false;
  }
  $('#save-app-info').disabled = true;
  $('#app-info-sheet-save').disabled = true;
  let error;
  try {
    ({ error } = await client.rpc('admin_update_app_info', {
      p_sections: sections,
      p_release_notes: releaseNotes,
    }));
  } catch (requestError) {
    error = requestError;
  } finally {
    $('#save-app-info').disabled = false;
    $('#app-info-sheet-save').disabled = false;
  }
  if (error) { notice(error.message, true); return false; }
  closeAppInfoSheet(false);
  await refreshData();
  showPage('app-info');
  notice('App Info and update history saved.');
  return true;
}

async function saveAppSettings(changes, auditLabel) {
  const { error } = await client.rpc('admin_update_app_settings', {
    p_maintenance_enabled: changes.maintenance_enabled ?? appSettings.maintenance_enabled,
    p_latest_version: changes.latest_version ?? appSettings.latest_version,
    p_minimum_supported_version: changes.minimum_supported_version ?? appSettings.minimum_supported_version,
    p_feature_flags: changes.feature_flags ?? appSettings.feature_flags,
    p_apk_download_url: changes.apk_download_url ?? appSettings.apk_download_url ?? '',
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
  $$('#mobile-tabs [data-page]').forEach((node) => node.classList.toggle('active', node.dataset.page === page));
  $('#more-tab').classList.toggle('active', !['dashboard', 'users', 'reports', 'announcements'].includes(page));
  $('#mobile-bulk-actions').hidden = selectedReportIds.size === 0 || page !== 'reports';
  $('#more-dialog').close();
  $('#page-title').textContent = ({ dashboard: 'Dashboard', users: 'Users', reports: 'Bug reports', announcements: 'Announcements', 'app-control': 'App control', 'app-info': 'App Info', team: 'Admin team', audit: 'Audit log' })[page];
  $('#mobile-page-title').textContent = $('#page-title').textContent;
}

function initTheme() {
  const saved = localStorage.getItem('c2f-admin-theme') || 'system';
  setTheme(saved);
  $('#appearance').addEventListener('change', () => setTheme($('#appearance').value));
  $('#mobile-appearance').addEventListener('change', () => setTheme($('#mobile-appearance').value));
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if ((localStorage.getItem('c2f-admin-theme') || 'system') === 'system') setTheme('system');
  });
}

async function init() {
  initTheme();
  try {
    if (localStorage.getItem('c2f-admin-app-info-tab') === 'history') appInfoActiveTab = 'history';
  } catch (_) {}
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
  $('#mobile-refresh').addEventListener('click', refreshData);
  $$('.nav').forEach((node) => node.addEventListener('click', () => showPage(node.dataset.page)));
  $$('#mobile-tabs [data-page], .more-link').forEach((node) => node.addEventListener('click', () => showPage(node.dataset.page)));
  $('#more-tab').addEventListener('click', () => $('#more-dialog').showModal());
  $('#mobile-signout').addEventListener('click', async () => { $('#more-dialog').close(); await $('#signout').click(); });
  $('#audit-open-filters').addEventListener('click', () => $('#audit-filter-dialog').showModal());
  $('#audit-filter-apply').addEventListener('click', () => $('#audit-filter-dialog').close());
  $('#app-info-tab-sections').addEventListener('click', () => setAppInfoTab('sections'));
  $('#app-info-tab-history').addEventListener('click', () => setAppInfoTab('history'));
  $('.app-info-tabs').addEventListener('keydown', (event) => {
    const tabs = [$('#app-info-tab-sections'), $('#app-info-tab-history')];
    const currentIndex = tabs.indexOf(event.target.closest('[role="tab"]'));
    if (currentIndex < 0) return;
    let nextIndex = currentIndex;
    if (event.key === 'ArrowRight') nextIndex = (currentIndex + 1) % tabs.length;
    else if (event.key === 'ArrowLeft') nextIndex = (currentIndex + tabs.length - 1) % tabs.length;
    else if (event.key === 'Home') nextIndex = 0;
    else if (event.key === 'End') nextIndex = tabs.length - 1;
    else return;
    event.preventDefault();
    setAppInfoTab(nextIndex === 0 ? 'sections' : 'history', true, true);
  });
  const auditToolbar = $('.audit-toolbar');
  const auditFilterNodes = ['#audit-action-filter', '#audit-target-filter', '#audit-actor-filter', ...$$('.audit-date-filter'), '#audit-clear-filters'].map((s) => typeof s === 'string' ? $(s) : s);
  const moveAuditFilters = () => {
    const target = window.matchMedia('(max-width: 899px)').matches ? $('#audit-filter-fields') : auditToolbar;
    auditFilterNodes.forEach((node) => target.append(node));
  };
  moveAuditFilters();
  window.matchMedia('(max-width: 899px)').addEventListener('change', moveAuditFilters);
  document.querySelectorAll('[data-app-info-collapse]').forEach((button) => button.addEventListener('click', () => {
    if (button.dataset.appInfoCollapse === 'sections') appInfoOpenSectionIndex = null;
    else appInfoOpenReleaseIndex = null;
    drawAppInfo();
  }));
  $('#add-info-section').addEventListener('click', () => {
    if (!appInfoContent) return;
    appInfoContent.sections.push({ id: `custom_${Date.now()}`, title: '', icon: 'info', details: [''] });
    const newIndex = appInfoContent.sections.length - 1;
    appInfoOpenSectionIndex = newIndex;
    drawAppInfo();
    if (appInfoMobileQuery.matches) openAppInfoSheet('sections', newIndex, 'title');
    else $(`#app-info-sections [data-info-section="${newIndex}"] [data-app-info-field="title"]`)?.focus();
  });
  $('#add-info-release').addEventListener('click', () => {
    if (!appInfoContent) return;
    appInfoContent.release_notes.forEach((entry) => { entry.is_latest = false; });
    const publishedAt = new Date();
    appInfoContent.release_notes.unshift({ version: '', date: appInfoDateTimeLabel(publishedAt), date_time: publishedAt.toISOString(), is_latest: true, features: [], fixes: [] });
    appInfoOpenReleaseIndex = 0;
    appInfoReleasePage = 1;
    $('#app-info-history-search').value = '';
    drawAppInfo();
    if (appInfoMobileQuery.matches) openAppInfoSheet('history', 0, 'version');
    else $('#app-info-releases [data-app-info-field="version"]')?.focus();
  });
  $('#app-info-sections').addEventListener('click', (event) => {
    const toggle = event.target.closest('[data-app-info-toggle="sections"]');
    if (toggle) {
      const index = Number(toggle.dataset.index);
      if (appInfoMobileQuery.matches) { openAppInfoSheet('sections', index); return; }
      appInfoOpenSectionIndex = appInfoOpenSectionIndex === index ? null : index;
      drawAppInfo();
      return;
    }
    const remove = event.target.closest('[data-remove-info-section]');
    if (!remove || !appInfoContent) return;
    removeAppInfoItem('sections', Number(remove.dataset.removeInfoSection));
  });
  $('#app-info-releases').addEventListener('click', (event) => {
    const toggle = event.target.closest('[data-app-info-toggle="history"]');
    if (toggle) {
      const index = Number(toggle.dataset.index);
      if (appInfoMobileQuery.matches) { openAppInfoSheet('history', index); return; }
      appInfoOpenReleaseIndex = appInfoOpenReleaseIndex === index ? null : index;
      drawAppInfo();
      return;
    }
    const remove = event.target.closest('[data-remove-info-release]');
    if (!remove || !appInfoContent) return;
    removeAppInfoItem('history', Number(remove.dataset.removeInfoRelease));
  });
  document.addEventListener('input', (event) => {
    if (event.target.matches('[data-app-info-field]')) updateAppInfoField(event.target);
  });
  $('#app-info-sheet-back').addEventListener('click', () => closeAppInfoSheet());
  $('#app-info-sheet-remove').addEventListener('click', () => {
    if (appInfoSheetItem) removeAppInfoItem(appInfoSheetItem.kind, appInfoSheetItem.index);
  });
  $('#app-info-sheet-save').addEventListener('click', saveAppInfo);
  $('#app-info-sheet').addEventListener('keydown', (event) => {
    if (event.key === 'Escape') { event.preventDefault(); closeAppInfoSheet(); return; }
    if (event.key !== 'Tab') return;
    const focusable = $$('#app-info-sheet button:not(:disabled), #app-info-sheet input:not(:disabled), #app-info-sheet textarea:not(:disabled)');
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  });
  $('#app-info-sheet-body').addEventListener('focusin', (event) => {
    if (event.target.matches('input, textarea')) window.setTimeout(() => event.target.scrollIntoView({ block: 'nearest', behavior: 'smooth' }), 120);
  });
  document.addEventListener('change', (event) => {
    if (event.target.matches('[data-app-info-field="is_latest"]')) updateAppInfoField(event.target);
  });
  appInfoMobileQuery.addEventListener('change', (event) => { if (!event.matches) closeAppInfoSheet(false); });
  const syncAppInfoViewport = () => {
    const viewport = window.visualViewport;
    document.documentElement.style.setProperty('--app-info-viewport-height', `${viewport?.height ?? window.innerHeight}px`);
    document.documentElement.style.setProperty('--app-info-viewport-top', `${viewport?.offsetTop ?? 0}px`);
  };
  syncAppInfoViewport();
  window.visualViewport?.addEventListener('resize', syncAppInfoViewport);
  window.visualViewport?.addEventListener('scroll', syncAppInfoViewport);
  $('#app-info-history-search').addEventListener('input', () => {
    appInfoReleasePage = 1;
    filterAppInfoReleases();
  });
  $('#app-info-history-previous').addEventListener('click', () => {
    if (appInfoReleasePage <= 1) return;
    appInfoReleasePage--;
    filterAppInfoReleases();
  });
  $('#app-info-history-next').addEventListener('click', () => {
    appInfoReleasePage++;
    filterAppInfoReleases();
  });
  $('#save-app-info').addEventListener('click', saveAppInfo);
  $('#user-search').addEventListener('input', drawUsers);
  $('#user-status').addEventListener('change', drawUsers);
  $('#user-status-pills').addEventListener('click', (event) => {
    const button = event.target.closest('[data-status]');
    if (!button) return;
    $('#user-status').value = button.dataset.status;
    drawUsers();
  });
  $('#report-status').addEventListener('change', drawReports);
  $('#report-status-pills').addEventListener('click', (event) => {
    const button = event.target.closest('[data-status]');
    if (!button) return;
    $('#report-status').value = button.dataset.status;
    drawReports();
  });
  ['#audit-search', '#audit-action-filter', '#audit-target-filter', '#audit-actor-filter', '#audit-date-from', '#audit-date-to']
    .forEach((selector) => $(selector).addEventListener(selector === '#audit-search' ? 'input' : 'change', () => {
      auditPage = 1;
      drawAudit();
    }));
  $('#audit-prev').addEventListener('click', () => { auditPage = Math.max(1, auditPage - 1); drawAudit(); });
  $('#audit-next').addEventListener('click', () => { auditPage += 1; drawAudit(); });
  $('#audit-clear-filters').addEventListener('click', () => {
    $('#audit-search').value = '';
    $('#audit-action-filter').value = '';
    $('#audit-target-filter').value = '';
    $('#audit-actor-filter').value = '';
    $('#audit-date-from').value = '';
    $('#audit-date-to').value = '';
    auditPage = 1;
    drawAudit();
  });
  $('#active-audit-filters').addEventListener('click', (event) => {
    const button = event.target.closest('[data-clear-filter]');
    if (!button) return;
    $(button.dataset.clearFilter).value = '';
    auditPage = 1;
    drawAudit();
  });
  $('#reports-cards').addEventListener('change', (event) => {
    const checkbox = event.target.closest('[data-report-select]');
    if (!checkbox) return;
    if (checkbox.checked) selectedReportIds.add(checkbox.dataset.reportSelect);
    else selectedReportIds.delete(checkbox.dataset.reportSelect);
    drawReports();
  });
  $('#reports-cards').addEventListener('click', (event) => {
    const button = event.target.closest('[data-report]');
    if (button) openReport(button.dataset.report);
  });
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
  $('#mobile-delete-selected').addEventListener('click', () => $('#delete-selected-reports').click());
  $('#mobile-resolve-selected').addEventListener('click', async () => {
    const ids = [...selectedReportIds];
    if (!ids.length) return;
    const { error } = await client.from('problem_reports').update({ status: 'resolved' }).in('id', ids);
    if (error) { notice(error.message, true); return; }
    selectedReportIds.clear();
    await refreshData();
    showPage('reports');
    notice(`Resolved ${ids.length} report${ids.length === 1 ? '' : 's'}.`);
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
    const rawHideAfterVersion = $('#announcement-hide-after-version').value.trim().replace(/^v/i, '');
    if (rawHideAfterVersion && !/^\d+(?:\.\d+)*$/.test(rawHideAfterVersion)) {
      notice('Enter the installed app version as numbers separated by dots, such as 3.0.3.35.', true); return;
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
      hide_after_version: rawHideAfterVersion || null,
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
    await saveAppSettings({
      latest_version: $('#latest-version').value.trim(),
      minimum_supported_version: $('#minimum-version').value.trim(),
      apk_download_url: $('#apk-download-url').value.trim(),
    }, 'App settings saved.');
    showPage('app-control');
  });
  $('#feature-switches').addEventListener('change', async (event) => {
    const input = event.target.closest('[data-feature]'); if (!input) return;
    const featureFlags = { ...(appSettings.feature_flags ?? {}), [input.dataset.feature]: input.checked };
    await saveAppSettings({ feature_flags: featureFlags }, 'Feature setting saved.');
    showPage('app-control');
  });
  $('#users-body').addEventListener('click', (e) => { const row = e.target.closest('[data-user]'); if (row) openUser(row.dataset.user); });
  $('#users-cards').addEventListener('click', (e) => { const card = e.target.closest('[data-user]'); if (card) openUser(card.dataset.user); });
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
    if (event === 'SIGNED_OUT' || !session) { stopProblemReportSubscription(); actor = account = null; role = null; showLogin(); }
  });
  const { data: { session } } = await client.auth.getSession();
  if (!session) { showLogin(); return; }
  try { await loadActor(); } catch (error) { await client.auth.signOut(); showLogin(error.message); }
}

init().catch((error) => showLogin(`Portal initialization failed: ${error.message}`));
