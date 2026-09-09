import 'replay_file_store.dart';

/// Native (Android/iOS/desktop) factory: the platform-channel replay store,
/// which itself degrades to in-memory on platforms without the channel.
ReplayFileStore createReplayFileStore() => MethodChannelReplayFileStore();
