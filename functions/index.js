/* eslint-disable */
const functions = require("firebase-functions/v1"); // v1 Triggerlar için
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // v2 Callable fonksiyonlar için
const admin = require("firebase-admin");
const axios = require("axios");

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
