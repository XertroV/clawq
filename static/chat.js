// clawq chat UI
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

  function addToolPanel(id, name) {
    const panel = document.createElement('div');
    panel.className = 'tool-panel';
    panel.dataset.toolId = id;
    panel.innerHTML = `
      <div class="tool-panel-header">
        <span class="tool-name">${name}</span>
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
        hidePairModal();
        if (pendingRetry) pendingRetry();
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
