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
// 3. TOTAL UNREAD COUNT AGGREGATOR (Chat Servisinden geldi)
// Bir sohbet güncellendiğinde, katılımcıların toplam okunmamış mesaj sayısını hesaplar ve user profiline yazar.
// --------------------------------------------------------
exports.aggregateUnreadCounts = functions.firestore
  .document("chats/{chatId}")
  .onUpdate(async (change, context) => {
    const newData = change.after.data();
    const oldData = change.before.data();

    const newCounts = newData.unreadCounts || {};
    const oldCounts = oldData.unreadCounts || {};

    if (JSON.stringify(newCounts) === JSON.stringify(oldCounts)) return;

    const participants = newData.participants || [];

    for (const uid of participants) {
      
      const chatsSnap = await admin.firestore()
        .collection("chats")
        .where("participants", "array-contains", uid)
        .get();

      let total = 0;
      chatsSnap.docs.forEach(doc => {
        const d = doc.data();
        const u = d.unreadCounts || {};
        if (u[uid] && typeof u[uid] === 'number') {
          total += u[uid];
        }
      });

      // Kullanıcı profiline yaz
      await admin.firestore().collection("users").doc(uid).set({
        totalUnreadCount: total,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
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