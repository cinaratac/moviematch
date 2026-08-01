/* eslint-disable */
const functions = require("firebase-functions/v1"); // v1 Triggerlar için
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // v2 Callable fonksiyonlar için
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");
const sanitizeHtml = require("sanitize-html");

// Firebase Admin'i başlat
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const NEWS_ADMIN_UIDS = new Set([
  "RfpPtaZfaKYueG9b2dd2ASScqOO2",
  "ZkXr7PmQ4WV0iRIVR7uUUwfNS8N2",
  "mNCWixSnJSa6tE1hZs4iZwn3Du43",
]);

function cleanText(value, maxLength = 20000) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maxLength);
}

function makeSlug(value) {
  return cleanText(value, 160)
    .toLocaleLowerCase("tr-TR")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ı/g, "i")
    .replace(/ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/ş/g, "s")
    .replace(/ö/g, "o")
    .replace(/ç/g, "c")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 120);
}

async function assertNewsEditor(uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
  if (NEWS_ADMIN_UIDS.has(uid)) return true;

  const db = admin.firestore();
  const editorDoc = await db.collection("news_editors").doc(uid).get();
  if (editorDoc.exists && editorDoc.data().active !== false) return true;

  const userDoc = await db.collection("users").doc(uid).get();
  const role = userDoc.exists ? userDoc.data().role : null;
  if (["admin", "editor", "newsEditor"].includes(role)) return true;

  throw new HttpsError("permission-denied", "Bu panel için yetkiniz yok.");
}

async function assertTriviaEditor(uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Giris yapmaniz gerekiyor.");
  if (NEWS_ADMIN_UIDS.has(uid)) return true;

  const db = admin.firestore();
  const editorDoc = await db.collection("trivia_editors").doc(uid).get();
  if (editorDoc.exists && editorDoc.data().active !== false) return true;

  const userDoc = await db.collection("users").doc(uid).get();
  const role = userDoc.exists ? userDoc.data().role : null;
  if (["admin", "editor", "triviaEditor", "newsEditor"].includes(role)) return true;

  throw new HttpsError("permission-denied", "Bu panel icin yetkiniz yok.");
}

async function assertBotAdmin(uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
  if (NEWS_ADMIN_UIDS.has(uid)) return true;

  const db = admin.firestore();
  const editorDoc = await db.collection("bot_editors").doc(uid).get();
  if (editorDoc.exists && editorDoc.data().active !== false) return true;

  const userDoc = await db.collection("users").doc(uid).get();
  const role = userDoc.exists ? userDoc.data().role : null;
  if (["admin", "botAdmin"].includes(role)) return true;

  throw new HttpsError("permission-denied", "Bu panel için yetkiniz yok.");
}

async function assertBlogEditor(uid, authToken = {}) {
  if (!uid) throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");

  const db = admin.firestore();
  const [editorDoc, userDoc] = await Promise.all([
    db.collection("blog_editors").doc(uid).get(),
    db.collection("users").doc(uid).get(),
  ]);
  const editor = editorDoc.exists ? editorDoc.data() || {} : {};
  const user = userDoc.exists ? userDoc.data() || {} : {};
  const role = cleanText(user.role, 40);
  const isManager = NEWS_ADMIN_UIDS.has(uid) ||
    role === "admin" || (editor.canManageAll === true && editor.active !== false);
  const isEditor = isManager ||
    (editorDoc.exists && editor.active !== false) ||
    (!editorDoc.exists && ["blogger", "blogEditor"].includes(role));

  if (!isEditor) {
    throw new HttpsError("permission-denied", "Bu hesap blogger olarak yetkilendirilmemiş.");
  }

  const tokenName = cleanText(authToken.name, 100);
  const tokenEmail = cleanText(authToken.email, 180);
  const username = cleanText(user.username || user.handle, 80).replace(/^@/, "");
  const displayName = cleanText(
    user.displayName || user.name || tokenName || username || tokenEmail.split("@")[0],
    100
  ) || "CineMatch Blogger";
  const photoUrl = cleanHttpsUrl(
    user.photoUrl || user.photoURL || user.profileImageUrl || authToken.picture,
    1400
  );

  return {
    canManageAll: isManager,
    profile: { uid, displayName, username, photoUrl },
  };
}

function cleanHttpsUrl(value, maxLength = 1400) {
  const candidate = cleanText(value, maxLength);
  if (!candidate) return "";
  try {
    const parsed = new URL(candidate);
    return parsed.protocol === "https:" ? parsed.toString() : "";
  } catch (error) {
    return "";
  }
}

function sanitizeBlogContent(value) {
  const source = typeof value === "string" ? value.slice(0, 180000) : "";
  return sanitizeHtml(source, {
    allowedTags: [
      "p", "br", "h2", "h3", "strong", "b", "em", "i", "u", "s",
      "blockquote", "ul", "ol", "li", "a", "figure", "img", "figcaption", "hr",
    ],
    allowedAttributes: {
      a: ["href", "target", "rel"],
      img: ["src", "alt", "data-storage-path"],
    },
    allowedSchemes: ["https"],
    allowedSchemesByTag: { img: ["https"], a: ["https", "http"] },
    allowProtocolRelative: false,
    transformTags: {
      a: (tagName, attribs) => ({
        tagName,
        attribs: {
          href: cleanHttpsUrl(attribs.href, 1400),
          target: "_blank",
          rel: "noopener noreferrer nofollow",
        },
      }),
    },
    exclusiveFilter: (frame) => {
      if (frame.tag !== "img") return false;
      const src = cleanHttpsUrl(frame.attribs.src, 1800);
      return !src || ![
        "firebasestorage.googleapis.com",
        "storage.googleapis.com",
      ].includes(new URL(src).hostname);
    },
  }).trim();
}

function normalizeBlogMovies(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  return value.reduce((movies, raw) => {
    if (movies.length >= 10 || !raw || typeof raw !== "object") return movies;
    const tmdbId = Number(raw.tmdbId || raw.id);
    if (!Number.isInteger(tmdbId) || tmdbId <= 0 || seen.has(tmdbId)) return movies;
    seen.add(tmdbId);
    movies.push({
      tmdbId,
      title: cleanText(raw.title, 180) || `TMDB ${tmdbId}`,
      originalTitle: cleanText(raw.originalTitle, 180),
      year: Number.isInteger(Number(raw.year)) ? Number(raw.year) : null,
      posterPath: /^\/[A-Za-z0-9._/-]+$/.test(String(raw.posterPath || ""))
        ? String(raw.posterPath)
        : "",
      posterUrl: cleanHttpsUrl(raw.posterUrl, 1400),
    });
    return movies;
  }, []);
}

function normalizeBlogImages(value, postId) {
  if (!Array.isArray(value)) return [];
  return value.reduce((images, raw) => {
    if (images.length >= 30 || !raw || typeof raw !== "object") return images;
    const url = cleanHttpsUrl(raw.url, 1800);
    const path = cleanText(raw.path, 600);
    if (!url || !/^blog_images\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+\/[A-Za-z0-9_.-]+$/.test(path)) {
      return images;
    }
    if (path.split("/")[2] !== postId) return images;
    images.push({ url, path, alt: cleanText(raw.alt, 180) });
    return images;
  }, []);
}

