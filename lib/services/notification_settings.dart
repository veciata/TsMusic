import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

const _defaultColor = Color(0xFF1DB954);

AudioServiceConfig getNotificationSettings({
  String? channelId,
  String? channelName,
  String? channelDescription,
  bool? showNotificationBadge,
  Color? notificationColor,
}) => AudioServiceConfig(
  androidNotificationChannelId: channelId ?? 'com.veciata.tsmusic.channel.audio',
  androidNotificationChannelName: channelName ?? 'TsMusic Playback',
  androidNotificationChannelDescription:
      channelDescription ?? 'TsMusic playback notification',
  androidShowNotificationBadge: showNotificationBadge ?? true,
  notificationColor: notificationColor ?? _defaultColor,
);