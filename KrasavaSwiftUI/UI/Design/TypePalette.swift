import SwiftUI

/// Палитра типов занятий.
///
/// Цвета собраны из двух источников: собственные акценты (подобраны под
/// читаемость на маленьких бейджах, как в оригинальном приложении) и
/// пользовательские переопределения. Пользователь всегда главнее: если он
/// назначил типу свой цвет, приложение и виджет обязаны показать именно его —
/// поэтому переопределения уезжают в снапшот виджета.
enum TypePalette {

    /// Стандартный акцент типа. Разделение на светлую и тёмную схемы не
    /// косметическое: на тёмном фоне нужен светлый акцент и наоборот, иначе
    /// контраст падает ниже комфортного.
    static func defaultHex(for type: LessonType, dark: Bool) -> UInt32 {
        switch type {
        case .lecture:      dark ? 0x8FB8FF : 0x2F5FBF
        case .practice:     dark ? 0x78D99D : 0x1B7F45
        case .lab:          dark ? 0xE3B368 : 0x8A5A00
        case .exam:         dark ? 0xE58C8C : 0xA02B2B
        case .credit:       dark ? 0x7FD8CC : 0x0F766E
        case .coursework:   dark ? 0xE9C46A : 0xA16207
        case .consultation: dark ? 0x9FA8FF : 0x4338CA
        case .individual:   dark ? 0xB6BAC4 : 0x5C606B
        case .other:        dark ? 0xC79BFF : 0x7E22CE
        case .additional:   dark ? 0xF4A8C8 : 0xBE185D
        }
    }

    static func color(
        for type: LessonType,
        overrides: UserOverrides,
        scheme: ColorScheme
    ) -> Color {
        let dark = scheme == .dark
        let hex = overrides.color(for: type)?.hex ?? defaultHex(for: type, dark: dark)
        return Color(rgb: hex)
    }

    /// Мягкая заливка бейджа того же тона.
    static func badgeBackground(
        for type: LessonType,
        overrides: UserOverrides,
        scheme: ColorScheme
    ) -> Color {
        color(for: type, overrides: overrides, scheme: scheme).opacity(scheme == .dark ? 0.22 : 0.14)
    }
}

extension Color {
    /// Цвет из 0xRRGGBB. Палитра задаётся числами, чтобы те же значения можно
    /// было положить в снапшот виджета без конвертаций.
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}