function normalizeTriviaQuestion(data) {
  const question = cleanText(data.question, 500);
  if (!question) throw new HttpsError("invalid-argument", "Soru metni gerekli.");

  const options = Array.isArray(data.options)
    ? data.options.map((item) => cleanText(item, 180)).filter(Boolean).slice(0, 4)
    : [];
  if (options.length !== 4) {
    throw new HttpsError("invalid-argument", "Tam 4 sik gerekli.");
  }

  const correctIndex = Number(data.correctIndex);
  if (!Number.isInteger(correctIndex) || correctIndex < 0 || correctIndex > 3) {
    throw new HttpsError("invalid-argument", "Dogru sik 0-3 arasinda olmali.");
  }

  const weekId = cleanText(data.weekId, 16);
  if (!/^\d{4}_W\d{1,2}$/.test(weekId)) {
    throw new HttpsError("invalid-argument", "Hafta ID formati gecersiz. Ornek: 2026_W27");
  }

  const difficulty = ["kolay", "orta", "zor"].includes(data.difficulty)
    ? data.difficulty
    : "orta";

  return {
    question,
    options,
    correctIndex,
    weekId,
    difficulty,
    imageUrl: cleanText(data.imageUrl, 1200) || null,
    explanation: cleanText(data.explanation, 800),
    isActive: data.isActive !== false,
  };
}

async function countTriviaQuestionsForWeek(db, weekId, excludeId) {
  const snap = await db
    .collection("trivia_questions")
    .where("weekId", "==", weekId)
    .get();
  return snap.docs.filter((doc) => doc.id !== excludeId).length;
}

exports.isNewsAdmin = onCall(async (request) => {
  await assertNewsEditor(request.auth && request.auth.uid);
  return { ok: true };
});

exports.isTriviaAdmin = onCall(async (request) => {
  await assertTriviaEditor(request.auth && request.auth.uid);
  return { ok: true };
});

exports.isBotAdmin = onCall(async (request) => {
  await assertBotAdmin(request.auth && request.auth.uid);
  return { ok: true };
});

exports.isBlogEditor = onCall(async (request) => {
  const access = await assertBlogEditor(
    request.auth && request.auth.uid,
    request.auth && request.auth.token
  );
  return { ok: true, ...access };
});

// Kullanıcıların profil kataloglarına eklediği filmleri zaman damgalı olaylara
// dönüştürür. Watchlist bilinçli olarak kapsam dışıdır; henüz izlenmemiş filmdir.
// Bu tetikleyici sayesinde haftalık rapor bütün users dokümanlarını taramaz.
exports.trackProfileMovieCatalogAdditions = functions.firestore
  .document("users/{uid}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const fields = {
      watchedKeys: "watched",
    };
    const writes = [];
    Object.entries(fields).forEach(([field, catalogType]) => {
      const previous = new Set(
        (Array.isArray(before[field]) ? before[field] : [])
          .map((value) => String(value).trim())
          .filter(Boolean)
      );
      const current = (Array.isArray(after[field]) ? after[field] : [])
        .map((value) => String(value).trim())
        .filter(Boolean);
      current.forEach((movieKey) => {
        if (previous.has(movieKey)) return;
        const fingerprint = crypto
          .createHash("sha1")
          .update(`${context.eventId}|${field}|${movieKey}`)
          .digest("hex");
        const ref = admin.firestore()
          .collection("profile_movie_events")
          .doc(fingerprint);
        writes.push(ref.set({
          userId: context.params.uid,
          movieKey,
          tmdbId: Number(movieKey) || null,
          catalogType,
          addedAt: admin.firestore.FieldValue.serverTimestamp(),
          sourceEventId: context.eventId,
        }));
      });
    });
    await Promise.all(writes);
    return null;
  });

// Admin tarafından elle üretilen haftalık Instagram raporu. Haftalar pazartesi
// 00:00 (Europe/Istanbul) başlangıçlıdır. İstemci yalnızca hazır veriyi çizer;
// sıralama ve yetki kontrolü güvenilir sunucu tarafında yapılır.
exports.generateWeeklySocialReport = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const rawEnd = request.data && request.data.weekEnd;
  const end = rawEnd ? new Date(rawEnd) : new Date();
  if (Number.isNaN(end.getTime())) {
    throw new HttpsError("invalid-argument", "Hafta tarihi geçersiz.");
  }

  // JS Date UTC çalışır. İstanbul pazartesi başlangıcını UTC'ye çeviriyoruz.
  const istanbulNow = new Date(end.getTime() + (3 * 60 * 60 * 1000));
  const day = istanbulNow.getUTCDay() || 7;
  istanbulNow.setUTCDate(istanbulNow.getUTCDate() - day + 1);
  istanbulNow.setUTCHours(0, 0, 0, 0);
  const start = new Date(istanbulNow.getTime() - (3 * 60 * 60 * 1000));
  const finish = new Date(start.getTime() + (7 * 24 * 60 * 60 * 1000));

  const db = admin.firestore();
  const additions = await db
    .collection("profile_movie_events")
    .where("addedAt", ">=", admin.firestore.Timestamp.fromDate(start))
    .where("addedAt", "<", admin.firestore.Timestamp.fromDate(finish))
    .get();
  const additionDocs = additions.docs;

  // Yalnızca gerçekten izlenen filmleri say. Uygulama aynı filmi hem katalog
  // anahtarı hem TMDB anahtarıyla watchedKeys'e ekleyebildiği için önce merkezi
  // katalog üzerinden tek bir kimliğe indirgeriz. Aynı kullanıcı/film çifti
  // haftada yalnızca bir kez sayılır.
  const watchedItems = additionDocs
    .map((doc) => doc.data() || {})
    .filter((item) => item.catalogType === "watched");
  const catalogCache = new Map();
  async function resolveCatalog(rawKey, rawTmdbId) {
    const key = String(rawKey || "").trim();
    const embeddedTmdb = /^tmdb:(\d+)$/.exec(key);
    const numericTmdb = Number(rawTmdbId) ||
      (embeddedTmdb ? Number(embeddedTmdb[1]) : Number(key)) || null;
    const cacheKey = `${key}|${numericTmdb || ""}`;
    if (catalogCache.has(cacheKey)) return catalogCache.get(cacheKey);

    let catalogDoc = key
      ? await db.collection("catalog_films").doc(key).get()
      : null;
    if ((!catalogDoc || !catalogDoc.exists) && numericTmdb) {
      const snap = await db.collection("catalog_films")
        .where("tmdbId", "==", numericTmdb).limit(1).get();
      catalogDoc = snap.empty ? null : snap.docs[0];
    }
    const data = catalogDoc && catalogDoc.exists ? catalogDoc.data() || {} : {};
    const tmdbId = Number(data.tmdbId) || numericTmdb;
    const resolved = {
      id: tmdbId ? `tmdb:${tmdbId}` : (catalogDoc && catalogDoc.exists ? catalogDoc.id : key),
      tmdbId: tmdbId || null,
      title: cleanText(data.title, 140) || key,
      year: Number(data.year) || null,
      posterUrl: cleanText(data.posterUrl, 1200),
    };
    catalogCache.set(cacheKey, resolved);
    return resolved;
  }

  const resolvedItems = await Promise.all(watchedItems.map(async (item) => ({
    userId: String(item.userId || ""),
    movie: await resolveCatalog(item.movieKey, item.tmdbId),
  })));
  const counts = new Map();
  resolvedItems.forEach(({ userId, movie }) => {
    if (!movie.id) return;
    const current = counts.get(movie.id) || {
      ...movie,
      viewers: new Set(),
    };
    current.viewers.add(userId || `anonymous:${current.viewers.size}`);
    counts.set(movie.id, current);
  });

  const movies = [...counts.values()]
    .map(({ viewers, ...movie }) => ({ ...movie, additions: viewers.size }))
    .sort((a, b) => b.additions - a.additions || a.title.localeCompare(b.title, "tr"))
    .slice(0, 10);

  const weekId = start.toISOString().slice(0, 10);
  const payload = {
    weekId,
    startAt: admin.firestore.Timestamp.fromDate(start),
    endAt: admin.firestore.Timestamp.fromDate(finish),
    totalAdditions: movies.reduce((sum, movie) => sum + movie.additions, 0),
    movies,
    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    generatedBy: uid,
  };
  await db.collection("weekly_social_reports").doc(weekId).set(payload, { merge: true });

  return {
    ok: true,
    weekId,
    startAt: start.toISOString(),
    endAt: finish.toISOString(),
    totalAdditions: movies.reduce((sum, movie) => sum + movie.additions, 0),
    movies,
  };
});

