import UIKit

/// On-Screen Controls mit Vektor-Assets (Button-PDFs aus Provenance, BSD-Lizenz
/// © Joseph Mattiello). Layout: PSX-Stil mit D-Pad links, △○✕□ rechts,
/// Schultertasten oben, Start/Select unten Mitte. Multi-Touch: ein Finger pro
/// Button; D-Pad erkennt 8 Richtungen + Diagonalen.
@MainActor
final class LibretroTouchControllerView: UIView {

    // MARK: - Face / shoulder button (single libretro button)

    private final class FaceButton: UIView {
        let button: LibretroABI.JoypadButton
        let normalImage: UIImageView
        let pressedImage: UIImageView
        let label: UILabel

        var isPressed: Bool = false {
            didSet {
                normalImage.isHidden = isPressed
                pressedImage.isHidden = !isPressed
            }
        }

        init(button: LibretroABI.JoypadButton,
             title: String,
             color: UIColor,
             thin: Bool = false,
             fontSize: CGFloat = 22) {
            self.button = button
            let normalName = thin ? "button-thin" : "button"
            let pressedName = thin ? "button-thin-pressed" : "button-pressed"
            normalImage = UIImageView(image: UIImage(named: "LibretroControls/\(normalName)"))
            pressedImage = UIImageView(image: UIImage(named: "LibretroControls/\(pressedName)"))
            label = UILabel()
            super.init(frame: .zero)
            isUserInteractionEnabled = false

            for v in [normalImage, pressedImage] {
                v.contentMode = .scaleAspectFit
                v.tintColor = color
                v.translatesAutoresizingMaskIntoConstraints = false
                addSubview(v)
                NSLayoutConstraint.activate([
                    v.topAnchor.constraint(equalTo: topAnchor),
                    v.bottomAnchor.constraint(equalTo: bottomAnchor),
                    v.leadingAnchor.constraint(equalTo: leadingAnchor),
                    v.trailingAnchor.constraint(equalTo: trailingAnchor)
                ])
            }
            pressedImage.isHidden = true

            label.text = title
            label.textColor = .white
            label.font = .systemFont(ofSize: fontSize, weight: .semibold)
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        required init?(coder: NSCoder) { fatalError() }
    }

    // MARK: - D-Pad (8-way single hit area)

    private final class DPadView: UIView {
        let imageView = UIImageView()
        var currentDirection: Direction = .none {
            didSet {
                guard currentDirection != oldValue else { return }
                imageView.image = UIImage(named: "LibretroControls/dPad-\(currentDirection.assetSuffix)")?
                    .withRenderingMode(.alwaysTemplate)
            }
        }

        enum Direction {
            case none, up, down, left, right, upLeft, upRight, downLeft, downRight
            var assetSuffix: String {
                switch self {
                case .none: return "None"
                case .up: return "Up"
                case .down: return "Down"
                case .left: return "Left"
                case .right: return "Right"
                case .upLeft: return "UpLeft"
                case .upRight: return "UpRight"
                case .downLeft: return "DownLeft"
                case .downRight: return "DownRight"
                }
            }
            var buttons: [LibretroABI.JoypadButton] {
                switch self {
                case .none: return []
                case .up: return [.up]
                case .down: return [.down]
                case .left: return [.left]
                case .right: return [.right]
                case .upLeft: return [.up, .left]
                case .upRight: return [.up, .right]
                case .downLeft: return [.down, .left]
                case .downRight: return [.down, .right]
                }
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            imageView.image = UIImage(named: "LibretroControls/dPad-None")?
                .withRenderingMode(.alwaysTemplate)
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = UIColor.white.withAlphaComponent(0.85)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Mappt einen Punkt im eigenen Koordinatensystem auf eine 8-Richtungs-Zone.
        /// Mittlere Deadzone -> .none. Diagonalen-Quadranten via Winkelschwellen.
        func direction(for point: CGPoint) -> Direction {
            let cx = bounds.midX
            let cy = bounds.midY
            let dx = point.x - cx
            let dy = point.y - cy
            let dead = bounds.width * 0.15
            if abs(dx) < dead && abs(dy) < dead { return .none }

            let angle = atan2(dy, dx) * 180 / .pi // -180..180, 0 = right
            switch angle {
            case -22.5..<22.5: return .right
            case 22.5..<67.5: return .downRight
            case 67.5..<112.5: return .down
            case 112.5..<157.5: return .downLeft
            case 157.5...180, -180 ..< -157.5: return .left
            case -157.5 ..< -112.5: return .upLeft
            case -112.5 ..< -67.5: return .up
            case -67.5 ..< -22.5: return .upRight
            default: return .none
            }
        }
    }

    // MARK: - State

    private var faceButtons: [FaceButton] = []
    private let dpad = DPadView()
    private var dpadTouch: UITouch?
    private var faceTouchMap: [ObjectIdentifier: FaceButton] = [:]

