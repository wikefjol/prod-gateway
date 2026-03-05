/* AI Gateway Portal — Client-side logic */

// Config injected by template via window.PORTAL_CONFIG
const CONFIG = window.PORTAL_CONFIG || {};

// ===== Toast Notifications =====
function showToast(message, type) {
  type = type || 'success';
  var container = document.getElementById('toastContainer');
  if (!container) return;
  var toast = document.createElement('div');
  toast.className = 'toast ' + type;
  var icon = type === 'success' ? '\u2705' : '\u274c';
  toast.innerHTML =
    '<div class="toast-content">' +
      '<span class="toast-icon">' + icon + '</span>' +
      '<span class="toast-message">' + message + '</span>' +
      '<button class="toast-close" onclick="closeToast(this)">\u00d7</button>' +
    '</div>';
  container.appendChild(toast);
  setTimeout(function() { toast.classList.add('show'); }, 100);
  setTimeout(function() {
    if (toast.parentNode) closeToast(toast.querySelector('.toast-close'));
  }, 5000);
}

function closeToast(btn) {
  var toast = btn.closest('.toast');
  toast.classList.remove('show');
  setTimeout(function() {
    if (toast.parentNode) toast.parentNode.removeChild(toast);
  }, 300);
}

// ===== Loading State =====
function setLoading(isLoading) {
  var el = document.querySelector('.container');
  if (!el) return;
  if (isLoading) el.classList.add('loading');
  else el.classList.remove('loading');
}

// ===== Key Visibility =====
var isKeyVisible = false;

function toggleKeyVisibility() {
  var hidden = document.getElementById('keyHidden');
  var visible = document.getElementById('keyVisible');
  var icon = document.getElementById('eyeIcon');
  if (!hidden || !visible) return;
  isKeyVisible = !isKeyVisible;
  hidden.style.display = isKeyVisible ? 'none' : 'inline';
  visible.style.display = isKeyVisible ? 'inline' : 'none';
  if (icon) icon.textContent = isKeyVisible ? '\ud83d\udc41\ufe0f\u200d\ud83d\udde8\ufe0f' : '\ud83d\udc41\ufe0f';
}

// ===== Copy to Clipboard =====
function copyToClipboard() {
  var key = CONFIG.apiKey;
  if (!key) { showToast('No API key to copy', 'error'); return; }
  navigator.clipboard.writeText(key).then(function() {
    showToast('API key copied to clipboard!');
    var btn = document.getElementById('copyBtn');
    if (btn) {
      var orig = btn.innerHTML;
      btn.innerHTML = '\u2713';
      setTimeout(function() { btn.innerHTML = orig; }, 1500);
    }
  }).catch(function() {
    showToast('Failed to copy. Please copy manually.', 'error');
  });
}

// ===== Get Key =====
function getKey() {
  setLoading(true);
  var btn = document.getElementById('getKeyBtn');
  var orig = btn.innerHTML;
  btn.innerHTML = '<span class="spinner"></span> Getting Key...';
  fetch('/portal/get-key', { method: 'POST', headers: { 'Content-Type': 'application/json' } })
    .then(function(r) { return r.json().then(function(d) { return { ok: r.ok, data: d }; }); })
    .then(function(res) {
      if (res.ok && res.data.success) {
        showToast(res.data.message);
        setTimeout(function() { window.location.reload(); }, 1500);
      } else {
        showToast('Error: ' + (res.data.error || 'Unknown'), 'error');
        btn.innerHTML = orig;
      }
    })
    .catch(function(e) { showToast('Network error: ' + e.message, 'error'); btn.innerHTML = orig; })
    .finally(function() { setLoading(false); });
}

// ===== Recycle Key =====
function recycleKey() {
  if (!confirm('Are you sure you want to recycle your API key?\n\nThis invalidates the current key. Applications using it will need the new key.')) return;
  setLoading(true);
  var btn = document.getElementById('recycleBtn');
  var orig = btn.innerHTML;
  btn.innerHTML = '<span class="spinner"></span> Recycling...';
  fetch('/portal/recycle-key', { method: 'POST', headers: { 'Content-Type': 'application/json' } })
    .then(function(r) { return r.json().then(function(d) { return { ok: r.ok, data: d }; }); })
    .then(function(res) {
      if (res.ok && res.data.success) {
        showToast(res.data.message);
        setTimeout(function() { window.location.reload(); }, 1500);
      } else {
        showToast('Error: ' + (res.data.error || 'Unknown'), 'error');
        btn.innerHTML = orig;
      }
    })
    .catch(function(e) { showToast('Network error: ' + e.message, 'error'); btn.innerHTML = orig; })
    .finally(function() { setLoading(false); });
}