// Admin sosyal medya stüdyosundaki film ızgarası ve puan sıralaması için TMDB
// detaylarını tek istekte hazırlar. İstemci ayrı ayrı TMDB çağrısı yapmaz.
exports.getSocialGridMovies = onCall(
  { secrets: ["TMDB_ACCESS_TOKEN"] },
  async (request) => {
    await assertNewsEditor(request.auth && request.auth.uid);
    const rawIds = Array.isArray(request.data && request.data.ids)
      ? request.data.ids
      : [];
    const ids = [...new Set(
      rawIds
        .map((value) => Number(value))
        .filter((value) => Number.isInteger(value) && value > 0)
    )];
    if (!ids.length) {
      throw new HttpsError("invalid-argument", "En az bir geçerli TMDB film linki gerekli.");
    }
    if (ids.length > 36) {
      throw new HttpsError("invalid-argument", "Tek görselde en fazla 36 film kullanılabilir.");
    }

    const token = process.env.TMDB_ACCESS_TOKEN;
    const results = await Promise.all(ids.map(async (id) => {
      try {
        const response = await axios.get(`https://api.themoviedb.org/3/movie/${id}`, {
          params: { language: "en-US" },
          headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
        });
        const movie = response.data || {};
        const displayTitle = movie.original_language === "tr"
          ? movie.original_title
          : movie.title;
        return {
          id,
          title: cleanText(displayTitle || movie.original_title, 160) || `TMDB ${id}`,
          year: /^\d{4}/.test(String(movie.release_date || ""))
            ? Number(String(movie.release_date).slice(0, 4))
            : null,
          posterUrl: movie.poster_path
            ? `https://image.tmdb.org/t/p/w500${movie.poster_path}`
            : "",
          heroPosterUrl: movie.poster_path
            ? `https://image.tmdb.org/t/p/w780${movie.poster_path}`
            : "",
          voteAverage: Number.isFinite(Number(movie.vote_average))
            ? Number(Number(movie.vote_average).toFixed(1))
            : 0,
        };
      } catch (error) {
        console.error("Sosyal grid TMDB hatası:", id, error.message);
        return null;
      }
    }));

    return {
      movies: results.filter(Boolean),
      missingIds: ids.filter((id, index) => !results[index]),
    };
  }
);

// ==================================================================
// BOT ADMIN PANELİ ERİŞİMİ
// CineBot AI (cinematchbotai) backend'i Firebase dışında (Render'da
// SQLite ile) çalıştığı için oradaki veriye Firestore üzerinden değil,
// doğrudan REST üzerinden erişilir. Panel, bu backend'in admin uçlarını
// (/api/admin/...) çağırmak için gereken base URL + gizli anahtarı
// SADECE yetkili admin kullanıcılara, giriş yaptıktan sonra bu callable
// üzerinden verir -- anahtar hiçbir zaman istemci kaynak koduna gömülmez.
// Gerekli secret'lar: BOTAI_API_BASE, BOTAI_ADMIN_KEY
// (firebase functions:secrets:set BOTAI_API_BASE / BOTAI_ADMIN_KEY)
// ==================================================================
exports.getBotAdminAccess = onCall(
  { secrets: ["BOTAI_API_BASE", "BOTAI_ADMIN_KEY"] },
  async (request) => {
    await assertBotAdmin(request.auth && request.auth.uid);

    const baseUrl = process.env.BOTAI_API_BASE;
    const key = process.env.BOTAI_ADMIN_KEY;
    if (!baseUrl || !key) {
      throw new HttpsError(
        "failed-precondition",
        "Bot admin paneli için sunucu tarafında BOTAI_API_BASE / BOTAI_ADMIN_KEY tanımlı değil."
      );
    }

    return { baseUrl, key };
  }
);

function blogTimestampMillis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : null;
}

function serializeBlogPost(id, data, includeContent = false) {
  const serialized = {
    id,
    title: cleanText(data.title, 180),
    slug: cleanText(data.slug, 120),
    excerpt: cleanText(data.excerpt, 360),
    category: cleanText(data.category, 40),
    tags: Array.isArray(data.tags) ? data.tags : [],
    movies: Array.isArray(data.movies) ? data.movies : [],
    coverImageUrl: cleanHttpsUrl(data.coverImageUrl, 1800),
    status: ["draft", "published", "archived"].includes(data.status)
      ? data.status
      : "draft",
    authorId: cleanText(data.authorId, 128),
    authorName: cleanText(data.authorName, 100),
    authorUsername: cleanText(data.authorUsername, 80),
    authorPhotoUrl: cleanHttpsUrl(data.authorPhotoUrl, 1400),
    readingMinutes: Number(data.readingMinutes) || 0,
    revision: Number(data.revision) || 0,
    createdAtMs: blogTimestampMillis(data.createdAt),
    updatedAtMs: blogTimestampMillis(data.updatedAt),
    publishedAtMs: blogTimestampMillis(data.publishedAt),
  };
  if (includeContent) {
    serialized.contentHtml = typeof data.contentHtml === "string" ? data.contentHtml : "";
    serialized.images = Array.isArray(data.images) ? data.images : [];
  }
  return serialized;
}

