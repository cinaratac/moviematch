const functions = require("firebase-functions");
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