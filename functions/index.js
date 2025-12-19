const functions = require("firebase-functions/v1"); 
const admin = require("firebase-admin");
admin.initializeApp();

// --------------------------------------------------------
// 1. LIKE İŞLEMİ (AGGREGATION / GRUPLAMA ÖZELLİKLİ)
// Aynı post için okunmamış bildirim varsa yenisini açmaz, günceller.
// --------------------------------------------------------
exports.createNotificationOnLike = functions.firestore
  .document("posts/{postId}/likes/{userId}")
  .onCreate(async (snapshot, context) => {
    const postId = context.params.postId;
    const actorId = context.params.userId; // Beğenen kişi

    // 1. Post ve Yazar verisini çek
    const postSnap = await admin.firestore().collection("posts").doc(postId).get();
    if (!postSnap.exists) return;
    const postData = postSnap.data();
    const authorId = postData.authorId;

    if (authorId === actorId) return;

    // 2. Beğenen kişinin ismini al
    const actorSnap = await admin.firestore().collection("users").doc(actorId).get();
    const actorData = actorSnap.data() || {};
    const actorName = actorData.displayName || "Bir Kullanıcı";
    const actorPhoto = actorData.photoURL || "";

    // 3. MEVCUT BİLDİRİM KONTROLÜ
    const querySnapshot = await admin.firestore()
      .collection("users")
      .doc(authorId)
      .collection("notifications")
      .where("type", "==", "like")
      .where("postId", "==", postId)
      .where("read", "==", false)
      .limit(1)
      .get();

    if (!querySnapshot.empty) {
      // VARSA: Mevcut bildirimi güncelle (Hotspot önleme)
      const doc = querySnapshot.docs[0];
      const currentCount = doc.data().count || 1;
      const newCount = currentCount + 1;

      await doc.ref.update({
        count: newCount,
        actorName: actorName,
        actorPhotoURL: actorPhoto,
        preview: `${actorName} ve ${currentCount} diğer kişi gönderini beğendi.`,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
    } else {
      // YOKSA: Yeni bildirim oluştur
      await admin.firestore()
        .collection("users")
        .doc(authorId)
        .collection("notifications")
        .add({
          type: "like",
          actorId: actorId,
          actorName: actorName,
          actorPhotoURL: actorPhoto,
          postId: postId,
          movieTitle: postData.movieTitle || "",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
          count: 1, 
          preview: `${actorName} gönderini beğendi.`
        });
    }
  });

// --------------------------------------------------------
// 2. TAKİP (FOLLOW) İŞLEMİ
// --------------------------------------------------------
exports.createNotificationOnFollow = functions.firestore
  .document("users/{followerId}/following/{followedId}")
  .onCreate(async (snapshot, context) => {
    const followerId = context.params.followerId; 
    const followedId = context.params.followedId; 

    const followerSnap = await admin.firestore().collection("users").doc(followerId).get();
    const followerData = followerSnap.data() || {};

    await admin.firestore()
      .collection("users")
      .doc(followedId)
      .collection("notifications")
      .doc(`${followerId}_follow`)
      .set({
        type: "follow",
        actorId: followerId,
        actorName: followerData.displayName || "Bir Kullanıcı",
        actorPhotoURL: followerData.photoURL || "",
        postId: "-",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      });
  });

// --------------------------------------------------------
// 3. TOTAL UNREAD COUNT OPTIMIZED (Maliyet Dostu Versiyon)
// Sohbet güncellendiğinde, aradaki farkı hesaplayıp kullanıcı profiline yansıtır.
// Tüm sohbetleri yeniden okumaz!
// --------------------------------------------------------
exports.aggregateUnreadCounts = functions.firestore
  .document("chats/{chatId}")
  .onUpdate(async (change, context) => {
    const newData = change.after.data();
    const oldData = change.before.data();

    const newCounts = newData.unreadCounts || {};
    const oldCounts = oldData.unreadCounts || {};

    // Sadece unreadCounts değiştiyse işlem yap (Gereksiz çalışmayı önle)
    if (JSON.stringify(newCounts) === JSON.stringify(oldCounts)) return;

    const participants = newData.participants || [];
    const updates = [];

    for (const uid of participants) {
      // Eski ve yeni değerleri güvenli şekilde al
      const oldVal = (oldCounts[uid] && typeof oldCounts[uid] === 'number') ? oldCounts[uid] : 0;
      const newVal = (newCounts[uid] && typeof newCounts[uid] === 'number') ? newCounts[uid] : 0;
      
      // Aradaki farkı hesapla (Örn: 3'ten 0'a düştüyse diff = -3)
      const diff = newVal - oldVal;

      if (diff !== 0) {
        // Kullanıcının totalUnreadCount değerini atomic olarak güncelle
        const updatePromise = admin.firestore()
            .collection("users")
            .doc(uid)
            .set({
                totalUnreadCount: admin.firestore.FieldValue.increment(diff),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
            
        updates.push(updatePromise);
      }
    }

    // Tüm güncellemeleri paralel olarak çalıştır
    if (updates.length > 0) {
      await Promise.all(updates);
    }
  });
// --------------------------------------------------------
// 4. PUSH NOTIFICATION GÖNDERİCİ (Mevcut kodunuzdan güncellendi)
// --------------------------------------------------------
exports.sendNotification = functions.firestore
  .document("users/{userId}/notifications/{notificationId}")
  .onCreate(async (snapshot, context) => {
    const userId = context.params.userId;
    const data = snapshot.data();
    
    // Kendi bildirimini gönderme
    if (data.actorId === userId) return;

    // Kullanıcının tokenlarını al
    const tokensSnap = await admin.firestore()
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .get();

    if (tokensSnap.empty) return;

    const tokens = tokensSnap.docs.map(doc => doc.id);

    // Bildirim içeriğini hazırla
    let title = "Yeni Bildirim";
    // Preview alanı like aggregation'da dolduruluyor.
    let body = data.preview || "Bir etkileşim aldınız."; 

    if (data.type === "like") {
      title = "Yeni Beğeni";
    } else if (data.type === "comment") {
      title = "Yeni Yorum";
      // Body = data.preview (artık comment preview buradan geliyor)
    } else if (data.type === "follow") {
      title = "Yeni Takipçi";
    }

    const payload = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: data.type,
        postId: data.postId || "",
        actorId: data.actorId || "",
        click_action: "FLUTTER_NOTIFICATION_CLICK" 
      }
    };

    // FCM üzerinden gönder
    await admin.messaging().sendToDevice(tokens, payload);
  });
  
// --------------------------------------------------------
// 5. CHAT PUSH NOTIFICATION GÖNDERİCİ (Mevcut kodunuzdan)
// --------------------------------------------------------
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

    const tokensSnap = await admin.firestore()
      .collection("users")
      .doc(receiverId)
      .collection("fcmTokens")
      .get();

    if (tokensSnap.empty) return;

    const tokens = tokensSnap.docs.map((doc) => doc.id);

    const payload = {
      notification: {
        title: "Yeni Mesaj",
        body: messageData.text || "Bir film gönderildi.", 
      },
      data: {
        type: "chat",
        chatId: chatId,
        click_action: "FLUTTER_NOTIFICATION_CLICK"
      },
    };

    await admin.messaging().sendToDevice(tokens, payload);
  });
  // --------------------------------------------------------