exports.listBlogPosts = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  const access = await assertBlogEditor(uid, request.auth && request.auth.token);
  const requestedLimit = Number(request.data && request.data.limit);
  const limit = Number.isInteger(requestedLimit)
    ? Math.min(100, Math.max(10, requestedLimit))
    : 30;
  const db = admin.firestore();
  let docs;
  let hasMore;
  if (access.canManageAll) {
    const snapshot = await db.collection("blog_posts")
      .orderBy("updatedAt", "desc")
      .limit(limit + 1)
      .get();
    hasMore = snapshot.docs.length > limit;
    docs = snapshot.docs.slice(0, limit);
  } else {
    const snapshot = await db.collection("blog_posts")
      .where("authorId", "==", uid)
      .get();
    const sortedDocs = snapshot.docs
      .sort((left, right) => {
        const leftMs = blogTimestampMillis(left.data().updatedAt) || 0;
        const rightMs = blogTimestampMillis(right.data().updatedAt) || 0;
        return rightMs - leftMs;
      });
    hasMore = sortedDocs.length > limit;
    docs = sortedDocs.slice(0, limit);
  }
  return {
    posts: docs.map((doc) => serializeBlogPost(doc.id, doc.data() || {})),
    hasMore,
  };
});

exports.getBlogPost = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  const access = await assertBlogEditor(uid, request.auth && request.auth.token);
  const id = cleanText(request.data && request.data.id, 120);
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError("invalid-argument", "Blog yazısı kimliği geçersiz.");
  }
  const snap = await admin.firestore().collection("blog_posts").doc(id).get();
  if (!snap.exists) throw new HttpsError("not-found", "Blog yazısı bulunamadı.");
  const post = snap.data() || {};
  if (post.authorId !== uid && !access.canManageAll) {
    throw new HttpsError("permission-denied", "Bu blog yazısını görüntüleyemezsiniz.");
  }
  return { post: serializeBlogPost(snap.id, post, true) };
});

async function assertBlogManager(request) {
  const access = await assertBlogEditor(
    request.auth && request.auth.uid,
    request.auth && request.auth.token
  );
  if (!access.canManageAll) {
    throw new HttpsError("permission-denied", "Blogger yetkilerini yalnızca yöneticiler değiştirebilir.");
  }
  return access;
}

function serializeBloggerCandidate(doc, activeEditorIds = new Set(), blockedEditorIds = new Set()) {
  const data = doc.data() || {};
  const username = cleanText(data.username || data.handle, 80).replace(/^@/, "");
  return {
    uid: doc.id,
    displayName: cleanText(data.displayName || data.name || username, 100) || "CineMatch Kullanıcısı",
    username,
    photoUrl: cleanHttpsUrl(data.photoUrl || data.photoURL || data.profileImageUrl, 1400),
    isBlogEditor: activeEditorIds.has(doc.id) ||
      (!blockedEditorIds.has(doc.id) && ["admin", "blogger", "blogEditor"].includes(data.role)),
  };
}

exports.searchBlogUsers = onCall(async (request) => {
  await assertBlogManager(request);
  const rawQuery = cleanText(request.data && request.data.query, 100).replace(/^@/, "");
  const query = rawQuery.toLocaleLowerCase("tr-TR");
  if (query.length < 2) {
    throw new HttpsError("invalid-argument", "Kullanıcı araması en az 2 karakter olmalı.");
  }

  const db = admin.firestore();
  const lookups = ["username_lc", "displayName_lc"].map((field) =>
    db.collection("users")
      .orderBy(field)
      .startAt(query)
      .endAt(`${query}\uf8ff`)
      .limit(8)
      .get()
  );
  if (/^[A-Za-z0-9_-]{20,128}$/.test(rawQuery)) {
    lookups.push(db.collection("users").where(admin.firestore.FieldPath.documentId(), "==", rawQuery).get());
  }
  const snapshots = await Promise.all(lookups);
  const usersById = new Map();
  snapshots.forEach((snapshot) => snapshot.docs.forEach((doc) => usersById.set(doc.id, doc)));
  const userDocs = [...usersById.values()].slice(0, 12);
  const editorDocs = await Promise.all(
    userDocs.map((doc) => db.collection("blog_editors").doc(doc.id).get())
  );
  const activeIds = new Set(
    editorDocs.filter((doc) => doc.exists && doc.data().active !== false).map((doc) => doc.id)
  );
  const blockedIds = new Set(
    editorDocs.filter((doc) => doc.exists && doc.data().active === false).map((doc) => doc.id)
  );
  return {
    users: userDocs.map((doc) => serializeBloggerCandidate(doc, activeIds, blockedIds)),
  };
});

exports.listBlogEditors = onCall(async (request) => {
  await assertBlogManager(request);
  const db = admin.firestore();
  const [editorSnapshot, roleSnapshot] = await Promise.all([
    db.collection("blog_editors").limit(100).get(),
    db.collection("users").where("role", "in", ["blogger", "blogEditor"]).limit(100).get(),
  ]);
  const activeDocs = editorSnapshot.docs.filter((doc) => doc.data().active !== false);
  const blockedIds = new Set(
    editorSnapshot.docs.filter((doc) => doc.data().active === false).map((doc) => doc.id)
  );
  const userIds = new Set(activeDocs.map((doc) => doc.id));
  roleSnapshot.docs.forEach((doc) => {
    if (!blockedIds.has(doc.id)) userIds.add(doc.id);
  });
  const userDocs = await Promise.all(
    [...userIds].map((uid) => db.collection("users").doc(uid).get())
  );
  const users = userDocs
    .filter((doc) => doc.exists)
    .map((doc) => serializeBloggerCandidate(doc, userIds))
    .sort((left, right) => left.displayName.localeCompare(right.displayName, "tr"));
  return { users };
});

exports.setBlogEditor = onCall(async (request) => {
  await assertBlogManager(request);
  const uid = cleanText(request.data && request.data.uid, 128);
  const active = request.data && request.data.active === true;
  if (!/^[A-Za-z0-9_-]{20,128}$/.test(uid)) {
    throw new HttpsError("invalid-argument", "Kullanıcı kimliği geçersiz.");
  }
  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "CineMatch kullanıcısı bulunamadı.");
  await db.collection("blog_editors").doc(uid).set({
    active,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: request.auth.uid,
  }, { merge: true });
  return { ok: true, uid, active };
});

exports.searchBlogMovies = onCall(
  { secrets: ["TMDB_ACCESS_TOKEN"] },
  async (request) => {
    await assertBlogEditor(
      request.auth && request.auth.uid,
      request.auth && request.auth.token
    );
    const query = cleanText(request.data && request.data.query, 120);
    if (query.length < 2) {
      throw new HttpsError("invalid-argument", "Film araması en az 2 karakter olmalı.");
    }

    try {
      const response = await axios.get("https://api.themoviedb.org/3/search/movie", {
        params: {
          query,
          language: "tr-TR",
          page: "1",
          include_adult: "false",
        },
        headers: {
          Authorization: `Bearer ${process.env.TMDB_ACCESS_TOKEN}`,
          Accept: "application/json",
        },
      });
      const results = Array.isArray(response.data && response.data.results)
        ? response.data.results
        : [];
      return {
        movies: results.slice(0, 12).map((movie) => ({
          tmdbId: Number(movie.id),
          title: cleanText(movie.title || movie.original_title, 180),
          originalTitle: cleanText(movie.original_title, 180),
          year: /^\d{4}/.test(String(movie.release_date || ""))
            ? Number(String(movie.release_date).slice(0, 4))
            : null,
          posterPath: /^\/[A-Za-z0-9._/-]+$/.test(String(movie.poster_path || ""))
            ? String(movie.poster_path)
            : "",
          posterUrl: movie.poster_path
            ? `https://image.tmdb.org/t/p/w342${movie.poster_path}`
            : "",
        })).filter((movie) => Number.isInteger(movie.tmdbId) && movie.tmdbId > 0),
      };
    } catch (error) {
      console.error("Blog TMDB arama hatası:", error.message);
      throw new HttpsError("internal", "TMDB film araması şu anda tamamlanamadı.");
    }
  }
);

