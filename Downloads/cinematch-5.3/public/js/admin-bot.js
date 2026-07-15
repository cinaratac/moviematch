const firebaseConfig = {
  apiKey: "AIzaSyAsHFffuxGA1cYKbHBs8LE6QbJOi4pjwC4",
  authDomain: "movie-matching-8a836.firebaseapp.com",
  projectId: "movie-matching-8a836",
  storageBucket: "movie-matching-8a836.firebasestorage.app",
  messagingSenderId: "266660427246",
  appId: "1:266660427246:web:4dcb77ff5e91e47dc04aff",
};

firebase.initializeApp(firebaseConfig);

const auth = firebase.auth();
const functions = firebase.functions();
const authPersistenceReady = auth.setPersistence(
  firebase.auth.Auth.Persistence.LOCAL
);

const els = {
  loginPanel: document.getElementById("loginPanel"),
  adminPanel: document.getElementById("adminPanel"),
  loginForm: document.getElementById("loginForm"),
  loginEmail: document.getElementById("loginEmail"),
  loginPassword: document.getElementById("loginPassword"),
  loginButton: document.getElementById("loginButton"),
  loginMessage: document.getElementById("loginMessage"),
  logoutButton: document.getElementById("logoutButton"),
  refreshButton: document.getElementById("refreshButton"),
  currentUserLabel: document.getElementById("currentUserLabel"),
  mainTitle: document.getElementById("mainTitle"),
  globalMessage: document.getElementById("globalMessage"),

  kpiSessions: document.getElementById("kpiSessions"),
  kpiMessages: document.getElementById("kpiMessages"),
  kpiTools: document.getElementById("kpiTools"),
  kpiRating: document.getElementById("kpiRating"),

  sessionSearch: document.getElementById("sessionSearch"),
  sessionCount: document.getElementById("sessionCount"),
  sessionList: document.getElementById("sessionList"),
  sessionPager: document.getElementById("sessionPager"),

  tabButtons: document.querySelectorAll(".tab-btn"),
  tabPanels: {
    overview: document.getElementById("tab-overview"),
    conversation: document.getElementById("tab-conversation"),
    tools: document.getElementById("tab-tools"),
  },

  ovSessions: document.getElementById("ovSessions"),
  ovActive: document.getElementById("ovActive"),
  ovMessages: document.getElementById("ovMessages"),
  ovUsers: document.getElementById("ovUsers"),
  ovTools: document.getElementById("ovTools"),
  ovToolSuccess: document.getElementById("ovToolSuccess"),
  ovAvgRating: document.getElementById("ovAvgRating"),
  ovEvalCount: document.getElementById("ovEvalCount"),
  topMoviesTable: document.querySelector("#topMoviesTable tbody"),

  conversationEmpty: document.getElementById("conversationEmpty"),
  conversationContent: document.getElementById("conversationContent"),
  sessionMeta: document.getElementById("sessionMeta"),
  sessionSummary: document.getElementById("sessionSummary"),
  transcriptList: document.getElementById("transcriptList"),
  sessionToolsTable: document.querySelector("#sessionToolsTable tbody"),
  sessionToolsEmpty: document.getElementById("sessionToolsEmpty"),
  evaluateForm: document.getElementById("evaluateForm"),
  evalRating: document.getElementById("evalRating"),
  evalNote: document.getElementById("evalNote"),
  evalMessage: document.getElementById("evalMessage"),
  evaluationsTable: document.querySelector("#evaluationsTable tbody"),

  toolCallsTable: document.querySelector("#toolCallsTable tbody"),
  toolCallsPager: document.getElementById("toolCallsPager"),
};

// Backend erişim bilgisi (getBotAdminAccess'ten alınır, sadece bellekte tutulur)
let botAccess = null; // { baseUrl, key }

let sessions = [];
let sessionOffset = 0;
const SESSION_PAGE_SIZE = 20;
let activeSessionId = null;

let toolCallsOffset = 0;
const TOOL_PAGE_SIZE = 25;

let charts = { daily: null, tool: null, rating: null };

