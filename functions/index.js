const functions = require("firebase-functions/v1"); // v1 Triggerlar için
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // v2 Callable fonksiyonlar için
const admin = require("firebase-admin");
const axios = require("axios");

// Firebase Admin'i başlat
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// ==================================================================
// 1. GENEL TMDB PROXY (Tüm aramalar ve detaylar buradan geçer)
// ==================================================================
exports.callTMDB = onCall({ secrets: ["TMDB_ACCESS_TOKEN"] }, async (request) => {
    // Güvenlik: Sadece giriş yapmış kullanıcılar
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Oturum açmanız gerekiyor.');
    }

    const { endpoint, params } = request.data;
    const token = process.env.TMDB_ACCESS_TOKEN;

    if (!endpoint) {
        throw new HttpsError('invalid-argument', 'Endpoint gerekli.');
    }

    try {
        const response = await axios.get(`https://api.themoviedb.org${endpoint}`, {
            params: { 
                ...params, 
                // Varsayılan dil ayarı, parametre gelirse onu kullanır
                language: params && params.language ? params.language : 'tr-TR' 
            },
            headers: {
                Authorization: `Bearer ${token}`,
                Accept: 'application/json'
            }
        });

        return response.data;
    } catch (error) {
        console.error("TMDB Proxy Hatası:", endpoint, error.message);
        // Detaylı hatayı loglayıp kullanıcıya genel hata dönüyoruz
        throw new HttpsError('internal', 'TMDB isteği başarısız oldu.');
    }
});

// ==================================================================
// 2. SEARCH MOVIES (Eski fonksiyonu tutmak istersen - Opsiyonel)
// ==================================================================
// Not: Artık callTMDB olduğu için bu fonksiyon şart değil ama
// search_movie.dart içinde hala bunu çağıran kod varsa kalsın.
exports.searchMovies = onCall({ secrets: ["TMDB_ACCESS_TOKEN"] }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Giriş yapmalısın.');
    }
    const query = request.data.query;
    const token = process.env.TMDB_ACCESS_TOKEN;

    try {
        const response = await axios.get(`https://api.themoviedb.org/3/search/movie`, {
            params: { query: query, language: 'tr-TR', page: '1', include_adult: 'false' },
            headers: { Authorization: `Bearer ${token}` }
        });
        return response.data;
    } catch (error) {
        throw new HttpsError('internal', 'Arama hatası.');
    }
});

// ==================================================================
// 3. MEVCUT FIRESTORE TRIGGERLARI (Dokunulmadı)
// ==================================================================

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
    const actorName = actorData.displayName || "Bir Kullanıcı";
    const actorPhoto = actorData.photoURL || "";
    const querySnapshot = await admin.firestore()
      .collection("users").doc(authorId).collection("notifications")
      .where("type", "==", "like").where("postId", "==", postId).where("read", "==", false)
      .limit(1).get();
    if (!querySnapshot.empty) {
      const doc = querySnapshot.docs[0];
      const currentCount = doc.data().count || 1;
      await doc.ref.update({
        count: currentCount + 1,
        actorName: actorName,
        actorPhotoURL: actorPhoto,
        preview: `${actorName} ve ${currentCount} diğer kişi gönderini beğendi.`,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } else {
      await admin.firestore().collection("users").doc(authorId).collection("notifications").add({
        type: "like", actorId: actorId, actorName: actorName, actorPhotoURL: actorPhoto,
        postId: postId, movieTitle: postData.movieTitle || "",
        createdAt: admin.firestore.FieldValue.serverTimestamp(), read: false, count: 1, 
        preview: `${actorName} gönderini beğendi.`
      });
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
        type: "follow", actorId: followerId, actorName: followerData.displayName || "Bir Kullanıcı",
        actorPhotoURL: followerData.photoURL || "", postId: "-",
        createdAt: admin.firestore.FieldValue.serverTimestamp(), read: false,
      });
  });