exports.saveBlogPost = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  const access = await assertBlogEditor(uid, request.auth && request.auth.token);
  const data = request.data || {};
  const title = cleanText(data.title, 180);
  const status = ["draft", "published", "archived"].includes(data.status)
    ? data.status
    : "draft";
  const postId = cleanText(data.id, 120);
  if (!title) throw new HttpsError("invalid-argument", "Yazı başlığı gerekli.");
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(postId)) {
    throw new HttpsError("invalid-argument", "Blog yazısı kimliği geçersiz.");
  }

  const contentHtml = sanitizeBlogContent(data.contentHtml);
  const contentText = sanitizeHtml(contentHtml, {
    allowedTags: [],
    allowedAttributes: {},
  }).replace(/\s+/g, " ").trim().slice(0, 120000);
  if (status === "published" && contentText.length < 20) {
    throw new HttpsError(
      "invalid-argument",
      "Yayınlamak için en az 20 karakterlik bir yazı içeriği gerekli."
    );
  }

  const db = admin.firestore();
  const ref = db.collection("blog_posts").doc(postId);
  const existingSnap = await ref.get();
  const existing = existingSnap.exists ? existingSnap.data() || {} : {};
  if (existingSnap.exists && existing.authorId !== uid && !access.canManageAll) {
    throw new HttpsError("permission-denied", "Yalnızca kendi blog yazılarınızı düzenleyebilirsiniz.");
  }

  const editingAnotherAuthor = existingSnap.exists && existing.authorId !== uid;
  const author = editingAnotherAuthor
    ? {
        uid: existing.authorId,
        displayName: cleanText(existing.authorName, 100) || "CineMatch Blogger",
        username: cleanText(existing.authorUsername, 80),
        photoUrl: cleanHttpsUrl(existing.authorPhotoUrl, 1400),
      }
    : access.profile;
  const now = admin.firestore.FieldValue.serverTimestamp();
  const slug = makeSlug(data.slug || title) || postId;
  const tags = Array.isArray(data.tags)
    ? [...new Set(data.tags.map((tag) => cleanText(tag, 40)).filter(Boolean))].slice(0, 12)
    : [];
  const movies = normalizeBlogMovies(data.movies);
  const images = normalizeBlogImages(data.images, postId);
  const activeImagePaths = new Set(images.map((image) => image.path));
  const removedImagePaths = Array.isArray(existing.images)
    ? existing.images
      .map((image) => cleanText(image && image.path, 600))
      .filter((path) => (
        /^blog_images\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+\/[A-Za-z0-9_.-]+$/.test(path) &&
        path.split("/")[2] === postId &&
        !activeImagePaths.has(path)
      ))
    : [];
  const excerpt = cleanText(data.excerpt, 360) || contentText.slice(0, 220);
  const coverImageUrl = cleanHttpsUrl(data.coverImageUrl, 1800) ||
    (images[0] ? images[0].url : "");
  const category = cleanText(data.category, 40) || "İnceleme";
  const readingMinutes = contentText
    ? Math.max(1, Math.ceil(contentText.split(/\s+/).length / 220))
    : 0;

  const payload = {
    schemaVersion: 1,
    title,
    slug,
    excerpt,
    contentHtml,
    contentText,
    category,
    tags,
    movies,
    tmdbIds: movies.map((movie) => movie.tmdbId),
    images,
    coverImageUrl,
    status,
    readingMinutes,
    authorId: author.uid,
    authorName: author.displayName,
    authorUsername: author.username,
    authorPhotoUrl: author.photoUrl,
    updatedAt: now,
    updatedBy: uid,
    updatedByName: access.profile.displayName,
    revision: admin.firestore.FieldValue.increment(1),
  };
  if (!existingSnap.exists) payload.createdAt = now;
  if (status === "published" && !existing.publishedAt) payload.publishedAt = now;

  const publicPayload = {
    schemaVersion: 1,
    title,
    slug,
    excerpt,
    contentHtml,
    contentText,
    category,
    tags,
    movies,
    tmdbIds: payload.tmdbIds,
    images,
    coverImageUrl,
    readingMinutes,
    authorId: author.uid,
    authorName: author.displayName,
    authorUsername: author.username,
    authorPhotoUrl: author.photoUrl,
    publishedAt: existing.publishedAt || now,
    updatedAt: now,
  };

  const batch = db.batch();
  batch.set(ref, payload, { merge: true });
  const publicRef = db.collection("public_blog_posts").doc(postId);
  if (status === "published") {
    batch.set(publicRef, publicPayload, { merge: true });
  } else {
    batch.delete(publicRef);
  }
  await batch.commit();
  if (removedImagePaths.length) {
    const bucket = admin.storage().bucket();
    const cleanupResults = await Promise.allSettled(
      removedImagePaths.map((path) => bucket.file(path).delete({ ignoreNotFound: true }))
    );
    cleanupResults.forEach((result, index) => {
      if (result.status === "rejected") {
        console.error("Kullanılmayan blog görseli silinemedi:", removedImagePaths[index], result.reason);
      }
    });
  }
  return { ok: true, id: postId, slug, status };
});

exports.deleteBlogPost = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  const access = await assertBlogEditor(uid, request.auth && request.auth.token);
  const id = cleanText(request.data && request.data.id, 120);
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError("invalid-argument", "Blog yazısı kimliği geçersiz.");
  }

  const db = admin.firestore();
  const ref = db.collection("blog_posts").doc(id);
  const snap = await ref.get();
  if (!snap.exists) return { ok: true };
  const post = snap.data() || {};
  if (post.authorId !== uid && !access.canManageAll) {
    throw new HttpsError("permission-denied", "Yalnızca kendi blog yazılarınızı silebilirsiniz.");
  }

  const batch = db.batch();
  batch.delete(ref);
  batch.delete(db.collection("public_blog_posts").doc(id));
  await batch.commit();

  const bucket = admin.storage().bucket();
  const storedPaths = Array.isArray(post.images)
    ? post.images.map((image) => cleanText(image && image.path, 600))
      .filter((path) => path.startsWith("blog_images/") && path.split("/").includes(id))
    : [];
  await Promise.allSettled([
    bucket.deleteFiles({ prefix: `blog_images/${post.authorId}/${id}/` }),
    ...storedPaths.map((path) => bucket.file(path).delete({ ignoreNotFound: true })),
  ]);
  return { ok: true };
});

