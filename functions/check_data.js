const admin = require('firebase-admin');
admin.initializeApp({projectId:'moneytest-app'});
const db = admin.firestore();
const uid = 'lw5doMDs4bMxnUHmGhYoLg0kAIj2';

Promise.all([
  db.collection('users').doc(uid).collection('accounts').get(),
  db.collection('users').doc(uid).collection('transactions').get(),
  db.collection('users').doc(uid).collection('financialAggregates').get()
]).then(([accounts, transactions, aggregates]) => {
  console.log('=== ACCOUNTS (' + accounts.size + ') ===');
  accounts.docs.forEach(d => console.log(d.id, JSON.stringify(d.data())));
  console.log('\n=== TRANSACTIONS (' + transactions.size + ') ===');
  transactions.docs.slice(0,10).forEach(d => {
    const data = d.data();
    console.log(d.id, '|', data.merchant, '|', data.amount, '|', data.type, '|', data.maskedNumber);
  });
  console.log('...');
  console.log('\n=== AGGREGATES (' + aggregates.size + ') ===');
  aggregates.docs.forEach(d => console.log(d.id, JSON.stringify(d.data()).substring(0,300)));
}).catch(e => console.error(e));
