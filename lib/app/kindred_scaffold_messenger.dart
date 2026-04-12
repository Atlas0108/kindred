import 'package:flutter/material.dart';

/// Root messenger so SnackBars survive `go()` away from a screen (e.g. after publish).
final GlobalKey<ScaffoldMessengerState> kindredScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
