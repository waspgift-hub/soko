import re
p=r"C:\Users\user\Desktop\SOKO VIBE\ttr\soko_langu\firestore.rules"
s=open(p,encoding='utf-8').read()

old_userpublic = """      // ONE field is client-writable: the profile-view counter, and only by
      // incrementing it by exactly one. There is deliberately no `create`, so a
      // caller cannot fabricate a projection, and `affectedKeys()` pins the
      // update to that single field, so kycApproved / isSeller / accountStatus
      // stay Admin-SDK-only and a forged verified badge remains impossible.
      //
      // Known limit: any signed-in account can call this repeatedly, so the
      // number is a vanity metric, not an audited count. Counting that has to be
      // trustworthy belongs behind a rate-limited server endpoint.
      allow update: if isSignedIn()
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['profileViews'])
        && request.resource.data.profileViews == resource.data.profileViews + 1;
      // Follower / following counts are server-owned (updated by the follow
      // service in a batch with the relationship docs). Clients may not touch
      // them — otherwise anyone could inflate their own popularity.
      allow update: if isSignedIn()
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['followerCount'])
        && request.resource.data.followerCount == resource.data.followerCount + 1;
      allow update: if isSignedIn()
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['followingCount'])
        && request.resource.data.followingCount == resource.data.followingCount + 1;
      allow update: if isSignedIn()
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['followerCount'])
        && request.resource.data.followerCount == resource.data.followerCount - 1;
      allow update: if isSignedIn()
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['followingCount'])
        && request.resource.data.followingCount == resource.data.followingCount - 1;
      // Public/private toggle + visibility settings are client-writable (their
      // own profile), but only the listed boolean keys.
      allow update: if isSignedIn()
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'visibility'
        ])
        && request.resource.data.visibility is map
        && request.resource.data.visibility.keys().hasOnly([
          'isPrivate', 'showFollowers', 'showFollowing', 'showProducts',
          'allowContactDiscovery'
        ])
        && request.resource.data.visibility.isPrivate is bool
        && request.resource.data.visibility.showFollowers is bool
        && request.resource.data.visibility.showFollowing is bool
        && request.resource.data.visibility.showProducts is bool
        && request.resource.data.visibility.allowContactDiscovery is bool;"""

new_userpublic = """      // ONE field is client-writable: the profile-view counter, and only by
      // incrementing it by exactly one. There is deliberately no `create`, so a
      // caller cannot fabricate a projection. Follower/following counts are
      // server-owned (admin SDK) and are NOT client-writable.
      allow update: if isSignedIn()
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['profileViews'])
        && request.resource.data.profileViews == resource.data.profileViews + 1;
      // Public/private toggle + visibility settings are client-writable by the
      // OWNER only.
      allow update: if isSignedIn()
        && request.auth.uid == userId
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'visibility'
        ])
        && request.resource.data.visibility is map
        && request.resource.data.visibility.keys().hasOnly([
          'isPrivate', 'showFollowers', 'showFollowing', 'showProducts',
          'allowContactDiscovery'
        ])
        && request.resource.data.visibility.isPrivate is bool
        && request.resource.data.visibility.showFollowers is bool
        && request.resource.data.visibility.showFollowing is bool
        && request.resource.data.visibility.showProducts is bool
        && request.resource.data.visibility.allowContactDiscovery is bool;"""

assert old_userpublic in s, "userpublic block not found"
s=s.replace(old_userpublic,new_userpublic)

old_followers = """      match /followers/{followerId} {
        allow create: if isSignedIn()
          && (
            // Follower writes their own followerId to follow a public target
            (request.auth.uid == request.resource.data.followerId
              && get(/databases/$(database)/documents/users/$(userId)).data.visibility.isPrivate == false)
            // Target approves a pending request (writes a follower edge for another uid)
            || (request.auth.uid == userId
              && request.resource.data.followerId != request.auth.uid)
          );
        allow delete: if isSignedIn()
          && (request.auth.uid == userId || request.auth.uid == followerId);
        allow read: if isSignedIn();
      }"""
new_followers = """      match /followers/{followerId} {
        allow create: if isSignedIn()
          && request.resource.data.followerId == followerId
          && (
            // Follower writes their own follower edge to a public target
            (request.auth.uid == followerId
              && get(/databases/$(database)/documents/users/$(userId)).data.get('visibility', {}).get('isPrivate', false) == false)
            // Target approves a pending request (must have a pending request doc)
            || (request.auth.uid == userId
              && followerId != request.auth.uid
              && exists(/databases/$(database)/documents/users/$(userId)/followRequests/$(followerId)))
          );
        allow delete: if isSignedIn()
          && (request.auth.uid == userId || request.auth.uid == followerId);
        allow read: if isSignedIn();
      }"""
assert old_followers in s
s=s.replace(old_followers,new_followers)

old_req = """      match /followRequests/{requesterId} {
        allow read: if isSignedIn() && request.auth.uid == userId;
        allow create: if isSignedIn()
          && request.resource.data.requesterId != request.auth.uid
          && request.resource.data.requesterId == requesterId;
        allow delete: if isSignedIn()
          && (request.auth.uid == userId || request.auth.uid == requesterId);
      }"""
new_req = """      match /followRequests/{requesterId} {
        allow read: if isSignedIn() && request.auth.uid == userId;
        allow create: if isSignedIn()
          && request.auth.uid == requesterId
          && requesterId != userId
          && get(/databases/$(database)/documents/users/$(userId)).data.get('visibility', {}).get('isPrivate', false) == true;
        allow delete: if isSignedIn()
          && (request.auth.uid == userId || request.auth.uid == requesterId);
      }"""
assert old_req in s
s=s.replace(old_req,new_req)

old_sent = """      match /followRequestsSent/{targetId} {
        allow read: if isSignedIn() && request.auth.uid == userId;
        allow create: if isSignedIn()
          && request.resource.data.targetId != request.auth.uid
          && request.resource.data.targetId == targetId;
        allow delete: if isSignedIn()
          && (request.auth.uid == userId || request.auth.uid == targetId);
      }"""
new_sent = """      match /followRequestsSent/{targetId} {
        allow read: if isSignedIn() && request.auth.uid == userId;
        allow create: if isSignedIn()
          && request.auth.uid == userId
          && targetId != request.auth.uid
          && request.resource.data.targetId == targetId;
        allow delete: if isSignedIn()
          && (request.auth.uid == userId || request.auth.uid == targetId);
      }"""
assert old_sent in s
s=s.replace(old_sent,new_sent)

old_blocked = """      match /blocked/{blockedId} {
        allow create: if isSignedIn()
          && request.auth.uid == userId
          && request.resource.data.blockerId == request.auth.uid;
        allow delete: if isSignedIn() && request.auth.uid == userId;
        allow read: if isSignedIn() && request.auth.uid == userId;
      }"""
new_blocked = """      match /blocked/{blockedId} {
        allow create: if isSignedIn()
          && request.auth.uid == userId
          && request.resource.data.blockerId == request.auth.uid
          && request.resource.data.blockedId == blockedId;
        allow delete: if isSignedIn() && request.auth.uid == userId;
        allow read: if isSignedIn() && request.auth.uid == userId;
      }"""
assert old_blocked in s
s=s.replace(old_blocked,new_blocked)

open(p,'w',encoding='utf-8').write(s)
print("done")
PY