import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────

class ProxmoxFormSectionHeader extends StatelessWidget {
  final AppThemeData colors;
  final String title;
  final IconData icon;
  final String? subtitle;

  const ProxmoxFormSectionHeader({
    super.key,
    required this.colors,
    required this.title,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: colors.primary, size: 14),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Form Field
// ─────────────────────────────────────────────

class ProxmoxFormField extends StatefulWidget {
  final AppThemeData colors;
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final IconData? icon;
  final TextInputType type;
  final bool obscure;
  final String? Function(String?)? validator;
  final String? helperText;

  const ProxmoxFormField({
    super.key,
    required this.colors,
    required this.label,
    required this.ctrl,
    required this.hint,
    this.icon,
    this.type = TextInputType.text,
    this.obscure = false,
    this.validator,
    this.helperText,
  });

  @override
  State<ProxmoxFormField> createState() => _ProxmoxFormFieldState();
}

class _ProxmoxFormFieldState extends State<ProxmoxFormField> {
  bool _obscured = true;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isObscurable = widget.obscure;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.curve,
              decoration: BoxDecoration(
                color: widget.colors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _focused
                      ? widget.colors.primary.withValues(alpha: 0.6)
                      : widget.colors.hairline,
                  width: _focused ? 1.5 : 1,
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: widget.colors.primary.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : [],
              ),
              child: TextFormField(
                controller: widget.ctrl,
                keyboardType: widget.type,
                obscureText: isObscurable ? _obscured : false,
                style:
                    TextStyle(color: widget.colors.textPrimary, fontSize: 14),
                validator: widget.validator ??
                    (v) => v == null || v.isEmpty
                        ? '${widget.label} boş olamaz'
                        : null,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                  prefixIcon: widget.icon != null
                      ? Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(widget.icon,
                              color: _focused
                                  ? widget.colors.primary
                                  : widget.colors.textMuted,
                              size: 18),
                        )
                      : null,
                  suffixIcon: isObscurable
                      ? GestureDetector(
                          onTap: () => setState(() => _obscured = !_obscured),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              _obscured
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: widget.colors.textMuted,
                              size: 18,
                            ),
                          ),
                        )
                      : null,
                  labelStyle: TextStyle(
                    color: _focused
                        ? widget.colors.primary
                        : widget.colors.textSecondary,
                    fontSize: 13,
                  ),
                  hintStyle:
                      TextStyle(color: widget.colors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: Colors.transparent,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: widget.colors.error, width: 1.5)),
                  focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: widget.colors.error, width: 1.5)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            if (widget.helperText != null)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 4),
                child: Text(
                  widget.helperText!,
                  style:
                      TextStyle(color: widget.colors.textMuted, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Dropdown Field
// ─────────────────────────────────────────────

class ProxmoxDropdownField extends StatelessWidget {
  final AppThemeData colors;
  final String label;
  final IconData icon;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final Function(String?) onChanged;

  const ProxmoxDropdownField({
    super.key,
    required this.colors,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.hairline),
        ),
        child: DropdownButtonFormField<String>(
          initialValue: value,
          dropdownColor: colors.bgCard,
          style: TextStyle(color: colors.textPrimary, fontSize: 14),
          icon:
              Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted),
          borderRadius: BorderRadius.circular(14),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: colors.textMuted, size: 18),
            labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
            filled: true,
            fillColor: Colors.transparent,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.primary, width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Node Selector
// ─────────────────────────────────────────────

class ProxmoxNodeSelector extends StatelessWidget {
  final AppThemeData colors;
  final List<dynamic> nodes;
  final String? selected;
  final Function(String?) onSelect;

  const ProxmoxNodeSelector({
    super.key,
    required this.colors,
    required this.nodes,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: nodes.map((n) {
        final name = n['node'] as String;
        // '_id' (sunucu+node bileşik kimliği) seçim/karşılaştırma için —
        // iki sunucu aynı node adını raporlarsa 'name' TEK BAŞINA
        // benzersiz değildir. Görüntülemede hâlâ ham 'name' kullanılıyor.
        final id = n['_id'] as String? ?? name;
        final isSelected = selected == id;
        final isOnline = n['status'] == 'online';

        return GestureDetector(
          onTap: () => onSelect(id),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.12)
                  : colors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.5)
                    : colors.hairline,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? colors.success : colors.error,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.dns_rounded,
                  color: isSelected ? colors.primary : colors.textMuted,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: TextStyle(
                    color: isSelected ? colors.primary : colors.textSecondary,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────
// Info Box
// ─────────────────────────────────────────────

class ProxmoxInfoBox extends StatelessWidget {
  final AppThemeData colors;
  final IconData icon;
  final Color color;
  final String text;
  final String? title;

  const ProxmoxInfoBox({
    super.key,
    required this.colors,
    required this.icon,
    required this.color,
    required this.text,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  text,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Switch Tile
// ─────────────────────────────────────────────

class ProxmoxSwitchTile extends StatelessWidget {
  final AppThemeData colors;
  final String title;
  final String? subtitle;
  final bool value;
  final Function(bool) onChanged;
  final IconData? icon;

  const ProxmoxSwitchTile({
    super.key,
    required this.colors,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: value ? colors.primary.withValues(alpha: 0.06) : colors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? colors.primary.withValues(alpha: 0.25)
                : colors.hairline,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: value
                      ? colors.primary.withValues(alpha: 0.12)
                      : colors.bgCardLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon,
                    color: value ? colors.primary : colors.textMuted, size: 14),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: value ? colors.textPrimary : colors.textSecondary,
                      fontSize: 13,
                      fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            // Custom switch
            AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.curve,
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                color: value ? colors.primary : colors.bgCardLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: value
                      ? colors.primary
                      : colors.hairline,
                ),
              ),
              child: AnimatedAlign(
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Slider Field
// ─────────────────────────────────────────────

class ProxmoxSliderField extends StatelessWidget {
  final AppThemeData colors;
  final String label;
  final String unit;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Function(double) onChanged;
  final IconData? icon;

  const ProxmoxSliderField({
    super.key,
    required this.colors,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: colors.textMuted, size: 14),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: colors.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '${value.toInt()} $unit',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.bgCardLight,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.12),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${min.toInt()} $unit',
                  style: TextStyle(color: colors.textMuted, fontSize: 10)),
              Text('${max.toInt()} $unit',
                  style: TextStyle(color: colors.textMuted, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
