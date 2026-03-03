const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
const fcm = admin.messaging();

// Sends push to all group members when a new chat message is created.
// This is what makes notifications work when app is closed or screen locked.
exports.onNewChatMessage = functions.firestore
  .document('groups/{groupId}/messages/{msgId}')
  .onCreate(async (snap, context) => {
    const msg = snap.data();
    if (!msg || msg.isPreset) return;
    const {groupId} = context.params;
    const senderUid = msg.senderUid;
    const senderName = msg.senderName || 'Someone';
    const text = msg.isDeleted ? 'Message removed' : msg.isPoll ? ('Poll: ' + (msg.pollQuestion||'')) : (msg.text||'');
    if (!text) return;
    const groupDoc = await db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return;
    const memberUids = groupDoc.data().memberUids || [];
    const otherUids = memberUids.filter(uid => uid !== senderUid);
    if (otherUids.length === 0) return;
    const userDocs = await Promise.all(otherUids.map(uid => db.collection('users').doc(uid).get()));
    const tokens = userDocs.map(d => d.data() && d.data().fcmToken).filter(Boolean);
    if (tokens.length === 0) return;
    await Promise.all(tokens.map(token => fcm.send({
      token,
      notification: {title: String.fromCodePoint(0x1F4AC)+' '+senderName, body: text.substring(0,100)},
      data: {type:'chat', groupId},
      android: {priority:'high', notification:{channelId:'yapapa_chat'}},
    }).catch(()=>null)));
  });