function setMessage(target, text, type = "") {
  target.textContent = text || "";
  target.className = `message ${type}`.trim();
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function formatDate(value) {
  if (!value) return "-";
  // SQLite CURRENT_TIMESTAMP -> "YYYY-MM-DD HH:MM:SS" (UTC varsayılır)
  const iso = value.includes("T") ? value : value.replace(" ", "T") + "Z";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return value;
  return d.toLocaleString("tr-TR", { dateStyle: "short", timeStyle: "short" });
}

function showLogin() {
  els.loginPanel.classList.remove("hidden");
  els.adminPanel.classList.add("hidden");
}

function showAdmin(user) {
  els.loginPanel.classList.add("hidden");
  els.adminPanel.classList.remove("hidden");
  els.currentUserLabel.textContent = user.email || user.uid;
}

function isPermissionError(error) {
  const code = error && error.code ? String(error.code) : "";
  return code.includes("permission-denied") || code.includes("unauthenticated");
}

// ---------------------------------------------------------------------
// Backend (Flask /api/admin/...) çağrıları
// ---------------------------------------------------------------------

async function botFetch(path, options = {}) {
  if (!botAccess) throw new Error("Bot backend erişimi hazır değil.");
  
  // baseUrl yerine doğrudan doğru adresi yazıyoruz:
  const res = await fetch(`https://cinematchbotai.onrender.com${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-Admin-Key": botAccess.key, // Şifreyi hala güvenli bir şekilde alıyoruz
      ...(options.headers || {}),
    },
  });
  
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.status === "error") {
    throw new Error(body.message || `İstek başarısız (${res.status})`);
  }
  return body;
}
// ---------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------

function switchTab(tabName) {
  els.tabButtons.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === tabName);
  });
  Object.entries(els.tabPanels).forEach(([name, panel]) => {
    panel.classList.toggle("hidden", name !== tabName);
  });

  const titles = {
    overview: "Genel Bakış",
    conversation: "Konuşma Detayı",
    tools: "Tool Çağrıları",
  };
  els.mainTitle.textContent = titles[tabName] || "Bot Paneli";

  if (tabName === "tools" && !els.toolCallsTable.children.length) {
    loadToolCalls();
  }
}

els.tabButtons.forEach((btn) => {
  btn.addEventListener("click", () => switchTab(btn.dataset.tab));
});

// ---------------------------------------------------------------------
// Genel Bakış (overview + basit grafikler)
// ---------------------------------------------------------------------

function renderBarChart(canvasId, labels, data, color, chartKey) {
  const ctx = document.getElementById(canvasId);
  if (!ctx || typeof Chart === "undefined") return;
  if (charts[chartKey]) charts[chartKey].destroy();
  charts[chartKey] = new Chart(ctx, {
    type: "bar",
    data: {
      labels,
      datasets: [{ data, backgroundColor: color, borderRadius: 4 }],
    },
    options: {
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true, ticks: { precision: 0 } } },
    },
  });
}

async function loadOverview() {
  setMessage(els.globalMessage, "Genel bakış yükleniyor...");
  try {
    const { data } = await botFetch("/api/admin/overview?days=14");

    els.kpiSessions.textContent = data.total_sessions ?? "–";
    els.kpiMessages.textContent = data.total_messages ?? "–";
    els.kpiTools.textContent = data.total_tool_calls ?? "–";
    els.kpiRating.textContent = data.avg_rating != null ? data.avg_rating : "–";

    els.ovSessions.textContent = data.total_sessions ?? "–";
    els.ovActive.textContent = data.active_sessions ?? "–";
    els.ovMessages.textContent = data.total_messages ?? "–";
    els.ovUsers.textContent = data.total_users ?? "–";
    els.ovTools.textContent = data.total_tool_calls ?? "–";

    const successRate = data.total_tool_calls
      ? Math.round((data.successful_tool_calls / data.total_tool_calls) * 100)
      : null;
    els.ovToolSuccess.textContent = successRate != null ? `${successRate}%` : "–";
    els.ovAvgRating.textContent = data.avg_rating != null ? `${data.avg_rating} / 5` : "Henüz yok";
    els.ovEvalCount.textContent = data.total_evaluations ?? 0;

    renderBarChart(
      "dailyChart",
      (data.daily_messages || []).map((d) => d.day.slice(5)),
      (data.daily_messages || []).map((d) => d.c),
      "#18a63a",
      "daily"
    );

    renderBarChart(
      "toolChart",
      ["Başarılı", "Başarısız"],
      [data.successful_tool_calls || 0, data.failed_tool_calls || 0],
      ["#18a63a", "#d93838"],
      "tool"
    );

    renderBarChart(
      "ratingChart",
      (data.rating_distribution || []).map((r) => `${r.rating}★`),
      (data.rating_distribution || []).map((r) => r.c),
      "#c98a1f",
      "rating"
    );

    els.topMoviesTable.innerHTML = (data.top_movies || [])
      .map((m) => `<tr><td>${escapeHtml(m.movie_name)}</td><td>${m.c}</td></tr>`)
      .join("") || '<tr><td colspan="2">Henüz veri yok.</td></tr>';

    setMessage(els.globalMessage, "");
  } catch (error) {
    setMessage(els.globalMessage, error.message, "error");
  }
}

// ---------------------------------------------------------------------
// Konuşma listesi (sidebar)
// ---------------------------------------------------------------------

function renderSessionList() {
  if (!sessions.length) {
    els.sessionList.innerHTML = '<p class="message">Konuşma bulunamadı.</p>';
    return;
  }
  els.sessionList.innerHTML = "";
  sessions.forEach((s) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "article-item";
    button.dataset.id = s.session_id;
    const ratingBadge = s.avg_rating != null
      ? `<span class="rating-badge">★ ${Number(s.avg_rating).toFixed(1)}</span>`
      : "";
    button.innerHTML = `
      <strong>${escapeHtml(s.username || s.user_id)}</strong>
      <span>${s.message_count} mesaj · ${s.is_active ? "aktif" : "kapalı"} · ${formatDate(s.last_active_at)}</span>
      ${ratingBadge}
    `;
    button.addEventListener("click", () => openSession(s.session_id));
    els.sessionList.appendChild(button);
  });
  markActiveSession(activeSessionId);
}

function markActiveSession(id) {
  document.querySelectorAll(".article-item").forEach((button) => {
    button.classList.toggle("active", Number(button.dataset.id) === Number(id));
  });
}

function renderSessionPager(total) {
  const page = Math.floor(sessionOffset / SESSION_PAGE_SIZE) + 1;
  const totalPages = Math.max(1, Math.ceil(total / SESSION_PAGE_SIZE));
  els.sessionPager.innerHTML = `
    <button id="sessionPrev" ${sessionOffset === 0 ? "disabled" : ""}>‹ Önceki</button>
    <span>${page} / ${totalPages}</span>
    <button id="sessionNext" ${sessionOffset + SESSION_PAGE_SIZE >= total ? "disabled" : ""}>Sonraki ›</button>
  `;
  document.getElementById("sessionPrev")?.addEventListener("click", () => {
    sessionOffset = Math.max(0, sessionOffset - SESSION_PAGE_SIZE);
    loadSessions();
  });
  document.getElementById("sessionNext")?.addEventListener("click", () => {
    sessionOffset += SESSION_PAGE_SIZE;
    loadSessions();
  });
}

async function loadSessions() {
  try {
    const search = els.sessionSearch.value.trim();
    const params = new URLSearchParams({
      limit: SESSION_PAGE_SIZE,
      offset: sessionOffset,
    });
    if (search) params.set("search", search);

    const { data, pagination } = await botFetch(`/api/admin/sessions?${params}`);
    sessions = data;
    els.sessionCount.textContent = `${pagination.total} oturum`;
    renderSessionList();
    renderSessionPager(pagination.total);
  } catch (error) {
    els.sessionList.innerHTML = `<p class="message error">${escapeHtml(error.message)}</p>`;
  }
}

let searchDebounce = null;
els.sessionSearch.addEventListener("input", () => {
  clearTimeout(searchDebounce);
  searchDebounce = setTimeout(() => {
    sessionOffset = 0;
    loadSessions();
  }, 300);
});

// ---------------------------------------------------------------------
// Konuşma detayı
// ---------------------------------------------------------------------

async function openSession(sessionId) {
  activeSessionId = sessionId;
  markActiveSession(sessionId);
  switchTab("conversation");

  els.conversationEmpty.classList.add("hidden");
  els.conversationContent.classList.remove("hidden");
  els.transcriptList.innerHTML = '<p class="message">Yükleniyor...</p>';

  try {
    const { data } = await botFetch(`/api/admin/sessions/${sessionId}`);
    const { session, transcript, tool_calls, evaluations, user_facts } = data;

    els.sessionMeta.innerHTML = `
      <div><span>Kullanıcı</span>${escapeHtml(session.username || "-")}</div>
      <div><span>User ID</span>${escapeHtml(session.user_id)}</div>
      <div><span>Başladı</span>${formatDate(session.started_at)}</div>
      <div><span>Son Aktiflik</span>${formatDate(session.last_active_at)}</div>
      <div><span>Mesaj Sayısı</span>${session.message_count}</div>
      <div><span>Durum</span>${session.is_active ? "Aktif" : "Kapalı"}</div>
      <div><span>Bilinen Bilgiler</span>${escapeHtml(JSON.stringify(user_facts || {}))}</div>
    `;

    els.sessionSummary.textContent = session.summary && session.summary.trim()
      ? session.summary
      : "Bu oturum için henüz otomatik özet üretilmedi.";

    els.transcriptList.innerHTML = transcript.length
      ? transcript.map((turn) => `
          <div class="bubble-row">
            <div class="bubble bubble-user">${escapeHtml(turn.user_message)}</div>
            <div class="bubble bubble-bot">${escapeHtml(turn.bot_response)}</div>
            <div class="bubble-time">${formatDate(turn.created_at)}</div>
          </div>
        `).join("")
      : '<p class="message">Bu oturumda mesaj yok.</p>';

    if (tool_calls.length) {
      els.sessionToolsEmpty.classList.add("hidden");
      els.sessionToolsTable.innerHTML = tool_calls.map((t) => {
        const ok = /"Response":\s*"True"/.test(t.api_response);
        return `<tr>
          <td>${formatDate(t.timestamp)}</td>
          <td>get_live_movie_data</td>
          <td>${escapeHtml(t.movie_name)}</td>
          <td class="${ok ? "result-ok" : "result-fail"}">${ok ? "Bulundu" : "Bulunamadı"}</td>
        </tr>`;
      }).join("");
    } else {
      els.sessionToolsEmpty.classList.remove("hidden");
      els.sessionToolsTable.innerHTML = "";
    }

    renderEvaluations(evaluations);
  } catch (error) {
    els.transcriptList.innerHTML = `<p class="message error">${escapeHtml(error.message)}</p>`;
  }
}

function renderEvaluations(evaluations) {
  els.evaluationsTable.innerHTML = evaluations.length
    ? evaluations.map((e) => `
        <tr>
          <td>${formatDate(e.created_at)}</td>
          <td>${"★".repeat(e.rating)}${"☆".repeat(5 - e.rating)}</td>
          <td>${escapeHtml(e.note || "-")}</td>
          <td>${escapeHtml(e.evaluator || "-")}</td>
        </tr>
      `).join("")
    : '<tr><td colspan="4">Henüz değerlendirme yok.</td></tr>';
}

els.evaluateForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!activeSessionId) return;

  setMessage(els.evalMessage, "Kaydediliyor...");
  try {
    await botFetch(`/api/admin/sessions/${activeSessionId}/evaluate`, {
      method: "POST",
      body: JSON.stringify({
        rating: Number(els.evalRating.value),
        note: els.evalNote.value.trim(),
        evaluator: els.currentUserLabel.textContent,
      }),
    });
    setMessage(els.evalMessage, "Kaydedildi.", "success");
    els.evalNote.value = "";
    await openSession(activeSessionId); // listeyi + rozetleri tazele
    await loadSessions();
  } catch (error) {
    setMessage(els.evalMessage, error.message, "error");
  }
});

// ---------------------------------------------------------------------
// Tool çağrıları (global liste)
// ---------------------------------------------------------------------

function renderToolCallsPager(total) {
  const page = Math.floor(toolCallsOffset / TOOL_PAGE_SIZE) + 1;
  const totalPages = Math.max(1, Math.ceil(total / TOOL_PAGE_SIZE));
  els.toolCallsPager.innerHTML = `
    <button id="toolPrev" ${toolCallsOffset === 0 ? "disabled" : ""}>‹ Önceki</button>
    <span>${page} / ${totalPages}</span>
    <button id="toolNext" ${toolCallsOffset + TOOL_PAGE_SIZE >= total ? "disabled" : ""}>Sonraki ›</button>
  `;
  document.getElementById("toolPrev")?.addEventListener("click", () => {
    toolCallsOffset = Math.max(0, toolCallsOffset - TOOL_PAGE_SIZE);
    loadToolCalls();
  });
  document.getElementById("toolNext")?.addEventListener("click", () => {
    toolCallsOffset += TOOL_PAGE_SIZE;
    loadToolCalls();
  });
}

async function loadToolCalls() {
  try {
    const params = new URLSearchParams({ limit: TOOL_PAGE_SIZE, offset: toolCallsOffset });
    const { data, pagination } = await botFetch(`/api/admin/tool-calls?${params}`);

    els.toolCallsTable.innerHTML = data.length
      ? data.map((t) => {
          const ok = /"Response":\s*"True"/.test(t.api_response);
          return `<tr>
            <td>${formatDate(t.timestamp)}</td>
            <td>${escapeHtml(t.username || t.user_id || "-")}</td>
            <td>get_live_movie_data</td>
            <td>${escapeHtml(t.movie_name)}</td>
            <td class="${ok ? "result-ok" : "result-fail"}">${ok ? "Bulundu" : "Bulunamadı"}</td>
            <td>${t.session_id ? `<button class="link-btn" data-session="${t.session_id}">#${t.session_id}</button>` : "-"}</td>
          </tr>`;
        }).join("")
      : '<tr><td colspan="6">Henüz tool çağrısı yok.</td></tr>';

    els.toolCallsTable.querySelectorAll("[data-session]").forEach((btn) => {
      btn.addEventListener("click", () => openSession(Number(btn.dataset.session)));
    });

    renderToolCallsPager(pagination.total);
  } catch (error) {
    els.toolCallsTable.innerHTML = `<tr><td colspan="6">${escapeHtml(error.message)}</td></tr>`;
  }
}

// ---------------------------------------------------------------------
// Genel yenile / auth akışı
// ---------------------------------------------------------------------

async function loadAll() {
  sessionOffset = 0;
  toolCallsOffset = 0;
  await Promise.all([loadOverview(), loadSessions()]);
  if (!els.tabPanels.tools.classList.contains("hidden")) {
    await loadToolCalls();
  }
}

els.refreshButton.addEventListener("click", loadAll);

els.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  els.loginButton.disabled = true;
  setMessage(els.loginMessage, "Giriş yapılıyor...");

  try {
    await authPersistenceReady;
    await auth.signInWithEmailAndPassword(
      els.loginEmail.value.trim(),
      els.loginPassword.value
    );
    setMessage(els.loginMessage, "");
  } catch (error) {
    setMessage(els.loginMessage, error.message, "error");
  } finally {
    els.loginButton.disabled = false;
  }
});

els.logoutButton.addEventListener("click", () => auth.signOut());

auth.onAuthStateChanged(async (user) => {
  botAccess = null;

  if (!user) {
    showLogin();
    return;
  }

  try {
    await authPersistenceReady;
    const getBotAdminAccess = functions.httpsCallable("getBotAdminAccess");
    const result = await getBotAdminAccess();
    botAccess = result.data; // { baseUrl, key }

    showAdmin(user);
    await loadAll();
  } catch (error) {
    if (isPermissionError(error)) {
      await auth.signOut();
      showLogin();
      setMessage(els.loginMessage, "Bu panel için yetkiniz yok.", "error");
      return;
    }

    showAdmin(user);
    setMessage(
      els.globalMessage,
      error.message || "Bot backend erişimi alınamadı. Sayfayı yenileyebilirsiniz.",
      "error"
    );
  }
});
