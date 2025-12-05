const functions = require("firebase-functions/v1"); 
const admin = require("firebase-admin");
admin.initializeApp();

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
    let body = "Bir etkileşim aldınız.";

    if (data.type === "like") {
      title = "Yeni Beğeni";
      body = `${data.actorName || 'Birisi'} gönderinizi beğendi.`;
    } else if (data.type === "comment") {
      title = "Yeni Yorum";
      body = `${data.actorName || 'Birisi'} yorum yaptı: ${data.preview || ''}`;
    } else if (data.type === "follow") {
      title = "Yeni Takipçi";
      body = `${data.actorName || 'Birisi'} sizi takip etti.`;
    }

    const payload = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        // Tıklandığında Flutter tarafında yakalamak için
        type: data.type,
        postId: data.postId || "",
        actorId: data.actorId || "",
        click_action: "FLUTTER_NOTIFICATION_CLICK" 
      }
    };

    // FCM üzerinden gönder
    await admin.messaging().sendToDevice(tokens, payload);
  });
  exports.sendChatNotification = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const messageData = snapshot.data();
    const chatId = context.params.chatId;
    const authorId = messageData.authorId;

    // 1. Chat dokümanını çekip katılımcıları (participants) bulalım
    const chatDoc = await admin.firestore().collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return;

    const participants = chatDoc.data().participants || [];

    // 2. Mesajı gönderen dışındaki diğer kişiyi bul (Alıcı)
    const receiverId = participants.find((uid) => uid !== authorId);
    if (!receiverId) return;

    // 3. Alıcının FCM tokenlarını al
    const tokensSnap = await admin.firestore()
      .collection("users")
      .doc(receiverId)
      .collection("fcmTokens")
      .get();

    if (tokensSnap.empty) return;

    const tokens = tokensSnap.docs.map((doc) => doc.id);

    // 4. Bildirim içeriğini hazırla
    const payload = {
      notification: {
        title: "Yeni Mesaj",
        body: messageData.text || "Bir film gönderildi.", // Mesaj metni veya varsayılan
      },
      data: {
        type: "chat",
        chatId: chatId,
        click_action: "FLUTTER_NOTIFICATION_CLICK"
      },
    };

    // 5. Gönder
    await admin.messaging().sendToDevice(tokens, payload);
  });