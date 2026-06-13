/* eslint-disable */
const functions = require("firebase-functions/v1"); // v1 Triggerlar için
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // v2 Callable fonksiyonlar için
const admin = require("firebase-admin");
const axios = require("axios");

// Firebase Admin'i başlat
if (admin.apps.length === 0) {
  admin.initializeApp();
}

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
// 4. SOHBET & MESAJ BİLDİRİMLERİ (İyileştirilmiş V1)
// ==================================================================
exports.sendChatNotification = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const messageData = snapshot.data();
    const authorId = messageData.authorId;
    const chatDoc = await admin.firestore().collection("chats").doc(context.params.chatId).get();
    if (!chatDoc.exists) return;

    const participants = chatDoc.data().participants || [];
    const receiverId = participants.find((uid) => uid !== authorId);
    if (!receiverId) return;

    const tokensSnap = await admin.firestore().collection("users").doc(receiverId).collection("fcmTokens").get();
    if (tokensSnap.empty) return;
    const tokens = tokensSnap.docs.map(doc => doc.id);

    const payload = {
      notification: { title: "Yeni Mesaj", body: messageData.text || "Bir mesajınız var." },
      data: { type: "chat", chatId: context.params.chatId, click_action: "FLUTTER_NOTIFICATION_CLICK" }
    };
    // Modern sendEachForMulticast kullanımı
    await admin.messaging().sendEachForMulticast({ tokens: tokens, ...payload });
  });

// ==================================================================
// 5. DİĞER KRİTİK SİSTEM FONKSİYONLARI
// ==================================================================
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
  const searchKeys = [...(myData.fiveStarKeys || []).slice(0, 30), ...(myData.favoritesKeys || []).slice(0, 10)];
  
  if (searchKeys.length === 0) return { results: [] };
  const query = await db.collection('users').where('fiveStarKeys', 'array-contains-any', searchKeys.slice(0, 10)).limit(20).get();
  return { results: query.docs.map(doc => ({ uid: doc.id, ...doc.data() })).filter(c => c.uid !== context.auth.uid) };
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