exports.saveNewsArticle = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const data = request.data || {};
  const title = cleanText(data.title, 180);
  const body = cleanText(data.body, 50000);
  const status = ["draft", "published", "archived"].includes(data.status)
    ? data.status
    : "draft";

  if (!title) throw new HttpsError("invalid-argument", "Başlık gerekli.");
  if (status === "published" && !body) {
    throw new HttpsError("invalid-argument", "Yayınlamak için haber metni gerekli.");
  }

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const articleId = cleanText(data.id, 120) || db.collection("news_articles").doc().id;
  const slug = makeSlug(data.slug || title) || articleId;
  const tags = Array.isArray(data.tags)
    ? data.tags.map((tag) => cleanText(tag, 40)).filter(Boolean).slice(0, 12)
    : [];

  const payload = {
    title,
    slug,
    summary: cleanText(data.summary, 320),
    body,
    category: cleanText(data.category, 40) || "Haber",
    movieTitle: cleanText(data.movieTitle, 120),
    imageUrl: cleanText(data.imageUrl, 1200),
    sourceUrl: cleanText(data.sourceUrl, 1200),
    tags,
    status,
    updatedAt: now,
    updatedBy: uid,
  };

  const ref = db.collection("news_articles").doc(articleId);
  const snap = await ref.get();
  if (!snap.exists) {
    payload.createdAt = now;
    payload.authorId = uid;
    payload.authorName = cleanText(data.authorName, 80) || "CineMatch Editör";
  }
  if (status === "published" && !snap.data()?.publishedAt) {
    payload.publishedAt = now;
  }

  await ref.set(payload, { merge: true });
  if (status === "published") {
    const publicPayload = {
      title: payload.title,
      slug: payload.slug,
      summary: payload.summary,
      body: payload.body,
      category: payload.category,
      movieTitle: payload.movieTitle,
      imageUrl: payload.imageUrl,
      sourceUrl: payload.sourceUrl,
      tags: payload.tags,
      authorName: payload.authorName || snap.data()?.authorName || "CineMatch Editör",
      publishedAt: payload.publishedAt || snap.data()?.publishedAt || now,
      updatedAt: now,
    };
    await db.collection("public_news").doc(articleId).set(publicPayload, { merge: true });
  } else {
    await db.collection("public_news").doc(articleId).delete().catch(() => null);
  }
  return { ok: true, id: articleId, slug };
});

exports.deleteNewsArticle = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const id = cleanText(request.data && request.data.id, 120);
  if (!id) throw new HttpsError("invalid-argument", "Haber ID gerekli.");

  await admin.firestore().collection("news_articles").doc(id).delete();
  await admin.firestore().collection("public_news").doc(id).delete().catch(() => null);
  return { ok: true };
});

exports.getAnnouncement = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const doc = await admin.firestore().collection("system").doc("announcement").get();
  return { announcement: doc.exists ? doc.data() : null };
});

exports.saveAnnouncement = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const data = request.data || {};
  const title = cleanText(data.title, 160);
  const message = cleanText(data.message, 3000);
  const imageUrl = cleanText(data.imageUrl, 1200);
  const isActive = data.isActive === true;

  if (isActive && (!title || !message)) {
    throw new HttpsError("invalid-argument", "Aktif duyuru icin baslik ve mesaj gerekli.");
  }

  const db = admin.firestore();
  const ref = db.collection("system").doc("announcement");
  const snap = await ref.get();
  const previous = snap.exists ? snap.data() : {};
  const previousItems = Array.isArray(previous.items) ? previous.items : [];
  const id = cleanText(data.id, 120) || `announcement_${Date.now()}`;
  const now = admin.firestore.FieldValue.serverTimestamp();

  let items = previousItems;
  if (title || message) {
    const item = {
      id,
      title,
      message,
      imageUrl,
      date: admin.firestore.Timestamp.now(),
      updatedBy: uid,
    };

    items = [
      item,
      ...previousItems.filter((entry) => entry && entry.id !== id),
    ].slice(0, 30);
  }

  await ref.set({
    id,
    title,
    message,
    imageUrl,
    isActive,
    items,
    updatedAt: now,
    updatedBy: uid,
  }, { merge: true });

  return { ok: true, id };
});

exports.saveTriviaQuestion = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertTriviaEditor(uid);

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const data = normalizeTriviaQuestion(request.data || {});
  const questionId = cleanText(request.data && request.data.id, 120) ||
    db.collection("trivia_questions").doc().id;

  const count = await countTriviaQuestionsForWeek(db, data.weekId, questionId);
  if (count >= 10) {
    throw new HttpsError("failed-precondition", `${data.weekId} haftasi icin 10 soru siniri dolu.`);
  }

  const ref = db.collection("trivia_questions").doc(questionId);
  const snap = await ref.get();
  const payload = {
    ...data,
    updatedAt: now,
    updatedBy: uid,
  };
  if (!snap.exists) {
    payload.createdAt = now;
    payload.createdBy = uid;
  }

  await ref.set(payload, { merge: true });
  return { ok: true, id: questionId };
});

exports.deleteTriviaQuestion = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertTriviaEditor(uid);

  const id = cleanText(request.data && request.data.id, 120);
  if (!id) throw new HttpsError("invalid-argument", "Soru ID gerekli.");

  await admin.firestore().collection("trivia_questions").doc(id).delete();
  return { ok: true };
});

exports.bulkSaveTriviaQuestions = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertTriviaEditor(uid);

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const items = Array.isArray(request.data && request.data.questions)
    ? request.data.questions
    : [];
  if (!items.length) {
    throw new HttpsError("invalid-argument", "Yuklenecek soru bulunamadi.");
  }
  if (items.length > 10) {
    throw new HttpsError("invalid-argument", "Tek seferde en fazla 10 soru yuklenebilir.");
  }

  const normalized = items.map((item) => normalizeTriviaQuestion(item));
  const weekIds = [...new Set(normalized.map((item) => item.weekId))];
  if (weekIds.length !== 1) {
    throw new HttpsError("invalid-argument", "Toplu yuklemede tum sorular ayni weekId icin olmali.");
  }

  const weekId = weekIds[0];
  const count = await countTriviaQuestionsForWeek(db, weekId);
  if (count + normalized.length > 10) {
    throw new HttpsError("failed-precondition", `${weekId} haftasi 10 soru sinirini asiyor.`);
  }

  const batch = db.batch();
  const ids = [];
  normalized.forEach((item) => {
    const ref = db.collection("trivia_questions").doc();
    ids.push(ref.id);
    batch.set(ref, {
      ...item,
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
      updatedBy: uid,
    });
  });

  await batch.commit();
  return { ok: true, ids };
});