// ===== Test API Key =====
function testApiKey() {
  var msgEl = document.getElementById('testMessage');
  var message = msgEl ? msgEl.value.trim() : '';
  if (!message) { showToast('Please enter a test message', 'error'); if (msgEl) msgEl.focus(); return; }

  var key = CONFIG.apiKey;
  if (!key) { showToast('No API key available for testing', 'error'); return; }

  var modelEl = document.getElementById('testModel');
  var model = modelEl ? modelEl.value : 'claude-haiku-4-5';

  var testBtn = document.getElementById('testBtn');
  var testBtnText = document.getElementById('testBtnText');
  var testSpinner = document.getElementById('testSpinner');
  if (testBtn) testBtn.disabled = true;
  if (testBtnText) testBtnText.style.display = 'none';
  if (testSpinner) testSpinner.style.display = 'inline-block';

  var body = { model: model, max_tokens: 150, messages: [{ role: 'user', content: message }] };
  var endpoint = '/llm/ai-proxy/v1/chat/completions';
  var reqDetails = { url: endpoint, method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer [HIDDEN]' }, body: body };

  fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key },
    body: JSON.stringify(body)
  })
  .then(function(r) {
    return r.json().then(function(d) {
      return { ok: r.ok, status: r.status, statusText: r.statusText, headers: Object.fromEntries(r.headers.entries()), data: d };
    });
  })
  .then(function(res) {
    var text = 'No response content';
    if (res.ok) {
      if (res.data.choices && res.data.choices.length > 0) {
        text = (res.data.choices[0].message && res.data.choices[0].message.content) || res.data.choices[0].text || text;
      }
      showTestResults(text, reqDetails, { status: res.status, statusText: res.statusText, headers: res.headers, body: res.data });
      showToast('API test successful!');
    } else {
      var errMsg = res.data.error || res.data.message || ('HTTP ' + res.status + ': ' + res.statusText);
      showTestResults('Error: ' + errMsg, reqDetails, { status: res.status, statusText: res.statusText, headers: res.headers, body: res.data });
      showToast('API test failed: ' + errMsg, 'error');
    }
  })
  .catch(function(e) {
    showTestResults('Network Error: ' + e.message, reqDetails, { error: e.message });
    showToast('Network error: ' + e.message, 'error');
  })
  .finally(function() {
    if (testBtn) testBtn.disabled = false;
    if (testBtnText) testBtnText.style.display = 'inline';
    if (testSpinner) testSpinner.style.display = 'none';
  });
}

function showTestResults(responseText, requestDetails, responseDetails) {
  var rc = document.getElementById('responseContent');
  if (rc) rc.textContent = responseText;
  var rd = document.getElementById('requestDetails');
  if (rd) rd.textContent = JSON.stringify(requestDetails, null, 2);
  var rsd = document.getElementById('responseDetails');
  if (rsd) rsd.textContent = JSON.stringify(responseDetails, null, 2);
  var tr = document.getElementById('testResponse');
  if (tr) tr.style.display = 'block';
  var td = document.getElementById('testDetails');
  if (td) td.style.display = 'block';
}

function clearTest() {
  var msg = document.getElementById('testMessage');
  if (msg) msg.value = '';
  var tr = document.getElementById('testResponse');
  if (tr) tr.style.display = 'none';
  var td = document.getElementById('testDetails');
  if (td) td.style.display = 'none';
  showToast('Test cleared');
}

// ===== Init =====
document.addEventListener('DOMContentLoaded', function() {
  // Ctrl+Enter to send test
  document.addEventListener('keydown', function(e) {
    if (e.target.id === 'testMessage' && e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      testApiKey();
    }
  });
  // Auto-resize textarea
  var ta = document.getElementById('testMessage');
  if (ta) {
    ta.addEventListener('input', function() {
      this.style.height = 'auto';
      this.style.height = Math.min(this.scrollHeight, 200) + 'px';
    });
  }
  // Active nav link
  var path = window.location.pathname;
  document.querySelectorAll('.nav-link').forEach(function(link) {
    var href = link.getAttribute('href');
    if (href === '/portal/' && (path === '/portal/' || path === '/portal')) {
      link.classList.add('active');
    } else if (href !== '/portal/' && path.startsWith(href)) {
      link.classList.add('active');
    }
  });
});
