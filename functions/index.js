/* eslint-disable */
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendChatNotification = functions.firestore
    .document("chats/{chatId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
        const messageData = snap.data();
        const senderId = messageData.authorId;
        const text = messageData.text || "Yeni bir mesajiniz var!";

        const chatRef = admin.firestore().collection("chats").doc(context.params.chatId);
        const chatDoc = await chatRef.get();

        if (!chatDoc.exists) return null;

        const participants = chatDoc.data().participants || [];
        const receivers = participants.filter((uid) => uid !== senderId);

        if (receivers.length === 0) return null;

        let senderName = "CineMatch";
        try {
            const senderDoc = await admin.firestore().collection("users").doc(senderId).get();
            if (senderDoc.exists && senderDoc.data().displayName) {
                senderName = senderDoc.data().displayName;
            }
        } catch (e) {
            console.error("Kullanici adi cekilemedi:", e);
        }

        const tokens = [];
        for (const receiverId of receivers) {
            const tokensSnap = await admin.firestore()
                .collection("users")
                .doc(receiverId)
                .collection("fcmTokens")
                .get();

            tokensSnap.forEach((doc) => {
                if (doc.data().token) {
                    tokens.push(doc.data().token);
                }
            });
        }

        if (tokens.length === 0) {
            console.log("Alicilar icin token bulunamadi.");
            return null;
        }

        const payload = {
            notification: {
                title: senderName,
                body: text,
            },
            tokens: tokens,
        };

        try {
            const response = await admin.messaging().sendEachForMulticast(payload);
            console.log(response.successCount + " bildirim basariyla gonderildi.");
        } catch (error) {
            console.error("Bildirim gonderme hatasi:", error);
        }

        return null;
    });