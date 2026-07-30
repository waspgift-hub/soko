import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class DriverRideRequestScreen extends StatelessWidget {
  const DriverRideRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ride_request_title'))),
      body: Center(child: Text(context.tr('coming_soon_placeholder'))),
    );
  }
}
