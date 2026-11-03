'use strict';

const DEFAULT_RELEASE = {
  latestVersion: '1.0.1',
  latestBuild: 2,
  minSupportedVersion: '1.0.0',
  minSupportedBuild: 1,
  urgency: 'none',
  releaseNotes: '',
  androidDownloadUrl: '',
  iosDownloadUrl: '',
  published: false,
};

function normalizeRelease(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  return {
    latestVersion: String(src.latestVersion || DEFAULT_RELEASE.latestVersion),
    latestBuild: Number(src.latestBuild) || DEFAULT_RELEASE.latestBuild,
    minSupportedVersion: String(src.minSupportedVersion || DEFAULT_RELEASE.minSupportedVersion),
    minSupportedBuild: Number(src.minSupportedBuild) || DEFAULT_RELEASE.minSupportedBuild,
    urgency: ['none', 'recommended', 'required'].includes(src.urgency)
      ? src.urgency
      : 'none',
    releaseNotes: String(src.releaseNotes || '').slice(0, 2000),
    androidDownloadUrl: String(src.androidDownloadUrl || ''),
    iosDownloadUrl: String(src.iosDownloadUrl || ''),
    published: src.published === true,
  };
}

function publicPayload(release) {
  const r = normalizeRelease(release);
  if (!r.published) {
    return {
      ...normalizeRelease(DEFAULT_RELEASE),
      published: false,
      urgency: 'none',
      androidDownloadUrl: '',
      iosDownloadUrl: '',
      note: 'No verified public store release is published yet.',
    };
  }
  return r;
}

function compareBuild(installedBuild, latestBuild) {
  const a = Number(installedBuild) || 0;
  const b = Number(latestBuild) || 0;
  return a < b;
}

module.exports = {
  DEFAULT_RELEASE,
  normalizeRelease,
  publicPayload,
  compareBuild,
};