// ==================================================================
// 1. GENEL TMDB PROXY (V2)
// ==================================================================
exports.callTMDB = onCall({ secrets: ["TMDB_ACCESS_TOKEN"] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Oturum açmanız gerekiyor.');
  const { endpoint, params } = request.data;
  const token = process.env.TMDB_ACCESS_TOKEN;
  if (!endpoint) throw new HttpsError('invalid-argument', 'Endpoint gerekli.');

  try {
    const response = await axios.get(`https://api.themoviedb.org${endpoint}`, {
      params: { ...params, language: params && params.language ? params.language : 'tr-TR' },
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' }
    });
    return response.data;
  } catch (error) {
    console.error("TMDB Proxy Hatası:", endpoint, error.message);
    throw new HttpsError('internal', 'TMDB isteği başarısız oldu.');
  }
});

// ==================================================================
// 2. SEARCH MOVIES (V2)
// ==================================================================
exports.searchMovies = onCall({ secrets: ["TMDB_ACCESS_TOKEN"] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş yapmalısın.');
  const query = request.data.query;
  const page = request.data.page || 1;
  const token = process.env.TMDB_ACCESS_TOKEN;

  try {
    const response = await axios.get(`https://api.themoviedb.org/3/search/movie`, {
      params: { query: query, language: 'tr-TR', page: page.toString(), include_adult: 'false' },
      headers: { Authorization: `Bearer ${token}` }
    });
    return response.data;
  } catch (error) {
    console.error("Search hatası:", error);
    throw new HttpsError('internal', 'Arama hatası.');
  }
});

// ==================================================================
// 3. SOSYAL BİLDİRİMLER (V1 Trigger)
// ==================================================================
function pushString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  return String(value).slice(0, 900);
}

function pushTime(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value._seconds) return value._seconds * 1000;
  return 0;
}

function isInvalidFcmToken(error) {
  const code = error && error.code;
  return [
    "messaging/invalid-registration-token",
    "messaging/registration-token-not-registered",
    "messaging/invalid-argument",
  ].includes(code);
}

async function sendPushToUser(uid, message) {
  if (!uid) return null;

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();
  const userData = userDoc.data() || {};
  if (userData.notificationsEnabled === false) return null;

  const tokensSnap = await userRef.collection("fcmTokens").get();
  if (tokensSnap.empty) return null;

  const tokens = tokensSnap.docs.map((doc) => doc.id).filter(Boolean);
  if (!tokens.length) return null;

  const data = {};
  Object.entries(message.data || {}).forEach(([key, value]) => {
    data[key] = pushString(value);
  });

  const result = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: message.notification,
    data,
    android: {
      priority: "high",
      notification: {
        channelId: data.type === "chat" ? "cinematch_chat" : "cinematch_social",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  });

  const cleanup = [];
  result.responses.forEach((response, index) => {
    if (!response.success && isInvalidFcmToken(response.error)) {
      cleanup.push(tokensSnap.docs[index].ref.delete().catch(() => null));
    }
  });
  await Promise.all(cleanup);
  return result;
}

function buildSocialPush(uid, notificationId, data) {
  const type = pushString(data.type, "social");
  const actorName = pushString(data.actorName, "Bir kullanici") || "Bir kullanici";
  const preview = pushString(data.preview);
  let title = "CineMatch";
  let body = "Yeni bildirimin var.";

  if (type === "like") {
    title = "Yeni begeni";
    body = `${actorName} gonderini begendi`;
  } else if (type === "comment") {
    title = "Yeni yorum";
    body = preview ? `${actorName}: ${preview}` : `${actorName} gonderine yorum yapti`;
  } else if (type === "follow") {
    title = "Yeni takipci";
    body = `${actorName} seni takip etmeye basladi`;
  } else if (type === "club_request") {
    title = "Kulup istegi";
    body = `${actorName} kulubune katilmak istiyor`;
  }

  return {
    notification: { title, body },
    data: {
      type,
      route: type,
      notificationId,
      actorId: pushString(data.actorId),
      actorName,
      postId: pushString(data.postId),
      clubId: pushString(data.clubId),
      clubName: pushString(data.clubName),
      preview,
      recipientId: uid,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
  };
}

exports.sendPushOnUserNotification = functions.firestore
  .document("users/{uid}/notifications/{notificationId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;

    const uid = context.params.uid;
    const notificationId = context.params.notificationId;
    const before = change.before.exists ? (change.before.data() || {}) : {};
    const after = change.after.data() || {};

    if (after.actorId === uid) return null;
    if (after.read === true || after.isRead === true) return null;

    if (change.before.exists) {
      const beforeTime = pushTime(before.updatedAt || before.createdAt);
      const afterTime = pushTime(after.updatedAt || after.createdAt);
      if (beforeTime === afterTime) return null;
    }

    return sendPushToUser(uid, buildSocialPush(uid, notificationId, after));
  });

