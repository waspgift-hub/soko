import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import '../../services/zego_config.dart';

class ZegoCallScreen extends StatelessWidget {
  final String callId;
  final String callType;
  final String? remoteName;

  const ZegoCallScreen({
    super.key,
    required this.callId,
    required this.callType,
    this.remoteName,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userID = user?.uid ?? 'unknown';
    final userName = user?.displayName ?? user?.email ?? 'User';

    final config = callType == 'video'
        ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
        : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();

    return ZegoUIKitPrebuiltCall(
      appID: ZegoConfig.appId,
      appSign: ZegoConfig.appSign,
      userID: userID,
      userName: userName,
      callID: callId,
      config: config,
      plugins: [ZegoUIKitSignalingPlugin()],
    );
  }
}
