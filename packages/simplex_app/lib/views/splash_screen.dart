import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:progress_indicators/progress_indicators.dart';
import 'package:simplex_chat/animations/entrance_fader.dart';
import 'package:simplex_chat/app_routes.dart';
import 'package:simplex_chat/constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // delay on splash screen
  void _splashDelay() {
    Future.delayed(const Duration(seconds: 4), () {
      Navigator.pushNamed(
        context,
        AppRoutes.intro,
      );
    });
  }

  @override
  void initState() {
    _splashDelay();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EntranceFader(
              duration: const Duration(seconds: 1),
              offset: const Offset(0, 15),
              child: SvgPicture.asset(
                'assets/logo.svg',
                height: 85,
              ),
            ),
            EntranceFader(
              offset: const Offset(0, 0),
              duration: const Duration(seconds: 1),
              delay: const Duration(seconds: 1),
              child: JumpingDotsProgressIndicator(
                fontSize: 40,
                color: kPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}