exports.createNotificationOnLike = functions.firestore
  .document("posts/{postId}/likes/{userId}")
  .onCreate(async (snapshot, context) => {
    const postId = context.params.postId;
    const actorId = context.params.userId;
    const postSnap = await admin.firestore().collection("posts").doc(postId).get();
    if (!postSnap.exists) return;
    const postData = postSnap.data();
    const authorId = postData.authorId;
    if (authorId === actorId) return;
    
    const actorSnap = await admin.firestore().collection("users").doc(actorId).get();
    const actorData = actorSnap.data() || {};
    const actorName = actorData.username || "Bir Kullanıcı";
    
    const querySnapshot = await admin.firestore()
      .collection("users").doc(authorId).collection("notifications")
      .where("type", "==", "like").where("postId", "==", postId).where("read", "==", false)
      .limit(1).get();

    if (!querySnapshot.empty) {
      const doc = querySnapshot.docs[0];
      await doc.ref.update({
        count: (doc.data().count || 1) + 1,
        actorName: actorName,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } else {
      await admin.firestore().collection("users").doc(authorId).collection("notifications").add({
        type: "like", actorId: actorId, actorName: actorName, postId: postId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(), read: false, count: 1,
        preview: `${actorName} gönderini beğendi.`
      });
    }
  });exports.removeNotificationOnUnlike = functions.firestore
  .document("posts/{postId}/likes/{userId}")
  .onDelete(async (snapshot, context) => {
    const postId = context.params.postId;
    
    // Post'un yazarını (authorId) bulmamız lazım
    const postSnap = await admin.firestore().collection("posts").doc(postId).get();
    if (!postSnap.exists) return;
    const authorId = postSnap.data().authorId;

    // Yazarın bildirimlerinde bu post için olan okunmamış beğeni bildirimini bul
    const querySnapshot = await admin.firestore()
      .collection("users").doc(authorId).collection("notifications")
      .where("type", "==", "like")
      .where("postId", "==", postId)
      .where("read", "==", false)
      .limit(1).get();

    if (!querySnapshot.empty) {
      const doc = querySnapshot.docs[0];
      const currentCount = doc.data().count || 1;
      
      if (currentCount > 1) {
        // Eğer bildirimde birden fazla kişinin beğenisi gruplanmışsa, sayacı 1 azalt
        await doc.ref.update({
          count: currentCount - 1
        });
      } else {
        // Eğer sadece 1 beğeni varsa ve o da geri alındıysa, bildirimi tamamen sil
        await doc.ref.delete();
      }
    }
  });

exports.createNotificationOnFollow = functions.firestore
  .document("users/{followerId}/following/{followedId}")
  .onCreate(async (snapshot, context) => {
    const followerId = context.params.followerId;
    const followedId = context.params.followedId;
    const followerSnap = await admin.firestore().collection("users").doc(followerId).get();
    const followerData = followerSnap.data() || {};
    await admin.firestore().collection("users").doc(followedId).collection("notifications")
      .doc(`${followerId}_follow`).set({
        type: "follow", actorId: followerId, actorName: followerData.username || "Bir Kullanıcı",
        createdAt: admin.firestore.FieldValue.serverTimestamp(), read: false,
      });
  });
// ==================================================================
// 4. SOHBET & MESAJ BİLDİRİMLERİ (Optimize Edilmiş V1)
// ==================================================================
exports.sendChatNotification = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const messageData = snapshot.data() || {};
    const authorId = messageData.authorId;
    const chatId = context.params.chatId;
    const messageId = context.params.messageId;

    if (!authorId) return null;

    const chatDoc = await admin.firestore().collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return null;

    const chatData = chatDoc.data() || {};
    const participants = Array.isArray(chatData.participants) ? chatData.participants : [];
    // Kendimiz hariç diğer katılımcıları bul
    const recipients = participants.filter((uid) => uid && uid !== authorId);
    if (!recipients.length) return null;

    const authorSnap = await admin.firestore().collection("users").doc(authorId).get();
    const authorData = authorSnap.data() || {};
    const actorName = authorData.displayName || authorData.username || authorData.name || "Bir kullanıcı";
    
    const preview = pushString(messageData.text, "Bir mesaj gönderdi.");
    const isGroup = chatData.isGroup === true;
    const groupName = pushString(chatData.name || chatData.groupName || "");
    const body = isGroup && groupName
      ? `${groupName}: ${preview}`
      : preview;

    await Promise.all(recipients.map(async (receiverId) => {
      const userDoc = await admin.firestore().collection("users").doc(receiverId).get();
      const userData = userDoc.data() || {};
      const mutedChats = Array.isArray(userData.mutedChats) ? userData.mutedChats : [];

      // KONTROL: Kullanıcı bu sohbeti sessize almış mı?
      if (mutedChats.includes(chatId)) return null;

      return sendPushToUser(receiverId, {
        notification: {
          title: pushString(actorName, "Yeni mesaj"),
          body,
        },
        data: {
          type: "chat",
          route: "chat",
          chatId,
          messageId,
          actorId: authorId,
          otherUid: authorId, // İstemci tarafında yönlendirme için
          actorName,
          preview,
          isGroup: isGroup ? "true" : "false",
          groupName,
          recipientId: receiverId,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
      });
    }));

    return null;
  });

exports.aggregateUnreadCounts = functions.firestore
  .document("chats/{chatId}")
  .onUpdate(async (change) => {
    const newData = change.after.data();
    const oldData = change.before.data();
    const newCounts = newData.unreadCounts || {};
    const oldCounts = oldData.unreadCounts || {};
    if (JSON.stringify(newCounts) === JSON.stringify(oldCounts)) return;
    
    for (const uid of (newData.participants || [])) {
      const diff = (newCounts[uid] || 0) - (oldCounts[uid] || 0);
      if (diff !== 0) {
        await admin.firestore().collection("users").doc(uid).set({
          totalUnreadCount: admin.firestore.FieldValue.increment(diff)
        }, { merge: true });
      }
    }
  });

exports.findMatchesCallable = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Giriş gerekli.');
  const db = admin.firestore();
  const meSnap = await db.collection('users').doc(context.auth.uid).get();
  if (!meSnap.exists) return { results: [] };
  const myData = meSnap.data();
  function listOf(field) {
    return Array.isArray(myData[field])
      ? myData[field].map((item) => String(item).trim()).filter(Boolean)
      : [];
  }

  function sampleKeys(values, max = 10) {
    const unique = [...new Set(values)].filter(Boolean);
    return unique.sort(() => Math.random() - 0.5).slice(0, max);
  }

  const candidates = new Map();
  async function runArrayQuery(field, keys) {
    const queryKeys = sampleKeys(keys, 10);
    if (!queryKeys.length) return;
    try {
      const snap = await db
        .collection('users')
        .where(field, 'array-contains-any', queryKeys)
        .limit(45)
        .get();
      snap.docs.forEach((doc) => {
        if (doc.id === context.auth.uid) return;
        const userData = doc.data() || {};
        if (!String(userData.username || '').trim()) return;
        candidates.set(doc.id, { uid: doc.id, ...userData });
      });
    } catch (e) {
      console.log('findMatchesCallable query skipped', field, e.message);
    }
  }

  const five = listOf('fiveStarKeys');
  const favs = listOf('favoritesKeys');
  const watch = listOf('watchlistKeys');
  const genres = listOf('favGenres').map((item) => item.toLowerCase());
  const directors = listOf('favDirectors').map((item) => item.toLowerCase());
  const actors = listOf('favActors').map((item) => item.toLowerCase());

  await Promise.all([
    runArrayQuery('fiveStarKeys', [...five, ...favs]),
    runArrayQuery('favoritesKeys', [...favs, ...five]),
    runArrayQuery('watchlistKeys', watch),
    runArrayQuery('favGenres', genres),
    runArrayQuery('favDirectors', directors),
    runArrayQuery('favActors', actors),
  ]);

  if (candidates.size < 8) {
    try {
      const discovery = await db
        .collection('users')
        .orderBy('totalMovies', 'desc')
        .limit(35)
        .get();
      discovery.docs.forEach((doc) => {
        if (doc.id === context.auth.uid) return;
        const userData = doc.data() || {};
        if (!String(userData.username || '').trim()) return;
        candidates.set(doc.id, { uid: doc.id, ...userData });
      });
    } catch (e) {
      console.log('findMatchesCallable discovery skipped', e.message);
    }
  }

  return { results: [...candidates.values()].slice(0, 120) };
}); 
// ==================================================================
// 7. FANOUT FEED (Takip Edilenler Akışı Optimizasyonu)
// ==================================================================
exports.fanoutPostToFollowers = functions.firestore
  .document("posts/{postId}")
  .onCreate(async (snapshot, context) => {
    const postData = snapshot.data();
    const authorId = postData.authorId;
    const postId = context.params.postId;

    const db = admin.firestore();
    
    // Yazarın takipçilerini bul (collectionGroup kullanarak)
    const followersSnap = await db.collectionGroup("following")
      .where("to", "==", authorId)
      .get();

    if (followersSnap.empty) return null;

    const batch = db.batch();
    
    // Post referansını her bir takipçinin özel feed kutusuna ekle
    followersSnap.forEach((doc) => {
      const followerId = doc.data().by;
      if (followerId) {
        const feedRef = db.collection("feeds").doc(followerId).collection("user_feed").doc(postId);
        batch.set(feedRef, {
          postId: postId,
          authorId: authorId,
          createdAt: postData.createdAt
        });
      }
    });

    return batch.commit();
  });