    private let menuButton = UIButton(type: .custom)
    var onMenuTapped: (() -> Void)?

    /// Vergrößert die Trefferzone für Face/Shoulder-Buttons (visuell unverändert).
    private let hitSlop: CGFloat = 28
    private let dpadSlop: CGFloat = 32
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    /// Slightly softer tick fired when a finger lifts off a button (like Ignited).
    private let releaseHaptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Init

    /// On-screen button layout per core family.
    enum Layout {
        case standard   // D-pad + △○✕□ + shoulders + Start/Select (PSX-style)
        case pcEngine   // D-pad + II / I + Select / Run
        case genesis    // D-pad + A / B / C + Mode / Start (Sega 3-button)
    }
    private let layout: Layout

    init(layout: Layout = .standard) {
        self.layout = layout
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        buildLayout()
        haptic.prepare()
        releaseHaptic.prepare()
    }

    /// Fires the release haptic if the user hasn't disabled it.
    private func fireReleaseHaptic() {
        guard HapticsPreferences.onRelease else { return }
        releaseHaptic.impactOccurred(intensity: 0.7)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        addSubview(dpad)

        menuButton.setImage(UIImage(named: "LibretroControls/button-menu"), for: .normal)
        menuButton.setImage(UIImage(named: "LibretroControls/button-menu-pressed"), for: .highlighted)
        menuButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        menuButton.imageView?.contentMode = .scaleAspectFit
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        addSubview(menuButton)

        switch layout {
        case .standard:
            addFace(.x, "△", .systemGreen)   // Triangle
            addFace(.a, "○", .systemRed)     // Circle
            addFace(.b, "✕", .systemBlue)    // Cross
            addFace(.y, "□", .systemPink)    // Square

            addFace(.l, "L1", .darkGray, thin: true, font: 16)
            addFace(.r, "R1", .darkGray, thin: true, font: 16)
            addFace(.l2, "L2", .darkGray, thin: true, font: 16)
            addFace(.r2, "R2", .darkGray, thin: true, font: 16)
            addFace(.select, "SELECT", .darkGray, thin: true, font: 12)
            addFace(.start, "START", .darkGray, thin: true, font: 12)

        case .pcEngine:
            // PC Engine pad: two face buttons + Select / Run. RetroPad A → I, B → II.
            addFace(.b, "II", .systemOrange)
            addFace(.a, "I", .systemRed)
            addFace(.select, "SELECT", .darkGray, thin: true, font: 12)
            addFace(.start, "RUN", .darkGray, thin: true, font: 14)

        case .genesis:
            // Sega 3-button pad. Genesis Plus GX RetroPad map: Y → A, B → B, A → C.
            // Select → Mode, Start → Start. Also covers SMS/GG (1 = B, 2 = A).
            addFace(.y, "A", .systemTeal)
            addFace(.b, "B", .systemBlue)
            addFace(.a, "C", .systemRed)
            addFace(.select, "MODE", .darkGray, thin: true, font: 13)
            addFace(.start, "START", .darkGray, thin: true, font: 12)
        }
    }

    private func addFace(_ button: LibretroABI.JoypadButton,
                         _ title: String,
                         _ color: UIColor,
                         thin: Bool = false,
                         font: CGFloat = 22) {
        let b = FaceButton(button: button, title: title, color: color, thin: thin, fontSize: font)
        addSubview(b)
        faceButtons.append(b)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > bounds.height {
            layoutLandscape()
        } else {
            layoutPortrait()
        }
    }

    private func face(_ b: LibretroABI.JoypadButton) -> FaceButton? {
        faceButtons.first { $0.button == b }
    }

    /// Positions the two PC Engine face buttons (II left, I right) centred in the face area.
    private func layoutPCEFaces(faceX: CGFloat, faceY: CGFloat, faceSize: CGFloat) {
        let btn = faceSize * 0.44
        let gap = faceSize * 0.14
        let totalW = btn * 2 + gap
        let startX = faceX + (faceSize - totalW) / 2
        let cy = faceY + (faceSize - btn) / 2
        face(.b)?.frame = CGRect(x: startX, y: cy, width: btn, height: btn)              // II
        face(.a)?.frame = CGRect(x: startX + btn + gap, y: cy, width: btn, height: btn)  // I
    }

    /// Positions the three Sega face buttons (A / B / C) in a centred row.
    private func layoutGenesisFaces(faceX: CGFloat, faceY: CGFloat, faceSize: CGFloat) {
        let btn = faceSize * 0.40
        let gap = faceSize * 0.06
        let totalW = btn * 3 + gap * 2
        let startX = faceX + (faceSize - totalW) / 2
        let cy = faceY + (faceSize - btn) / 2
        face(.y)?.frame = CGRect(x: startX, y: cy, width: btn, height: btn)                    // A
        face(.b)?.frame = CGRect(x: startX + btn + gap, y: cy, width: btn, height: btn)        // B
        face(.a)?.frame = CGRect(x: startX + 2 * (btn + gap), y: cy, width: btn, height: btn)  // C
    }

