import 'package:flutter/material.dart';

/// Global navigator so services (alerts, voice SOS) can show dialogs.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

BuildContext? get appContext => appNavigatorKey.currentContext;
