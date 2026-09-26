
import 'package:flutter/material.dart';

class CustomSnackbar {
  
  void showSnackBar(BuildContext context, String message, {Color? bgColor}) {
    final snackBar = SnackBar(
      content: Text(message,textAlign: TextAlign.center,),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}