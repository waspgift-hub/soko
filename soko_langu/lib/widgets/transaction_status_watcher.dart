import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionStatusWatcher extends StatefulWidget {
  final Widget child;
  const TransactionStatusWatcher({super.key, required this.child});
  @override
  State<TransactionStatusWatcher> createState() => _TransactionStatusWatcherState();
}
class _TransactionStatusWatcherState extends State<TransactionStatusWatcher> {
  @override
  Widget build(BuildContext context) => widget.child;
}
