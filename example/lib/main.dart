// The controls from https://boringavatars.com/, drawn by this package.
//
// Every avatar on screen goes through `BoringAvatar`, which rasterises in
// software — not `flutter_svg`, which draws all six variants wrongly, and not
// `Canvas`, which would make the pixels depend on the GPU. So what this demo
// shows is what the package guarantees: the same bytes upstream produces.

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const BoringAvatarsDemo());

/// The palette from upstream's own front page, plus three to switch between.
const _palettes = <List<String>>[
  ['#00686C', '#32C2B9', '#EDECB3', '#FAD928', '#FF9915'],
  ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
  ['#0A0310', '#49007E', '#FF005B', '#FF7D10', '#FFB238'],
  ['#FFAD08', '#EDD75A', '#73B06F', '#0C8F8F', '#405059'],
];

const _names = <String>[
  'Mary Baker',
  'Amelia Earhart',
  'Sarah Winnemucca',
  'Margaret Hamilton',
  'Lucy Stone',
  'Mahalia Jackson',
  'Ada Lovelace',
  'Grace Hopper',
];

const _ink = Color(0xFF123B3D);
const _wash = Color(0xFFDCE9E6);
const _panel = Color(0xFFF7F9F8);

class BoringAvatarsDemo extends StatelessWidget {
  const BoringAvatarsDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'boring_avatars',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _ink),
      scaffoldBackgroundColor: _wash,
      useMaterial3: true,
    ),
    home: const _Home(),
  );
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  BoringAvatarsVariant _variant = BoringAvatarsVariant.beam;
  int _palette = 0;
  bool _square = false;

  List<String> get _colors => _palettes[_palette];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Masthead(),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _VariantPicker(
                        colors: _colors,
                        selected: _variant,
                        square: _square,
                        onChanged: (v) => setState(() => _variant = v),
                      ),
                      _PalettePicker(
                        colors: _colors,
                        onShuffle: () => setState(
                          () => _palette = (_palette + 1) % _palettes.length,
                        ),
                      ),
                      _ShapePicker(
                        square: _square,
                        onChanged: (s) => setState(() => _square = s),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Gallery(variant: _variant, colors: _colors, square: _square),
                  const SizedBox(height: 16),
                  _CodeStrip(
                    variant: _variant,
                    colors: _colors,
                    square: _square,
                  ),
                  const SizedBox(height: 16),
                  _SvgStrip(
                    variant: _variant,
                    colors: _colors,
                    square: _square,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'boring_avatars',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: _ink,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'A bit-exact Dart port. Same name, same palette, same pixels as the '
        'npm package — rasterised here in software.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _ink.withValues(alpha: 0.7), height: 1.4),
      ),
    ],
  );
}

/// The rounded white container the three control groups share.
class _Pill extends StatelessWidget {
  const _Pill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: _ink.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// Six real avatars, not six icons — the picker is drawn by the thing it picks.
class _VariantPicker extends StatelessWidget {
  const _VariantPicker({
    required this.colors,
    required this.selected,
    required this.square,
    required this.onChanged,
  });

  final List<String> colors;
  final BoringAvatarsVariant selected;
  final bool square;
  final ValueChanged<BoringAvatarsVariant> onChanged;

  @override
  Widget build(BuildContext context) => _Pill(
    children: [
      for (final variant in BoringAvatarsVariant.renderable)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: variant.name,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onChanged(variant),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: variant == selected ? _ink : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: BoringAvatar(
                  name: 'Mary Baker',
                  colors: colors,
                  size: 30,
                  version: BoringAvatarsVersion.v1_6_1,
                  variant: variant,
                  square: square,
                  semanticLabel: '${variant.name} sample',
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.colors, required this.onShuffle});

  final List<String> colors;
  final VoidCallback onShuffle;

  static Color _parse(String hex) =>
      Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

  @override
  Widget build(BuildContext context) => _Pill(
    children: [
      for (final hex in colors)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _parse(hex),
              shape: BoxShape.circle,
            ),
          ),
        ),
      const SizedBox(width: 4),
      Tooltip(
        message: 'Next palette',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onShuffle,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _ink.withValues(alpha: 0.06),
            ),
            child: Icon(Icons.shuffle, size: 16, color: _ink),
          ),
        ),
      ),
    ],
  );
}

