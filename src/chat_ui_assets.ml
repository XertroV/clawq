(* Auto-generated chat UI assets - embedded static files *)

let index_html =
  {|<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>clawq chat</title>
  <link rel="stylesheet" href="/chat.css">
</head>
<body>
<div id="app">
  <div id="header">
    <span id="title">clawq</span>
    <span id="status" class="status-dot"></span>
  </div>
  <div id="messages"></div>
  <div id="tool-timeline"></div>
  <form id="input-form">
    <input type="text" id="user-input" placeholder="Type a message..." autocomplete="off">
    <button type="submit" id="send-btn">Send</button>
    <button type="button" id="abort-btn" style="display:none">Stop</button>
  </form>
</div>
<div id="pair-modal" style="display:none">
  <div id="pair-dialog">
    <h2>Pairing Required</h2>
    <p>Enter the 6-digit pairing code shown by <code>clawq otp-show</code>:</p>
    <input type="text" id="pair-code" maxlength="6" placeholder="000000" pattern="[0-9]{6}">
    <div id="pair-error"></div>
    <button id="pair-submit">Pair</button>
  </div>
</div>
<script src="/chat.js"></script>
</body>
</html>
|}

let chat_css =
  {|*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, monospace;
  background: #0f0f0f;
  color: #e0e0e0;
  height: 100vh;
  display: flex;
  flex-direction: column;
}

#app {
  display: flex;
  flex-direction: column;
  height: 100vh;
  max-width: 900px;
  margin: 0 auto;
  width: 100%;
}

#header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  border-bottom: 1px solid #222;
  background: #111;
}

#title {
  font-weight: 600;
  font-size: 1.1rem;
  color: #ccc;
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #444;
}
.status-dot.active { background: #4caf50; }
.status-dot.thinking { background: #ff9800; animation: pulse 1s infinite; }

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}

#messages {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.message {
  max-width: 80%;
  padding: 10px 14px;
  border-radius: 8px;
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-word;
}

.message.user {
  background: #1a3a5c;
  align-self: flex-end;
  border-bottom-right-radius: 2px;
}

.message.assistant {
  background: #1e1e1e;
  align-self: flex-start;
  border-bottom-left-radius: 2px;
  border: 1px solid #2a2a2a;
}

.message.system {
  background: #1a1a1a;
  align-self: center;
  font-size: 0.85rem;
  color: #888;
  border: 1px solid #333;
}

#tool-timeline {
  padding: 0 16px 8px;
}

.tool-panel {
  background: #151515;
  border: 1px solid #2a2a2a;
  border-radius: 6px;
  margin-bottom: 6px;
  overflow: hidden;
}

.tool-panel-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  cursor: pointer;
  user-select: none;
  font-size: 0.85rem;
}