// 6. MATCH FINDER (Eşleşme Bulucu) - Callable Function
// Rastgele aramak yerine, ortak zevklere sahip adayları doğrudan sorgular.
// --------------------------------------------------------
exports.findMatchesCallable = functions.https.onCall(async (data, context) => {
  // 1. Güvenlik Kontrolü
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Kullanıcı girişi gerekli.');
  }

  const myUid = context.auth.uid;
  const db = admin.firestore();

  // 2. Kendi profilini çek
  const meSnap = await db.collection('users').doc(myUid).get();
  if (!meSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Kullanıcı profili bulunamadı.');
  }
  const myData = meSnap.data();
  const myFiveStars = (myData.fiveStarKeys || []).slice(0, 50); // En son 50 tanesi yeterli
  const myFavorites = (myData.favoritesKeys || []).slice(0, 20);

  // 3. STRATEJİ: "Rastgele" yerine "Hedefli" Arama
  // Benim sevdiğim filmlerden rastgele 3 tanesini seçip, bunları sevenleri arayalım.
  // Eğer hiç verim yoksa son çare rastgele bakarız.
  
  let candidates = [];
  const searchPool = [...myFiveStars, ...myFavorites];
  
  if (searchPool.length > 0) {
    // Rastgele 3 film ID'si seç (Array-contains-any limiti 10'dur, biz 3-4 kullanalım)
    const randomKeys = searchPool.sort(() => 0.5 - Math.random()).slice(0, 3);
    
    // Bu filmlerden HERHANGİ BİRİNİ sevenleri getir
    const query = await db.collection('users')
      .where('fiveStarKeys', 'array-contains-any', randomKeys)
      .limit(30)
      .get();
      
    candidates = query.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  // Eğer aday çıkmadıysa veya hiç filmim yoksa, mecburen rastgele/son kayıt olanlardan getir
  if (candidates.length < 5) {
     const fallbackQuery = await db.collection('users')
       .orderBy('createdAt', 'desc') // Veya rastgele bir field
       .limit(20)
       .get();
     const fallbacks = fallbackQuery.docs.map(doc => ({ id: doc.id, ...doc.data() }));
     candidates = [...candidates, ...fallbacks];
  }

  // 4. Kendini ve daha önce etkileşime geçtiklerini listeden çıkar
  // (Not: Etkileşim listesi çok büyükse bu filtreyi client'a bırakabiliriz, şimdilik burada basitçe yapalım)
  candidates = candidates.filter(c => c.id !== myUid);
  
  // 5. Basit Puanlama ve Formatlama (Detaylı hesaplama yine client'ta veya burada yapılabilir)
  // Bant genişliği tasarrufu için sadece gerekli alanları dönüyoruz.
  const results = candidates.map(c => {
    // Basit bir kesişim hesabı
    const theirFive = new Set(c.fiveStarKeys || []);
    const commonCount = myFiveStars.filter(id => theirFive.has(id)).length;
    
    return {
      uid: c.id,
      displayName: c.displayName,
      photoURL: c.photoURL,
      // Client tarafındaki detaylı hesaplama için gereken ham veriler:
      fiveStarKeys: c.fiveStarKeys || [],
      favoritesKeys: c.favoritesKeys || [],
      watchlistKeys: c.watchlistKeys || [],
      favGenres: c.favGenres || [],
      favDirectors: c.favDirectors || [],
      favActors: c.favActors || [],
      // Ön hesaplama skoru (Client sıralamada kullanabilir)
      preScore: commonCount * 10 
    };
  });

  return { results };
});