    private func layoutPortrait() {
        let w = bounds.width
        let h = bounds.height
        let safe = safeAreaInsets

        let dpadSize = min(w, h) * 0.32
        let dpadX = 24 + safe.left
        let dpadY = h - dpadSize - 32 - safe.bottom
        dpad.frame = CGRect(x: dpadX, y: dpadY, width: dpadSize, height: dpadSize)

        let faceSize = dpadSize
        let faceCellW = faceSize / 3
        let faceX = w - faceSize - 24 - safe.right
        let faceY = dpadY

        if layout == .standard {
            face(.x)?.frame = CGRect(x: faceX + faceCellW, y: faceY, width: faceCellW, height: faceCellW)
            face(.y)?.frame = CGRect(x: faceX, y: faceY + faceCellW, width: faceCellW, height: faceCellW)
            face(.a)?.frame = CGRect(x: faceX + 2 * faceCellW, y: faceY + faceCellW, width: faceCellW, height: faceCellW)
            face(.b)?.frame = CGRect(x: faceX + faceCellW, y: faceY + 2 * faceCellW, width: faceCellW, height: faceCellW)

            let shoulderW: CGFloat = 72
            let shoulderH: CGFloat = 36
            let shoulderGap: CGFloat = 8
            let shoulderTopY = 16 + safe.top
            let shoulderBottomY = shoulderTopY + shoulderH + shoulderGap
            face(.l)?.frame  = CGRect(x: 24 + safe.left, y: shoulderTopY, width: shoulderW, height: shoulderH)
            face(.l2)?.frame = CGRect(x: 24 + safe.left, y: shoulderBottomY, width: shoulderW, height: shoulderH)
            face(.r)?.frame  = CGRect(x: w - shoulderW - 24 - safe.right, y: shoulderTopY, width: shoulderW, height: shoulderH)
            face(.r2)?.frame = CGRect(x: w - shoulderW - 24 - safe.right, y: shoulderBottomY, width: shoulderW, height: shoulderH)
        } else if layout == .pcEngine {
            layoutPCEFaces(faceX: faceX, faceY: faceY, faceSize: faceSize)
        } else {
            layoutGenesisFaces(faceX: faceX, faceY: faceY, faceSize: faceSize)
        }

        let centerW: CGFloat = 80
        let centerH: CGFloat = 32
        let centerY = h - centerH - 24 - safe.bottom
        face(.select)?.frame = CGRect(x: w / 2 - centerW - 8, y: centerY, width: centerW, height: centerH)
        face(.start)?.frame  = CGRect(x: w / 2 + 8, y: centerY, width: centerW, height: centerH)

        let menuSize: CGFloat = 44
        menuButton.frame = CGRect(x: (w - menuSize) / 2, y: 16 + safe.top, width: menuSize, height: menuSize)
    }

    /// Landscape: D-Pad unten-links, Face-Buttons unten-rechts, L1/L2 oben links übereinander,
    /// R1/R2 oben rechts übereinander, Start/Select unten-mittig, Menu oben Mitte.
    private func layoutLandscape() {
        let w = bounds.width
        let h = bounds.height
        let safe = safeAreaInsets

        let dpadSize = min(w, h) * 0.42
        let edgePad: CGFloat = 16
        let dpadX = edgePad + safe.left
        let dpadY = h - dpadSize - edgePad - safe.bottom
        dpad.frame = CGRect(x: dpadX, y: dpadY, width: dpadSize, height: dpadSize)

        let faceSize = dpadSize
        let faceCellW = faceSize / 3
        let faceX = w - faceSize - edgePad - safe.right
        let faceY = dpadY

        if layout == .standard {
            face(.x)?.frame = CGRect(x: faceX + faceCellW, y: faceY, width: faceCellW, height: faceCellW)
            face(.y)?.frame = CGRect(x: faceX, y: faceY + faceCellW, width: faceCellW, height: faceCellW)
            face(.a)?.frame = CGRect(x: faceX + 2 * faceCellW, y: faceY + faceCellW, width: faceCellW, height: faceCellW)
            face(.b)?.frame = CGRect(x: faceX + faceCellW, y: faceY + 2 * faceCellW, width: faceCellW, height: faceCellW)

            // Schultertasten: L1 oben, L2 darunter — links. R1/R2 rechts.
            let shoulderW: CGFloat = 84
            let shoulderH: CGFloat = 40
            let shoulderGap: CGFloat = 8
            let shoulderTopY = edgePad + safe.top
            let shoulderBottomY = shoulderTopY + shoulderH + shoulderGap
            face(.l)?.frame  = CGRect(x: edgePad + safe.left, y: shoulderTopY, width: shoulderW, height: shoulderH)
            face(.l2)?.frame = CGRect(x: edgePad + safe.left, y: shoulderBottomY, width: shoulderW, height: shoulderH)
            face(.r)?.frame  = CGRect(x: w - shoulderW - edgePad - safe.right, y: shoulderTopY, width: shoulderW, height: shoulderH)
            face(.r2)?.frame = CGRect(x: w - shoulderW - edgePad - safe.right, y: shoulderBottomY, width: shoulderW, height: shoulderH)
        } else if layout == .pcEngine {
            layoutPCEFaces(faceX: faceX, faceY: faceY, faceSize: faceSize)
        } else {
            layoutGenesisFaces(faceX: faceX, faceY: faceY, faceSize: faceSize)
        }

        // Start/Select mittig unten.
        let centerW: CGFloat = 90
        let centerH: CGFloat = 34
        let centerY = h - centerH - edgePad - safe.bottom
        face(.select)?.frame = CGRect(x: w / 2 - centerW - 8, y: centerY, width: centerW, height: centerH)
        face(.start)?.frame  = CGRect(x: w / 2 + 8, y: centerY, width: centerW, height: centerH)

        // Menu zentriert oben.
        let menuSize: CGFloat = 44
        menuButton.frame = CGRect(x: (w - menuSize) / 2, y: edgePad + safe.top, width: menuSize, height: menuSize)
    }

