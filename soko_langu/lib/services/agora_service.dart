import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class AgoraService {
  static const String appId = '408c0734a8d54f8cae2a17e840b96d86';

  late RtcEngine engine;

  Future<void> initialize({
    ChannelProfileType channelProfile = ChannelProfileType.channelProfileCommunication,
  }) async {
    engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: channelProfile,
    ));
  }

  void dispose() {
    engine.leaveChannel();
    engine.release();
  }
}