.tool-panel-header:hover { background: #1c1c1c; }

.tool-name { color: #7ecfff; font-family: monospace; }
.tool-status { margin-left: auto; font-size: 0.75rem; }
.tool-status.running { color: #ff9800; }
.tool-status.done { color: #4caf50; }
.tool-status.error { color: #f44336; }

.tool-panel-body {
  display: none;
  padding: 8px 12px;
  font-size: 0.8rem;
  font-family: monospace;
  color: #aaa;
  border-top: 1px solid #222;
  white-space: pre-wrap;
  max-height: 200px;
  overflow-y: auto;
}

.tool-panel.expanded .tool-panel-body { display: block; }

#input-form {
  display: flex;
  gap: 8px;
  padding: 12px 16px;
  border-top: 1px solid #222;
  background: #111;
}

#user-input {
  flex: 1;
  background: #1e1e1e;
  border: 1px solid #333;
  border-radius: 6px;
  padding: 10px 14px;
  color: #e0e0e0;
  font-size: 0.95rem;
  outline: none;
}

#user-input:focus { border-color: #4a9eff; }

button {
  background: #1a3a5c;
  color: #e0e0e0;
  border: none;
  border-radius: 6px;
  padding: 10px 18px;
  cursor: pointer;
  font-size: 0.9rem;
}

button:hover { background: #224a72; }
button:disabled { opacity: 0.5; cursor: not-allowed; }

#abort-btn { background: #3a1a1a; }
#abort-btn:hover { background: #4a2020; }

/* Pair modal */
#pair-modal {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.7);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

#pair-dialog {
  background: #1a1a1a;
  border: 1px solid #333;
  border-radius: 10px;
  padding: 28px;
  max-width: 380px;
  width: 90%;
}

#pair-dialog h2 { margin-bottom: 12px; color: #ccc; }
#pair-dialog p { margin-bottom: 16px; color: #999; font-size: 0.9rem; line-height: 1.5; }
#pair-dialog code { color: #7ecfff; font-family: monospace; }

#pair-code {
  width: 100%;
  background: #111;
  border: 1px solid #444;
  border-radius: 6px;
  padding: 10px;
  color: #e0e0e0;
  font-size: 1.2rem;
  letter-spacing: 0.2em;
  text-align: center;
  margin-bottom: 10px;
}

#pair-error { color: #f44336; font-size: 0.85rem; min-height: 20px; margin-bottom: 10px; }

#pair-submit { width: 100%; }

/* Scrollbar */
::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #333; border-radius: 3px; }
|}

let chat_js =
  {|// clawq chat UI
(function() {
  const SESSION_KEY = 'clawq_session_id';
  const TOKEN_KEY = 'clawq_token';

  function getSessionId() {
    let id = localStorage.getItem(SESSION_KEY);
    if (!id) {
      id = 'web-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
      localStorage.setItem(SESSION_KEY, id);
    }
    return id;
  }

  function getToken() {
    return localStorage.getItem(TOKEN_KEY) || '';
  }

  function setToken(t) {
    localStorage.setItem(TOKEN_KEY, t);
  }

  const sessionId = getSessionId();
  const messagesEl = document.getElementById('messages');
  const form = document.getElementById('input-form');
  const inputEl = document.getElementById('user-input');
  const sendBtn = document.getElementById('send-btn');
  const abortBtn = document.getElementById('abort-btn');
  const statusDot = document.getElementById('status');
  const toolTimeline = document.getElementById('tool-timeline');
  const pairModal = document.getElementById('pair-modal');
  const pairCode = document.getElementById('pair-code');
  const pairSubmit = document.getElementById('pair-submit');
  const pairError = document.getElementById('pair-error');

  let abortController = null;
  let currentToolPanels = {};

  function setStatus(s) {
    statusDot.className = 'status-dot ' + s;
  }

  function addMessage(role, content) {
    const div = document.createElement('div');
    div.className = 'message ' + role;
    div.textContent = content;
    messagesEl.appendChild(div);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return div;
  }

  function clearToolTimeline() {
    toolTimeline.innerHTML = '';
    currentToolPanels = {};
  }

  function escapeHtml(s) {
    const d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  function addToolPanel(id, name) {
    const panel = document.createElement('div');
    panel.className = 'tool-panel';
    panel.dataset.toolId = id;
    panel.innerHTML = `
      <div class="tool-panel-header">
        <span class="tool-name">${escapeHtml(name)}</span>
        <span class="tool-status running">running...</span>
      </div>
      <div class="tool-panel-body"></div>
    `;
    panel.querySelector('.tool-panel-header').addEventListener('click', () => {
      panel.classList.toggle('expanded');
    });
    toolTimeline.appendChild(panel);
    currentToolPanels[id] = panel;
    return panel;
  }

  function updateToolPanel(id, result) {
    const panel = currentToolPanels[id];
    if (!panel) return;
    const statusEl = panel.querySelector('.tool-status');
    const bodyEl = panel.querySelector('.tool-panel-body');
    const isError = result && result.startsWith('Error:');
    statusEl.textContent = isError ? 'error' : 'done';
    statusEl.className = 'tool-status ' + (isError ? 'error' : 'done');
    if (result) bodyEl.textContent = result.slice(0, 2000);
  }

  function parseSSEData(line) {
    if (!line.startsWith('data: ')) return null;
    const raw = line.slice(6).trim();
    if (raw === '[DONE]') return { type: 'done_sentinel' };
    try {
      return JSON.parse(raw);
    } catch(e) {
      return { type: 'raw', content: raw };
    }
  }

  async function sendMessage(message) {
    if (!message.trim()) return;

    setStatus('thinking');
    sendBtn.disabled = true;
    abortBtn.style.display = '';
    clearToolTimeline();

    const userDiv = addMessage('user', message);
    const assistantDiv = addMessage('assistant', '');
    let assistantContent = '';

    abortController = new AbortController();

    try {
      const token = getToken();
      const headers = { 'Content-Type': 'application/json' };
      if (token) headers['Authorization'] = 'Bearer ' + token;

      const resp = await fetch('/chat/stream', {
        method: 'POST',
        headers,
        body: JSON.stringify({ session_id: sessionId, message }),
        signal: abortController.signal,
      });

      if (resp.status === 401 || resp.status === 403) {
        showPairModal(async () => {
          await sendMessage(message);
        });
        return;
      }

      if (!resp.ok) {
        const err = await resp.text();
        assistantDiv.textContent = 'Error: ' + resp.status + ' ' + err;
        return;
      }

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop();

        for (const line of lines) {
          if (!line.trim()) continue;
          const data = parseSSEData(line);
          if (!data) continue;

          if (data.type === 'done_sentinel' || data.type === 'done') break;
          if (data.type === 'delta' && data.content) {
            assistantContent += data.content;
            assistantDiv.textContent = assistantContent;
            messagesEl.scrollTop = messagesEl.scrollHeight;
          } else if (data.type === 'tool_start') {
            addToolPanel(data.id || data.name, data.name);
          } else if (data.type === 'tool_result') {
            updateToolPanel(data.id || data.name, data.result || '');
          }
        }
      }
    } catch(e) {
      if (e.name !== 'AbortError') {
        assistantDiv.textContent = assistantContent || ('Error: ' + e.message);
      } else {
        if (!assistantContent) assistantDiv.textContent = '[Stopped]';
      }
    } finally {
      abortController = null;
      sendBtn.disabled = false;
      abortBtn.style.display = 'none';
      setStatus('active');
    }
  }

  let pendingRetry = null;

  function showPairModal(retry) {
    pendingRetry = retry;
    pairCode.value = '';
    pairError.textContent = '';
    pairModal.style.display = 'flex';
    pairCode.focus();
  }

  function hidePairModal() {
    pairModal.style.display = 'none';
    pendingRetry = null;
  }

  pairSubmit.addEventListener('click', async () => {
    const code = pairCode.value.trim();
    if (!/^\d{6}$/.test(code)) {
      pairError.textContent = 'Enter a 6-digit code.';
      return;
    }
    pairError.textContent = '';
    try {
      const resp = await fetch('/pair', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code }),
      });
      const data = await resp.json();
      if (!resp.ok) {
        pairError.textContent = data.error || 'Pairing failed.';
        return;
      }
      if (data.token) {
        setToken(data.token);
        const retry = pendingRetry;
        hidePairModal();
        if (retry) retry();
      } else {
        pairError.textContent = 'No token received.';
      }
    } catch(e) {
      pairError.textContent = 'Network error: ' + e.message;
    }
  });

  pairCode.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') pairSubmit.click();
  });

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const msg = inputEl.value.trim();
    if (!msg) return;
    inputEl.value = '';
    sendMessage(msg);
  });

  abortBtn.addEventListener('click', () => {
    if (abortController) abortController.abort();
  });

  inputEl.focus();
  setStatus('active');
})();
|}

