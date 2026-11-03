'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { publicPayload, compareBuild } = require('../src/modules/config/app-release');

test('unpublished payload never includes store URLs', () => {
  const out = publicPayload({
    published: false,
    androidDownloadUrl: 'https://play.google.com/fake',
    iosDownloadUrl: 'https://apps.apple.com/fake',
    urgency: 'required',
  });
  assert.equal(out.published, false);
  assert.equal(out.androidDownloadUrl, '');
  assert.equal(out.iosDownloadUrl, '');
  assert.equal(out.urgency, 'none');
});

test('published payload keeps verified metadata', () => {
  const out = publicPayload({
    published: true,
    latestVersion: '1.0.2',
    latestBuild: 3,
    urgency: 'recommended',
    androidDownloadUrl: '',
  });
  assert.equal(out.published, true);
  assert.equal(out.latestBuild, 3);
  assert.equal(compareBuild(2, 3), true);
});
