const firebaseConfig = {
  apiKey: "AIzaSyAsHFffuxGA1cYKbHBs8LE6QbJOi4pjwC4",
  authDomain: "movie-matching-8a836.firebaseapp.com",
  projectId: "movie-matching-8a836",
  storageBucket: "movie-matching-8a836.firebasestorage.app",
  messagingSenderId: "266660427246",
  appId: "1:266660427246:web:4dcb77ff5e91e47dc04aff",
};

firebase.initializeApp(firebaseConfig);
const db = firebase.firestore();

const pageType = document.body.dataset.newsPage;
let allArticles = [];

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function formatDate(timestamp) {
  const date = timestamp && timestamp.toDate ? timestamp.toDate() : null;
  if (!date) return "";
  return date.toLocaleDateString("tr-TR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });
}

function articleLink(article) {
  return `news-detail.html?id=${encodeURIComponent(article.id)}`;
}

function renderList() {
  const list = document.getElementById("newsList");
  const count = document.getElementById("newsCount");
  const searchInput = document.getElementById("newsSearch");
  const search = (searchInput.value || "").trim().toLocaleLowerCase("tr-TR");
  const visible = allArticles.filter((article) => {
    const haystack = [
      article.title,
      article.summary,
      article.category,
      article.movieTitle,
      Array.isArray(article.tags) ? article.tags.join(" ") : "",
    ]
      .join(" ")
      .toLocaleLowerCase("tr-TR");
    return !search || haystack.includes(search);
  });

  count.textContent = `${visible.length} haber`;

  if (!visible.length) {
    list.innerHTML = '<p class="state-text">Gosterilecek haber yok.</p>';
    return;
  }

  list.innerHTML = visible
    .map((article) => {
      const image = article.imageUrl
        ? `<img src="${escapeHtml(article.imageUrl)}" alt="${escapeHtml(article.title)}" loading="lazy" />`
        : "";
      return `
        <a class="news-card" href="${articleLink(article)}">
          ${image}
          <div class="news-card-body">
            <div class="news-meta">
              <strong>${escapeHtml(article.category || "Haber")}</strong>
              <span>${escapeHtml(formatDate(article.publishedAt))}</span>
            </div>
            <h3>${escapeHtml(article.title)}</h3>
            <p>${escapeHtml(article.summary || "")}</p>
            <span class="read-more">Haberi oku</span>
          </div>
        </a>
      `;
    })
    .join("");
}

async function loadList() {
  const list = document.getElementById("newsList");
  const searchInput = document.getElementById("newsSearch");

  try {
    const snapshot = await db
      .collection("public_news")
      .orderBy("publishedAt", "desc")
      .limit(80)
      .get();

    allArticles = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    searchInput.addEventListener("input", renderList);
    renderList();
  } catch (error) {
    list.innerHTML = `<p class="state-text">Haberler yuklenemedi: ${escapeHtml(error.message)}</p>`;
  }
}

function renderDetail(article) {
  const target = document.getElementById("articleDetail");
  const paragraphs = String(article.body || "")
    .split(/\n\s*\n/)
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => `<p>${escapeHtml(part)}</p>`)
    .join("");
  const image = article.imageUrl
    ? `<img class="article-image" src="${escapeHtml(article.imageUrl)}" alt="${escapeHtml(article.title)}" />`
    : "";
  const tags = Array.isArray(article.tags)
    ? article.tags.map((tag) => `<span class="tag">${escapeHtml(tag)}</span>`).join("")
    : "";
  const source = article.sourceUrl
    ? `<a class="source-link" href="${escapeHtml(article.sourceUrl)}" target="_blank" rel="noopener">Kaynağı aç</a>`
    : "";

  document.title = `${article.title} - CineMatch`;
  target.innerHTML = `
    <div class="news-meta">
      <strong>${escapeHtml(article.category || "Haber")}</strong>
      <span>${escapeHtml(formatDate(article.publishedAt))}</span>
      ${article.movieTitle ? `<span>${escapeHtml(article.movieTitle)}</span>` : ""}
    </div>
    <h1>${escapeHtml(article.title)}</h1>
    ${article.summary ? `<p class="article-summary">${escapeHtml(article.summary)}</p>` : ""}
    ${image}
    <div class="article-body">${paragraphs}</div>
    ${tags ? `<div class="tag-row">${tags}</div>` : ""}
    ${source}
  `;
}

async function loadDetail() {
  const target = document.getElementById("articleDetail");
  const params = new URLSearchParams(window.location.search);
  const id = params.get("id");

  if (!id) {
    target.innerHTML = '<p class="state-text">Haber bağlantısı eksik.</p>';
    return;
  }

  try {
    const doc = await db.collection("public_news").doc(id).get();
    if (!doc.exists) {
      target.innerHTML = '<p class="state-text">Haber bulunamadı.</p>';
      return;
    }
    renderDetail({ id: doc.id, ...doc.data() });
  } catch (error) {
    target.innerHTML = `<p class="state-text">Haber yuklenemedi: ${escapeHtml(error.message)}</p>`;
  }
}

if (pageType === "list") {
  loadList();
}

if (pageType === "detail") {
  loadDetail();
}
