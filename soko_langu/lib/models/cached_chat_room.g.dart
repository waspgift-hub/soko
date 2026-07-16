// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_chat_room.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CachedChatRoomAdapter extends TypeAdapter<CachedChatRoom> {
  @override
  final int typeId = 2;

  @override
  CachedChatRoom read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CachedChatRoom(
      id: fields[0] as String,
      participants: (fields[1] as List).cast<String>(),
      lastMessage: fields[2] as String,
      lastTimestampMillis: fields[3] as int,
      unreadCountBuyer: fields[4] as int,
      unreadCountSeller: fields[5] as int,
      productId: fields[6] as String?,
      productTitle: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, CachedChatRoom obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.participants)
      ..writeByte(2)
      ..write(obj.lastMessage)
      ..writeByte(3)
      ..write(obj.lastTimestampMillis)
      ..writeByte(4)
      ..write(obj.unreadCountBuyer)
      ..writeByte(5)
      ..write(obj.unreadCountSeller)
      ..writeByte(6)
      ..write(obj.productId)
      ..writeByte(7)
      ..write(obj.productTitle);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedChatRoomAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
