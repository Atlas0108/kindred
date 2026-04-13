import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:introduction_screen/introduction_screen.dart';

import '../../theme/app_theme.dart';

/// Design tokens matching onboarding mockups (forest green, bronze accent).
abstract final class _OnboardingColors {
  static const forest = Color(0xFF1B3022);
  static const bodyGrey = Color(0xFF4A4A4A);
  static const overlineBronze = Color(0xFF996633);
  static const dotActive = Color(0xFF9A5F2E);
  static const dotInactive = Color(0xFFD0D0D0);
}

/// Viewport width at or above this uses centered onboarding copy (desktop / tablet landscape).
const double _onboardingWideLayoutWidth = 720;

/// Public marketing / first-run flow. Served at `/onboarding` without sign-in.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  TextStyle get _serifHeadline => GoogleFonts.playfairDisplay(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: _OnboardingColors.forest,
    height: 1.12,
  );

  TextStyle get _sansBody => GoogleFonts.inter(
    fontSize: 17,
    height: 1.55,
    color: _OnboardingColors.bodyGrey,
    fontWeight: FontWeight.w400,
  );

  PageDecoration _pageDecoration({
    required Alignment bodyAlignment,
    EdgeInsets? contentMargin,
    EdgeInsets? titlePadding,
    EdgeInsets? bodyPadding,
  }) {
    return PageDecoration(
      pageColor: AppTheme.publicCommonsCream,
      bodyAlignment: bodyAlignment,
      imageFlex: 0,
      bodyFlex: 1,
      safeArea: 72,
      pageMargin: EdgeInsets.zero,
      contentMargin: contentMargin ?? const EdgeInsets.symmetric(horizontal: 28),
      titlePadding: titlePadding ?? const EdgeInsets.only(top: 40, bottom: 20),
      bodyPadding: bodyPadding ?? EdgeInsets.zero,
      titleTextStyle: _serifHeadline,
      bodyTextStyle: _sansBody,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= _onboardingWideLayoutWidth;
    final textAlign = wide ? TextAlign.center : TextAlign.left;
    final bodyAlign =
        wide ? Alignment.topCenter : Alignment.centerLeft;
    final colCross =
        wide ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    final pages = <PageViewModel>[
      PageViewModel(
        titleWidget: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: colCross,
            children: [
              Text(
                'INTRODUCTION',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w600,
                  color: _OnboardingColors.overlineBronze,
                ),
                textAlign: textAlign,
              ),
              const SizedBox(height: 20),
              Text.rich(
                TextSpan(
                  style: _serifHeadline,
                  children: const [
                    TextSpan(text: 'Welcome to your '),
                    TextSpan(
                      text: 'digital',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                    TextSpan(text: ' hearth.'),
                  ],
                ),
                textAlign: textAlign,
              ),
            ],
          ),
        ),
        bodyWidget: SizedBox(
          width: double.infinity,
          child: Text(
            'A space for neighbors to gather, share, and grow together. Rooted '
            'in community, cultivated by you.',
            style: _sansBody,
            textAlign: textAlign,
          ),
        ),
        decoration: _pageDecoration(bodyAlignment: bodyAlign),
      ),
      PageViewModel(
        titleWidget: SizedBox(
          width: double.infinity,
          child: Text(
            'Discover your local rhythm.',
            style: _serifHeadline,
            textAlign: textAlign,
          ),
        ),
        bodyWidget: SizedBox(
          width: double.infinity,
          child: Text(
            'Join groups centered around your interests, from garden clubs to '
            'neighborhood watch. Find the people who make this place home.',
            style: _sansBody,
            textAlign: textAlign,
          ),
        ),
        decoration: _pageDecoration(bodyAlignment: bodyAlign),
      ),
      PageViewModel(
        titleWidget: SizedBox(
          width: double.infinity,
          child: Text.rich(
            TextSpan(
              style: _serifHeadline.copyWith(fontWeight: FontWeight.w400),
              children: const [
                TextSpan(text: 'The '),
                TextSpan(
                  text: 'Public\u00A0Commons',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _OnboardingColors.forest,
                  ),
                ),
                TextSpan(text: ' belong to '),
                TextSpan(
                  text: 'you',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                TextSpan(text: '.'),
              ],
            ),
            textAlign: textAlign,
          ),
        ),
        bodyWidget: SizedBox(
          width: double.infinity,
          child: Text(
            'Contribute to discussions, help a neighbor, or start your own '
            'community project.',
            style: _sansBody,
            textAlign: textAlign,
          ),
        ),
        decoration: _pageDecoration(bodyAlignment: bodyAlign),
      ),
    ];

    return IntroductionScreen(
      globalBackgroundColor: AppTheme.publicCommonsCream,
      pages: pages,
      showSkipButton: false,
      showBackButton: false,
      skipOrBackFlex: 0,
      dotsFlex: 1,
      nextFlex: 2,
      controlsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      controlsMargin: EdgeInsets.zero,
      dotsDecorator: DotsDecorator(
        size: const Size.square(8),
        activeSize: const Size(26, 10),
        activeColor: _OnboardingColors.dotActive,
        color: _OnboardingColors.dotInactive,
        spacing: const EdgeInsets.symmetric(horizontal: 4),
        activeShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      next: const SizedBox.shrink(),
      overrideNext: (ctx, onPressed) => Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: _OnboardingColors.forest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          child: Text('Next', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      done: const SizedBox.shrink(),
      overrideDone: (ctx, onPressed) => Align(
        alignment: Alignment.centerRight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _OnboardingColors.forest.withValues(alpha: 0.2),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _OnboardingColors.forest,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              padding: const EdgeInsets.symmetric(horizontal: 28),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              elevation: 0,
            ),
            onPressed: onPressed,
            child: Text(
              'Get Started',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
      onDone: () => context.go('/sign-up'),
      globalFooter: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Already a member? ',
              style: GoogleFonts.inter(fontSize: 14, color: _OnboardingColors.bodyGrey),
            ),
            TextButton(
              onPressed: () => context.go('/sign-in'),
              style: TextButton.styleFrom(
                foregroundColor: _OnboardingColors.forest,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Log in',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _OnboardingColors.forest,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