exports.aggregateUnreadCounts = functions.firestore
  .document("chats/{chatId}")
  .onUpdate(async (change, context) => {
    const newData = change.after.data();
    const oldData = change.before.data();
    const newCounts = newData.unreadCounts || {};
    const oldCounts = oldData.unreadCounts || {};
    if (JSON.stringify(newCounts) === JSON.stringify(oldCounts)) return;
    const participants = newData.participants || [];
    const updates = [];
    for (const uid of participants) {
      const oldVal = (oldCounts[uid] && typeof oldCounts[uid] === 'number') ? oldCounts[uid] : 0;
      const newVal = (newCounts[uid] && typeof newCounts[uid] === 'number') ? newCounts[uid] : 0;
      const diff = newVal - oldVal;
      if (diff !== 0) {
        const updatePromise = admin.firestore().collection("users").doc(uid)
            .set({ totalUnreadCount: admin.firestore.FieldValue.increment(diff), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        updates.push(updatePromise);
      }
    }
    if (updates.length > 0) await Promise.all(updates);
  });

exports.sendNotification = functions.firestore
  .document("users/{userId}/notifications/{notificationId}")
  .onCreate(async (snapshot, context) => {
    const userId = context.params.userId;
    const data = snapshot.data();
    if (data.actorId === userId) return;
    const tokensSnap = await admin.firestore().collection("users").doc(userId).collection("fcmTokens").get();
    if (tokensSnap.empty) return;
    const tokens = tokensSnap.docs.map(doc => doc.id);
    let title = "Yeni Bildirim";
    let body = data.preview || "Bir etkileşim aldınız."; 
    if (data.type === "like") title = "Yeni Beğeni";
    else if (data.type === "comment") title = "Yeni Yorum";
    else if (data.type === "follow") title = "Yeni Takipçi";
    const payload = {
      notification: { title: title, body: body },
      data: { type: data.type, postId: data.postId || "", actorId: data.actorId || "", click_action: "FLUTTER_NOTIFICATION_CLICK" }
    };
    await admin.messaging().sendToDevice(tokens, payload);
  });
  
exports.sendChatNotification = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const messageData = snapshot.data();
    const chatId = context.params.chatId;
    const authorId = messageData.authorId;
    const chatDoc = await admin.firestore().collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return;
    const participants = chatDoc.data().participants || [];
    const receiverId = participants.find((uid) => uid !== authorId);
    if (!receiverId) return;
    const tokensSnap = await admin.firestore().collection("users").doc(receiverId).collection("fcmTokens").get();
    if (tokensSnap.empty) return;
    const tokens = tokensSnap.docs.map((doc) => doc.id);
    const payload = {
      notification: { title: "Yeni Mesaj", body: messageData.text || "Bir film gönderildi." },
      data: { type: "chat", chatId: chatId, click_action: "FLUTTER_NOTIFICATION_CLICK" },
    };
    await admin.messaging().sendToDevice(tokens, payload);
  });

exports.findMatchesCallable = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Kullanıcı girişi gerekli.');
  const myUid = context.auth.uid;
  const db = admin.firestore();
  const meSnap = await db.collection('users').doc(myUid).get();
  if (!meSnap.exists) throw new functions.https.HttpsError('not-found', 'Kullanıcı profili bulunamadı.');
  const myData = meSnap.data();
  const myFiveStars = (myData.fiveStarKeys || []).slice(0, 50);
  const myFavorites = (myData.favoritesKeys || []).slice(0, 20);
  let candidates = [];
  const searchPool = [...myFiveStars, ...myFavorites];
  if (searchPool.length > 0) {
    const randomKeys = searchPool.sort(() => 0.5 - Math.random()).slice(0, 3);
    const query = await db.collection('users').where('fiveStarKeys', 'array-contains-any', randomKeys).limit(30).get();
    candidates = query.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }
  if (candidates.length < 5) {
     const fallbackQuery = await db.collection('users').orderBy('createdAt', 'desc').limit(20).get();
     const fallbacks = fallbackQuery.docs.map(doc => ({ id: doc.id, ...doc.data() }));
     candidates = [...candidates, ...fallbacks];
  }
  candidates = candidates.filter(c => c.id !== myUid);
  const results = candidates.map(c => {
    const theirFive = new Set(c.fiveStarKeys || []);
    const commonCount = myFiveStars.filter(id => theirFive.has(id)).length;
    return {
      uid: c.id, displayName: c.displayName, photoURL: c.photoURL,
      fiveStarKeys: c.fiveStarKeys || [], favoritesKeys: c.favoritesKeys || [],
      watchlistKeys: c.watchlistKeys || [], favGenres: c.favGenres || [],
      favDirectors: c.favDirectors || [], favActors: c.favActors || [],
      preScore: commonCount * 10 
    };
  });
  return { results };
});