class _ShapePicker extends StatelessWidget {
  const _ShapePicker({required this.square, required this.onChanged});

  final bool square;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _Pill(
    children: [
      _shape(isSquare: false),
      const SizedBox(width: 4),
      _shape(isSquare: true),
    ],
  );

  Widget _shape({required bool isSquare}) => InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: () => onChanged(isSquare),
    child: Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: square == isSquare
            ? _ink.withValues(alpha: 0.10)
            : Colors.transparent,
      ),
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(isSquare ? 2 : 999),
        ),
      ),
    ),
  );
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.variant,
    required this.colors,
    required this.square,
  });

  final BoringAvatarsVariant variant;
  final List<String> colors;
  final bool square;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 20,
      runSpacing: 24,
      children: [
        for (final name in _names)
          SizedBox(
            width: 108,
            child: Column(
              children: [
                BoringAvatar(
                  name: name,
                  colors: colors,
                  size: 72,
                  version: BoringAvatarsVersion.v1_6_1,
                  variant: variant,
                  square: square,
                  semanticLabel: name,
                ),
                const SizedBox(height: 10),
                Text(
                  name.split(' ').first,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// The call that produced everything above, copyable.
class _CodeStrip extends StatelessWidget {
  const _CodeStrip({
    required this.variant,
    required this.colors,
    required this.square,
  });

  final BoringAvatarsVariant variant;
  final List<String> colors;
  final bool square;

  String get _code =>
      'BoringAvatar(\n'
      "  name: 'Mary Baker',\n"
      '  colors: const [${colors.map((c) => "'$c'").join(', ')}],\n'
      '  size: 72,\n'
      '  version: BoringAvatarsVersion.v1_6_1,\n'
      '  variant: BoringAvatarsVariant.${variant.name},\n'
      '${square ? '  square: true,\n' : ''}'
      ')';

  @override
  Widget build(BuildContext context) => _Snippet(
    label: 'The widget',
    body: _code,
    caption:
        'version is required and has no default — a default of "newest" would '
        'redraw every avatar in your app on a dependency upgrade.',
  );
}

/// The other half of the public surface, and the thing the port is *about*:
/// the document upstream emits, byte for byte.
class _SvgStrip extends StatelessWidget {
  const _SvgStrip({
    required this.variant,
    required this.colors,
    required this.square,
  });

  final BoringAvatarsVariant variant;
  final List<String> colors;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final svg = boringAvatarSvg(
      name: 'Mary Baker',
      colors: colors,
      size: 72,
      version: BoringAvatarsVersion.v1_6_1,
      variant: variant,
      square: square,
    );
    return _Snippet(
      label: 'The same avatar as a document',
      body: svg,
      caption:
          '${svg.length} characters, identical to what boring-avatars 1.6.1 '
          'renders for these inputs. The avatars above are this document '
          'rasterised in software.',
    );
  }
}

class _Snippet extends StatelessWidget {
  const _Snippet({
    required this.label,
    required this.body,
    required this.caption,
  });

  final String label;
  final String body;
  final String caption;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            _CopyButton(text: body),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SelectableText(
            body,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['Consolas', 'Menlo', 'Courier New'],
              fontSize: 12.5,
              height: 1.5,
              color: _ink,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          caption,
          style: TextStyle(
            color: _ink.withValues(alpha: 0.55),
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _copied ? 'Copied' : 'Copy',
    icon: Icon(
      _copied ? Icons.check : Icons.copy_rounded,
      size: 18,
      color: _ink.withValues(alpha: 0.7),
    ),
    onPressed: () async {
      await Clipboard.setData(ClipboardData(text: widget.text));
      if (!mounted) return;
      setState(() => _copied = true);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _copied = false);
    },
  );
}
