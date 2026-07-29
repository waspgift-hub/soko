const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { notifyUser } = require('./sender');

const db = admin.firestore();

exports.notifyOnEscrowRelease = functions.firestore
  .document('transactions/{transactionId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (before.status === 'escrow_hold' && after.status === 'completed') {
      const sellerId = after.sellerId;
      const buyerId = after.buyerId;
      const productName = after.productName || 'Product';
      const amount = after.sellerReceives || after.grossAmount || 0;

      if (sellerId) {
        await notifyUser({
          userId: sellerId,
          title: 'Escrow Released',
          body: `TSh ${Number(amount).toLocaleString()} for ${productName} has been released to your wallet.`,
          type: 'escrow_release',
          data: { transactionId: context.params.transactionId, productName },
        });
      }
      if (buyerId) {
        await notifyUser({
          userId: buyerId,
          title: 'Order Completed',
          body: `Your order for ${productName} is complete. Thank you for shopping on Soko Vibe!`,
          type: 'delivery_confirmed',
          data: { transactionId: context.params.transactionId, productName },
        });
      }
    }
  });

exports.notifyOnDispute = functions.firestore
  .document('transactions/{transactionId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (before.status !== 'disputed' && after.status === 'disputed') {
      const sellerId = after.sellerId;
      const buyerId = after.buyerId;
      const productName = after.productName || 'Product';
      if (sellerId) {
        await notifyUser({
          userId: sellerId,
          title: 'Dispute Filed',
          body: `A dispute has been filed for ${productName}. Please check your orders.`,
          type: 'order_disputed',
          data: { transactionId: context.params.transactionId, productName },
        });
      }
      if (buyerId) {
        await notifyUser({
          userId: buyerId,
          title: 'Dispute Filed',
          body: `Your dispute for ${productName} has been filed. We will review it shortly.`,
          type: 'order_disputed',
          data: { transactionId: context.params.transactionId, productName },
        });
      }
    }
  });
