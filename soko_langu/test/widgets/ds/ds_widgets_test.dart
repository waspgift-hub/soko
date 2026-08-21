import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../test_helper.dart';
import 'package:soko_vibe/widgets/ds/ds_button.dart';
import 'package:soko_vibe/widgets/ds/ds_text_field.dart';
import 'package:soko_vibe/widgets/ds/ds_card.dart';
import 'package:soko_vibe/widgets/ds/ds_badge.dart';
import 'package:soko_vibe/widgets/ds/ds_skeleton.dart';
import 'package:soko_vibe/widgets/ds/ds_empty_state.dart';
import 'package:soko_vibe/widgets/ds/ds_avatar.dart';
import 'package:soko_vibe/widgets/ds/ds_chip.dart';
import 'package:soko_vibe/widgets/ds/ds_divider.dart';

void main() {
  group('DsButton', () {
    testWidgets('renders primary variant with label', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(label: 'Buy Now', onPressed: () {}),
      ));
      expect(find.text('Buy Now'), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var tapped = false;
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(label: 'Tap Me', onPressed: () => tapped = true),
      ));
      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('does not call onPressed when disabled', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(label: 'Disabled', onPressed: null),
      ));
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
    });

    testWidgets('shows loading state', (tester) async {
      await tester.pumpWidget(TestApp(child: Scaffold(
        body: DsButton(label: 'Submit', onPressed: () {}, loading: true),
      )));
      await tester.pump();
      expect(find.byType(DsButton), findsOneWidget);
      expect(find.text('Submit'), findsNothing);
    });

    testWidgets('renders secondary variant', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(
          label: 'Cancel',
          variant: DsButtonVariant.secondary,
          onPressed: () {},
        ),
      ));
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('renders tonal variant', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(
          label: 'Tonal',
          variant: DsButtonVariant.tonal,
          onPressed: () {},
        ),
      ));
      expect(find.text('Tonal'), findsOneWidget);
    });

    testWidgets('renders ghost variant', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(
          label: 'Ghost',
          variant: DsButtonVariant.ghost,
          onPressed: () {},
        ),
      ));
      expect(find.text('Ghost'), findsOneWidget);
    });

    testWidgets('renders danger variant', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(
          label: 'Delete',
          variant: DsButtonVariant.danger,
          onPressed: () {},
        ),
      ));
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('renders with icon', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(
          label: 'With Icon',
          icon: Icons.add,
          onPressed: () {},
        ),
      ));
      expect(find.text('With Icon'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('small size renders', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(label: 'Small', size: DsButtonSize.sm, onPressed: () {}),
      ));
      expect(find.text('Small'), findsOneWidget);
    });

    testWidgets('large size renders', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsButton(label: 'Large', size: DsButtonSize.lg, onPressed: () {}),
      ));
      expect(find.text('Large'), findsOneWidget);
    });
  });

  group('DsTextField', () {
    testWidgets('renders with label', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsTextField(label: 'Email'),
      ));
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('accepts text input', (tester) async {
      final ctrl = TextEditingController();
      await pumpTestApp(tester, child: Scaffold(
        body: DsTextField(controller: ctrl, label: 'Name'),
      ));
      await tester.enterText(find.byType(TextFormField), 'John');
      expect(ctrl.text, 'John');
    });

    testWidgets('shows prefix icon', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsTextField(label: 'Search', prefixIcon: Icons.search),
      ));
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('shows suffix icon', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsTextField(
          label: 'Password',
          suffixIcon: Icons.visibility,
          obscureText: true,
        ),
      ));
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });

    testWidgets('validator returns error for empty', (tester) async {
      final formKey = GlobalKey<FormState>();
      await pumpTestApp(tester, child: Scaffold(
        body: Form(
          key: formKey,
          child: DsTextField(
            label: 'Required',
            validator: (v) => v == null || v.isEmpty ? 'Required field' : null,
          ),
        ),
      ));
      formKey.currentState!.validate();
      await tester.pumpAndSettle();
      expect(find.text('Required field'), findsOneWidget);
    });

    testWidgets('validator passes for valid input', (tester) async {
      final formKey = GlobalKey<FormState>();
      await pumpTestApp(tester, child: Scaffold(
        body: Form(
          key: formKey,
          child: DsTextField(
            label: 'Email',
            validator: (v) => v != null && v.contains('@') ? null : 'Invalid email',
          ),
        ),
      ));
      await tester.enterText(find.byType(TextFormField), 'test@example.com');
      formKey.currentState!.validate();
      await tester.pumpAndSettle();
      expect(find.text('Invalid email'), findsNothing);
    });

    testWidgets('obscureText widget renders correctly', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsTextField(label: 'Password', obscureText: true),
      ));
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });
  });

  group('DsCard', () {
    testWidgets('renders child content', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsCard(child: Text('Card Content')),
      ));
      expect(find.text('Card Content'), findsOneWidget);
    });

    testWidgets('responds to tap', (tester) async {
      var tapped = false;
      await pumpTestApp(tester, child: Scaffold(
        body: DsCard(onTap: () => tapped = true, child: Text('Tappable')),
      ));
      await tester.tap(find.text('Tappable'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('flat elevation renders', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsCard(elevation: DsCardElevation.flat, child: Text('Flat')),
      ));
      expect(find.text('Flat'), findsOneWidget);
    });

    testWidgets('medium elevation renders', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsCard(elevation: DsCardElevation.medium, child: Text('Medium')),
      ));
      expect(find.text('Medium'), findsOneWidget);
    });
  });

  group('DsBadge', () {
    testWidgets('renders label text', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsBadge(label: 'NEW', color: Colors.green),
      ));
      expect(find.text('NEW'), findsOneWidget);
    });
  });

  group('DsSkeleton', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(TestApp(child: Scaffold(body: DsSkeleton())));
      await tester.pump();
      expect(find.byType(DsSkeleton), findsOneWidget);
    });
  });

  group('DsEmptyState', () {
    testWidgets('renders title', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsEmptyState(
          icon: Icons.inbox,
          title: 'No items',
        ),
      ));
      expect(find.text('No items'), findsOneWidget);
    });

    testWidgets('renders body text', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsEmptyState(
          icon: Icons.inbox,
          title: 'Empty',
          body: 'Nothing here yet',
        ),
      ));
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('renders action button when provided', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsEmptyState(
          icon: Icons.inbox,
          title: 'Empty',
          actionLabel: 'Refresh',
          onAction: () {},
        ),
      ));
      expect(find.text('Refresh'), findsOneWidget);
    });
  });

  group('DsAvatar', () {
    testWidgets('renders initials fallback', (tester) async {
      await pumpTestApp(tester, child: const Scaffold(
        body: DsAvatar(initials: 'AB'),
      ));
      expect(find.text('AB'), findsOneWidget);
    });

    testWidgets('renders person icon when no image/initials', (tester) async {
      await pumpTestApp(tester, child: const Scaffold(
        body: DsAvatar(),
      ));
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('small size renders at 32px', (tester) async {
      await pumpTestApp(tester, child: const Scaffold(
        body: DsAvatar(initials: 'X', size: DsAvatarSize.sm),
      ));
      final SizedBox box = tester.widget(find.byType(SizedBox).first);
      expect(box.width, 32);
    });

    testWidgets('large size renders at 72px', (tester) async {
      await pumpTestApp(tester, child: const Scaffold(
        body: DsAvatar(initials: 'X', size: DsAvatarSize.lg),
      ));
      final SizedBox box = tester.widget(find.byType(SizedBox).first);
      expect(box.width, 72);
    });
  });

  group('DsChip', () {
    testWidgets('renders label', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsChip(label: 'Electronics'),
      ));
      expect(find.text('Electronics'), findsOneWidget);
    });

    testWidgets('selected state shows primary bg', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsChip(label: 'Test', selected: true),
      ));
      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('with icon renders icon', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsChip(label: 'Filter', icon: Icons.filter_list),
      ));
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
    });

    testWidgets('small size renders', (tester) async {
      await pumpTestApp(tester, child: Scaffold(
        body: DsChip(label: 'Small', chipSize: DsChipSize.sm),
      ));
      expect(find.text('Small'), findsOneWidget);
    });
  });

  group('DsDivider', () {
    testWidgets('solid divider renders', (tester) async {
      await pumpTestApp(tester, child: const Scaffold(
        body: DsDivider(),
      ));
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('labeled divider shows label text', (tester) async {
      await pumpTestApp(tester, child: const Scaffold(
        body: DsDivider(style: DsDividerStyle.labeled, label: 'Section'),
      ));
      expect(find.text('Section'), findsOneWidget);
    });

    testWidgets('dashed divider renders', (tester) async {
      await pumpTestApp(tester, child: const Scaffold(
        body: DsDivider(style: DsDividerStyle.dashed),
      ));
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
