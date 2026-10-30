import SwiftUI
import UIKit

extension Color {
    /// Обратное преобразование в 0xRRGGBB — нужно `ColorPicker`, чтобы
    /// сохранить выбранный пользователем цвет в настройках.
    ///
    /// Работает через sRGB-компоненты: палитра задаётся в sRGB, и обратное
    /// преобразование должно быть в том же пространстве, иначе цвет после
    /// сохранения и перезапуска слегка «уезжает».
    var rgbHex: UInt32? {
        let resolved = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        let r = UInt32((min(max(red, 0), 1) * 255).rounded())
        let g = UInt32((min(max(green, 0), 1) * 255).rounded())
        let b = UInt32((min(max(blue, 0), 1) * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}