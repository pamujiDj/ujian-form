import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// View dengan latar gradasi.
final class GradientView: UIView {
    override class var layerClass: AnyClass { return CAGradientLayer.self }

    init(colors: [UInt32], vertical: Bool) {
        super.init(frame: .zero)
        let g = layer as! CAGradientLayer
        g.colors = colors.map { UIColor(hex: $0).cgColor }
        if vertical {
            g.startPoint = CGPoint(x: 0.5, y: 0)
            g.endPoint = CGPoint(x: 0.5, y: 1)
        } else {
            g.startPoint = CGPoint(x: 0, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 0.5)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Tombol dengan gradasi biru-ungu.
final class GradientButton: UIButton {
    override class var layerClass: AnyClass { return CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let g = layer as! CAGradientLayer
        g.colors = [UIColor(hex: 0x06B6D4).cgColor, UIColor(hex: 0x3B82F6).cgColor, UIColor(hex: 0xA855F7).cgColor]
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        layer.cornerRadius = 26
        clipsToBounds = true
        setTitleColor(.white, for: .normal)
        titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.8 : 1 }
    }
}

/// Label dengan jarak tepi (untuk banner dan penanda).
final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let r = super.textRect(forBounds: bounds.inset(by: insets), limitedToNumberOfLines: numberOfLines)
        return CGRect(x: r.origin.x - insets.left,
                      y: r.origin.y - insets.top,
                      width: r.width + insets.left + insets.right,
                      height: r.height + insets.top + insets.bottom)
    }
}
