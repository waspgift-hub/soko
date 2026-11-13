'use strict';

// Test script for Centralized Notification Orchestrator
// Tests using: waspgift@gmail and phone 0693273241

const { app } = require('../src/app');
const http = require('http');

let server;
let port;

before(async () => {
  await new Promise((resolve) => {
    server = app.listen(0, () => {
      port = server.address().port;
      resolve();
    });
  });
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

function req(method, path, body = {}, headers = {}) {
  return new Promise((resolve, reject) => {
    const r = http.request(
      {
        host: 'localhost',
        port,
        path,
        method,
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
      },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, body: JSON.parse(b) });
          } catch {
            resolve({ status: res.statusCode, body: b });
          }
        });
      },
    );
    r.on('error', reject);
    r.end(JSON.stringify(body));
  });
}

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Test 1: Send payment success notification
async function testPaymentSuccess() {
  console.log('\n=== Test 1: Payment Success Notification ===');
  try {
    const result = await req('POST', '/api/v1/notifications/send', {
      eventType: 'payment_success',
      userId: 'test-user-123',
      data: { amount: '5000', orderId: 'ORD-001' },
      language: 'sw',
    });
    console.log(`Status: ${result.status}`);
    console.log(`Body: ${JSON.stringify(result.body, null, 2)}`);
    if (result.body.success) {
      console.log('✓ Payment success notification sent successfully');
    } else {
      console.log('✗ Payment success notification failed');
    }
    return result.body.success;
  } catch (e) {
    console.log(`✗ Test error: ${e.message}`);
    return false;
  }
}

// Test 2: Send KYC approved notification
async function testKycApproved() {
  console.log('\n=== Test 2: KYC Approved Notification ===');
  try {
    const result = await req('POST', '/api/v1/notifications/send', {
      eventType: 'kyc_approved',
      userId: 'test-user-123',
      data: {},
      language: 'sw',
    });
    console.log(`Status: ${result.status}`);
    console.log(`Body: ${JSON.stringify(result.body, null, 2)}`);
    if (result.body.success) {
      console.log('✓ KYC approved notification sent successfully');
    } else {
      console.log('✗ KYC approved notification failed');
    }
    return result.body.success;
  } catch (e) {
    console.log(`✗ Test error: ${e.message}`);
    return false;
  }
}

// Test 3: Send order created notification
async function testOrderCreated() {
  console.log('\n=== Test 3: Order Created Notification ===');
  try {
    const result = await req('POST', '/api/v1/notifications/send', {
      eventType: 'order_created',
      userId: 'test-user-123',
      data: { orderId: 'ORD-001' },
      language: 'en',
    });
    console.log(`Status: ${result.status}`);
    console.log(`Body: ${JSON.stringify(result.body, null, 2)}`);
    if (result.body.success) {
      console.log('✓ Order created notification sent successfully');
    } else {
      console.log('✗ Order created notification failed');
    }
    return result.body.success;
  } catch (e) {
    console.log(`✗ Test error: ${e.message}`);
    return false;
  }
}

// Test 4: Send chat new message notification
async function testChatNewMessage() {
  console.log('\n=== Test 4: Chat New Message Notification ===');
  try {
    const result = await req('POST', '/api/v1/notifications/send', {
      eventType: 'chat_new_message',
      userId: 'test-user-123',
      data: { senderName: 'Mtalemwa', roomId: 'room-abc' },
      language: 'sw',
    });
    console.log(`Status: ${result.status}`);
    console.log(`Body: ${JSON.stringify(result.body, null, 2)}`);
    if (result.body.success) {
      console.log('✓ Chat new message notification sent successfully');
    } else {
      console.log('✗ Chat new message notification failed');
    }
    return result.body.success;
  } catch (e) {
    console.log(`✗ Test error: ${e.message}`);
    return false;
  }
}

async function runTests() {
  console.log('🚀 Starting Notification Orchestrator Tests');
  console.log('Using email: waspgift@gmail and phone: 0693273241\n');

  const results = [];
  
  results.push(await testPaymentSuccess());
  await sleep(1000);
  
  results.push(await testKycApproved());
  await sleep(1000);
  
  results.push(await testOrderCreated());
  await sleep(1000);
  
  results.push(await testChatNewMessage());
  
  console.log('\n=== Test Summary ===');
  const passed = results.filter(r => r).length;
  const total = results.length;
  console.log(`Passed: ${passed}/${total}`);
  
  if (passed === total) {
    console.log('🎉 All tests passed!');
  } else {
    console.log('⚠️  Some tests failed');
  }
  
  await sleep(2000);
  process.exit(passed === total ? 0 : 1);
}

runTests().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});