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
  currentUserLabel: document.getElementById("currentUserLabel"),
  announcementStatus: document.getElementById("announcementStatus"),
  announcementList: document.getElementById("announcementList"),
  announcementId: document.getElementById("announcementId"),
  announcementActive: document.getElementById("announcementActive"),
  announcementTitle: document.getElementById("announcementTitle"),
  announcementMessage: document.getElementById("announcementMessage"),
  announcementImageUrl: document.getElementById("announcementImageUrl"),
  announcementMessageLabel: document.getElementById("announcementMessageLabel"),
  saveAnnouncementButton: document.getElementById("saveAnnouncementButton"),
  deactivateAnnouncementButton: document.getElementById("deactivateAnnouncementButton"),
};

function setMessage(target, text, type = "") {
  target.textContent = text || "";
  target.className = `message ${type}`.trim();
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

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function formatDate(value) {
  if (!value || typeof value.toDate !== "function") return "";
  const date = value.toDate();
  return `${date.getDate().toString().padStart(2, "0")}.${(date.getMonth() + 1)
    .toString()
    .padStart(2, "0")}.${date.getFullYear()}`;
}

function fillAnnouncement(data) {
  const announcement = data || {};
  els.announcementId.value = announcement.id || "";
  els.announcementActive.checked = announcement.isActive === true;
  els.announcementTitle.value = announcement.title || "";
  els.announcementMessage.value = announcement.message || "";
  els.announcementImageUrl.value = announcement.imageUrl || "";
  els.announcementStatus.textContent = announcement.isActive
    ? "Yayında"
    : "Pasif";
  renderAnnouncementList(Array.isArray(announcement.items) ? announcement.items : []);
  setMessage(els.announcementMessageLabel, "");
}

function renderAnnouncementList(items) {
  if (!items.length) {
    els.announcementList.innerHTML = '<p class="message">Henüz duyuru yok.</p>';
    return;
  }

  els.announcementList.innerHTML = "";
  items.slice(0, 12).forEach((item) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "article-item";
    button.innerHTML = `
      <strong>${escapeHtml(item.title || "Başlıksız duyuru")}</strong>
      <span>${escapeHtml(formatDate(item.date))}</span>
    `;
    button.addEventListener("click", () => {
      els.announcementId.value = item.id || "";
      els.announcementTitle.value = item.title || "";
      els.announcementMessage.value = item.message || "";
      els.announcementImageUrl.value = item.imageUrl || "";
      els.announcementActive.checked = true;
    });
    els.announcementList.appendChild(button);
  });
}

function collectAnnouncement({ forceInactive = false } = {}) {
  const isActive = forceInactive ? false : els.announcementActive.checked;
  return {
    id: isActive ? "" : els.announcementId.value.trim(),
    isActive,
    title: els.announcementTitle.value.trim(),
    message: els.announcementMessage.value.trim(),
    imageUrl: els.announcementImageUrl.value.trim(),
  };
}

async function loadAnnouncement() {
  setMessage(els.announcementMessageLabel, "Duyuru yükleniyor...");
  try {
    const getAnnouncement = functions.httpsCallable("getAnnouncement");
    const result = await getAnnouncement();
    fillAnnouncement(result.data && result.data.announcement);
  } catch (error) {
    setMessage(els.announcementMessageLabel, error.message, "error");
  }
}

async function saveAnnouncement(payload, loadingText, successText) {
  els.saveAnnouncementButton.disabled = true;
  els.deactivateAnnouncementButton.disabled = true;
  setMessage(els.announcementMessageLabel, loadingText);

  try {
    const saveAnnouncement = functions.httpsCallable("saveAnnouncement");
    const result = await saveAnnouncement(payload);
    if (result.data && result.data.id) els.announcementId.value = result.data.id;
    setMessage(els.announcementMessageLabel, successText, "success");
    await loadAnnouncement();
  } catch (error) {
    setMessage(els.announcementMessageLabel, error.message, "error");
  } finally {
    els.saveAnnouncementButton.disabled = false;
    els.deactivateAnnouncementButton.disabled = false;
  }
}

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

els.saveAnnouncementButton.addEventListener("click", () => {
  saveAnnouncement(
    collectAnnouncement(),
    "Duyuru kaydediliyor...",
    "Duyuru kaydedildi."
  );
});

els.deactivateAnnouncementButton.addEventListener("click", () => {
  saveAnnouncement(
    collectAnnouncement({ forceInactive: true }),
    "Duyuru pasifleştiriliyor...",
    "Duyuru pasifleştirildi."
  );
});

auth.onAuthStateChanged(async (user) => {
  if (!user) {
    showLogin();
    return;
  }

  try {
    await authPersistenceReady;
    const isNewsAdmin = functions.httpsCallable("isNewsAdmin");
    await isNewsAdmin();
    showAdmin(user);
    loadAnnouncement();
  } catch (error) {
    if (isPermissionError(error)) {
      await auth.signOut();
      showLogin();
      setMessage(els.loginMessage, "Bu panel için yetkiniz yok.", "error");
      return;
    }

    showAdmin(user);
    setMessage(
      els.announcementMessageLabel,
      "Yetki kontrolu gecici olarak tamamlanamadi. Sayfayi yenileyebilirsiniz.",
      "error"
    );
  }
});