    @objc private func menuTapped() {
        onMenuTapped?()
    }

    // MARK: - Touch

    private func faceButton(at point: CGPoint) -> FaceButton? {
        // Trefferzone wird via hitSlop ringsum vergrößert; Zonen überlappen sich
        // in der Praxis nicht stark, der nächstgelegene Treffer gewinnt.
        var best: (button: FaceButton, distance: CGFloat)?
        for b in faceButtons {
            let expanded = b.frame.insetBy(dx: -hitSlop, dy: -hitSlop)
            guard expanded.contains(point) else { continue }
            let dx = point.x - b.frame.midX
            let dy = point.y - b.frame.midY
            let dist = dx * dx + dy * dy
            if best == nil || dist < best!.distance {
                best = (b, dist)
            }
        }
        return best?.button
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { handle(touch: t, ended: false) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { handle(touch: t, ended: false) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { handle(touch: t, ended: true) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { handle(touch: t, ended: true) }
    }

    private func handle(touch: UITouch, ended: Bool) {
        let key = ObjectIdentifier(touch)
        let point = touch.location(in: self)

        // D-Pad ownership: claimed by first touch that lands inside dpad.frame
        // (mit dpadSlop), released when that touch lifts (slide outside is allowed).
        if dpadTouch == nil, !ended,
           dpad.frame.insetBy(dx: -dpadSlop, dy: -dpadSlop).contains(point) {
            dpadTouch = touch
        }
        if dpadTouch === touch {
            if ended {
                applyDpad(.none)
                dpadTouch = nil
            } else {
                let local = convert(point, to: dpad)
                applyDpad(dpad.direction(for: local))
            }
            return
        }

        // Face / shoulder buttons.
        let prev = faceTouchMap[key]
        let hit = ended ? nil : faceButton(at: point)
        if prev !== hit {
            if let prev {
                let stillHeld = faceTouchMap.contains { $0.key != key && $0.value === prev }
                if !stillHeld {
                    prev.isPressed = false
                    LibretroFrontend.shared.setButton(prev.button, pressed: false)
                    fireReleaseHaptic()
                }
            }
            if let hit {
                hit.isPressed = true
                LibretroFrontend.shared.setButton(hit.button, pressed: true)
                haptic.impactOccurred(intensity: 1.0)
            }
        }
        if ended {
            faceTouchMap.removeValue(forKey: key)
        } else {
            faceTouchMap[key] = hit
        }
    }

    private var currentDpadButtons: Set<LibretroABI.JoypadButton> = []

    private func applyDpad(_ direction: DPadView.Direction) {
        let previous = dpad.currentDirection
        dpad.currentDirection = direction
        let target = Set(direction.buttons)
        for b in currentDpadButtons.subtracting(target) {
            LibretroFrontend.shared.setButton(b, pressed: false)
        }
        for b in target.subtracting(currentDpadButtons) {
            LibretroFrontend.shared.setButton(b, pressed: true)
        }
        currentDpadButtons = target
        // Leichter Tick bei Richtungswechsel; weicher Release-Tick beim Loslassen.
        if direction != previous {
            if direction == .none {
                if previous != .none { fireReleaseHaptic() }
            } else {
                haptic.impactOccurred(intensity: 0.85)
            }
        }
    }
}
