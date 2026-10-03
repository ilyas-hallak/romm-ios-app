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

    // MARK: - Analog stick

    /// A fixed stick: the knob follows the finger inside the ring and springs
    /// back to the centre when the finger lifts.
    private final class ThumbstickView: UIView {
        let stick: LibretroABI.AnalogStick
        private let ring = CAShapeLayer()
        private let knob = CAShapeLayer()
        private var vector = CGVector.zero

        init(stick: LibretroABI.AnalogStick) {
            self.stick = stick
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            ring.fillColor = UIColor.white.withAlphaComponent(0.08).cgColor
            ring.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
            ring.lineWidth = 2
            knob.fillColor = UIColor.white.withAlphaComponent(0.3).cgColor
            knob.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
            knob.lineWidth = 2
            layer.addSublayer(ring)
            layer.addSublayer(knob)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).cgPath
            let knobSize = bounds.width * 0.5
            knob.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: knobSize, height: knobSize)).cgPath
            placeKnob()
        }

        /// Moves the knob without the implicit layer animation, it has to stick
        /// to the finger.
        func show(_ vector: CGVector) {
            self.vector = vector
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            placeKnob()
            CATransaction.commit()
        }

        private func placeKnob() {
            let knobSize = bounds.width * 0.5
            let travel = (bounds.width - knobSize) / 2
            knob.frame = CGRect(
                x: bounds.midX - knobSize / 2 + vector.dx * travel,
                y: bounds.midY - knobSize / 2 + vector.dy * travel,
                width: knobSize,
                height: knobSize
            )
        }
    }

    /// Deflection for a finger at `point` on a stick filling `bounds`, -1 to 1
    /// on both axes with negative being left and up. Full deflection is reached
    /// a little inside the ring, a thumb should not have to chase the edge.
    nonisolated static func stickVector(for point: CGPoint, in bounds: CGRect) -> CGVector {
        let reach = bounds.width * 0.35
        guard reach > 0 else { return .zero }
        var dx = (point.x - bounds.midX) / reach
        var dy = (point.y - bounds.midY) / reach
        let length = (dx * dx + dy * dy).squareRoot()
        if length > 1 {
            dx /= length
            dy /= length
        }
        return CGVector(dx: dx, dy: dy)
    }

    // MARK: - State

    private var faceButtons: [FaceButton] = []
    private var thumbsticks: [ThumbstickView] = []
    private var stickTouchMap: [ObjectIdentifier: ThumbstickView] = [:]
    private let dpad = DPadView()
    private var dpadTouch: UITouch?
    private var faceTouchMap: [ObjectIdentifier: FaceButton] = [:]

    private let menuButton = UIButton(type: .custom)
    var onMenuTapped: (() -> Void)?

    /// Where a press goes. The running core by default, the pad on a second
    /// phone points it at the network instead.
    var onButton: (LibretroABI.JoypadButton, Bool) -> Void = { button, pressed in
        LibretroFrontend.shared.setButton(button, pressed: pressed)
    }

    /// Where a stick moves to, with both axes from -1 to 1.
    var onStick: (LibretroABI.AnalogStick, Double, Double) -> Void = { stick, x, y in
        LibretroFrontend.shared.setStick(stick, x: x, y: y)
    }

    /// Hides the button that opens the in-game menu, for a pad that has no game
    /// of its own to pause.
    var isMenuButtonHidden: Bool {
        get { menuButton.isHidden }
        set { menuButton.isHidden = newValue }
    }

    /// Vergrößert die Trefferzone für Face/Shoulder-Buttons (visuell unverändert).
    private let hitSlop: CGFloat = 28
    private let dpadSlop: CGFloat = 32
    private let stickSlop: CGFloat = 20
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    /// Slightly softer tick fired when a finger lifts off a button (like Ignited).
    private let releaseHaptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Init

    /// On-screen button layout per core family.
    enum Layout {
        case standard   // D-pad + △○✕□ + shoulders + Start/Select (PSX-style)
        case dualShock  // standard plus two analog sticks
        case psp        // D-pad + △○✕□ + one analog stick + L / R + Start/Select
        case pcEngine   // D-pad + II / I + Select / Run
        case genesis    // D-pad + A / B / C + Mode / Start (Sega 3-button)
        case dreamcast  // D-pad + A / B / X / Y diamond + L / R triggers + Start

        var sticks: [LibretroABI.AnalogStick] {
            switch self {
            case .dualShock: return [.left, .right]
            case .psp: return [.left]
            case .standard, .pcEngine, .genesis, .dreamcast: return []
            }
        }

        /// Shoulder buttons as left/right pairs, top row first.
        var shoulderRows: [(left: LibretroABI.JoypadButton, right: LibretroABI.JoypadButton)] {
            switch self {
            case .standard, .dualShock: return [(.l, .r), (.l2, .r2)]
            case .psp: return [(.l, .r)]
            case .dreamcast: return [(.l2, .r2)]
            case .pcEngine, .genesis: return []
            }
        }

        static func forCore(_ core: LibretroCore, analogSticks: Bool) -> Layout {
            switch core {
            case .pcsxRearmed: return analogSticks ? .dualShock : .standard
            case .ppsspp: return .psp
            case .beetlePCEFast: return .pcEngine
            case .genesisPlusGX: return .genesis
            case .flycast: return .dreamcast
            }
        }
    }

    /// Swapping the layout lets go of everything held first, a button that
    /// vanishes mid press would otherwise stay down in the core.
    var layout: Layout {
        didSet {
            guard layout != oldValue else { return }
            releaseAll()
            faceButtons.forEach { $0.removeFromSuperview() }
            faceButtons.removeAll()
            thumbsticks.forEach { $0.removeFromSuperview() }
            thumbsticks.removeAll()
            buildLayout()
            setNeedsLayout()
        }
    }

    init(layout: Layout = .standard) {
        self.layout = layout
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        addSubview(dpad)
        menuButton.setImage(UIImage(named: "LibretroControls/button-menu"), for: .normal)
        menuButton.setImage(UIImage(named: "LibretroControls/button-menu-pressed"), for: .highlighted)
        menuButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        menuButton.imageView?.contentMode = .scaleAspectFit
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        addSubview(menuButton)
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
        switch layout {
        case .standard, .dualShock:
            addPlayStationFaces()
            addFace(.l, "L1", .darkGray, thin: true, font: 16)
            addFace(.r, "R1", .darkGray, thin: true, font: 16)
            addFace(.l2, "L2", .darkGray, thin: true, font: 16)
            addFace(.r2, "R2", .darkGray, thin: true, font: 16)
            addFace(.select, "SELECT", .darkGray, thin: true, font: 12)
            addFace(.start, "START", .darkGray, thin: true, font: 12)

        case .psp:
            addPlayStationFaces()
            addFace(.l, "L", .darkGray, thin: true, font: 16)
            addFace(.r, "R", .darkGray, thin: true, font: 16)
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

        case .dreamcast:
            // Dreamcast pad: A / B / X / Y in a diamond (Y top, X left, B right,
            // A bottom), two analog triggers, Start, and no Select at all.
            // Flycast's RetroPad map: X → Y, Y → X, A → B, B → A, L2 → L, R2 → R.
            addFace(.x, "Y", .systemOrange)
            addFace(.y, "X", .systemGreen)
            addFace(.a, "B", .systemBlue)
            addFace(.b, "A", .systemRed)
            addFace(.l2, "L", .darkGray, thin: true, font: 16)
            addFace(.r2, "R", .darkGray, thin: true, font: 16)
            addFace(.start, "START", .darkGray, thin: true, font: 12)
        }

        for stick in layout.sticks {
            let view = ThumbstickView(stick: stick)
            addSubview(view)
            thumbsticks.append(view)
        }
    }

    private func addPlayStationFaces() {
        addFace(.x, "△", .systemGreen)   // Triangle
        addFace(.a, "○", .systemRed)     // Circle
        addFace(.b, "✕", .systemBlue)    // Cross
        addFace(.y, "□", .systemPink)    // Square
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

    /// Positions four face buttons in a diamond on a 3×3 grid: RetroPad X top,
    /// Y left, A right, B bottom. Shared by the PlayStation, PSP and Dreamcast
    /// layouts, which only differ in their labels.
    private func layoutDiamondFaces(faceX: CGFloat, faceY: CGFloat, faceSize: CGFloat) {
        let cell = faceSize / 3
        face(.x)?.frame = CGRect(x: faceX + cell, y: faceY, width: cell, height: cell)
        face(.y)?.frame = CGRect(x: faceX, y: faceY + cell, width: cell, height: cell)
        face(.a)?.frame = CGRect(x: faceX + 2 * cell, y: faceY + cell, width: cell, height: cell)
        face(.b)?.frame = CGRect(x: faceX + cell, y: faceY + 2 * cell, width: cell, height: cell)
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
        // The row is wider than the face area. Centring it pushed C past the
        // right screen edge, so it ends at the area's right edge instead.
        let startX = faceX + faceSize - totalW
        let cy = faceY + (faceSize - btn) / 2
        face(.y)?.frame = CGRect(x: startX, y: cy, width: btn, height: btn)                    // A
        face(.b)?.frame = CGRect(x: startX + btn + gap, y: cy, width: btn, height: btn)        // B
        face(.a)?.frame = CGRect(x: startX + 2 * (btn + gap), y: cy, width: btn, height: btn)  // C
    }

    private func layoutPortrait() {
        let w = bounds.width
        let h = bounds.height
        let safe = safeAreaInsets

        let centerW: CGFloat = 80
        let centerH: CGFloat = 32
        let centerY = h - centerH - 24 - safe.bottom
        layoutCenterButtons(width: centerW, height: centerH, y: centerY)

        let dpadSize = min(w, h) * 0.32
        let stickSize = min(dpadSize * 0.75, 150)
        let sticksTop = layoutSticks(size: stickSize, centerWidth: centerW, centerY: centerY)

        // With sticks the D-pad and the face buttons move up to make room for
        // them, the sticks sit inwards and would overlap otherwise.
        let dpadBottom = sticksTop.map { $0 - 8 } ?? h - 32 - safe.bottom
        let dpadY = dpadBottom - dpadSize
        dpad.frame = CGRect(x: 24 + safe.left, y: dpadY, width: dpadSize, height: dpadSize)
        layoutFaces(faceX: w - dpadSize - 24 - safe.right, faceY: dpadY, faceSize: dpadSize)

        layoutShoulders(width: 72, height: 36, top: 16 + safe.top, left: 24 + safe.left, right: w - 24 - safe.right)

        let menuSize: CGFloat = 44
        menuButton.frame = CGRect(x: (w - menuSize) / 2, y: 16 + safe.top, width: menuSize, height: menuSize)
    }

    /// Landscape: D-Pad unten-links, Face-Buttons unten-rechts, L1/L2 oben links übereinander,
    /// R1/R2 oben rechts übereinander, Start/Select unten-mittig, Menu oben Mitte.
    private func layoutLandscape() {
        let w = bounds.width
        let h = bounds.height
        let safe = safeAreaInsets
        let edgePad: CGFloat = 16

        let centerW: CGFloat = 90
        let centerH: CGFloat = 34
        let centerY = h - centerH - edgePad - safe.bottom
        layoutCenterButtons(width: centerW, height: centerH, y: centerY)

        let dpadSize = min(w, h) * 0.42
        let dpadY = h - dpadSize - edgePad - safe.bottom
        dpad.frame = CGRect(x: edgePad + safe.left, y: dpadY, width: dpadSize, height: dpadSize)
        layoutFaces(faceX: w - dpadSize - edgePad - safe.right, faceY: dpadY, faceSize: dpadSize)

        _ = layoutSticks(size: min(dpadSize * 0.62, 150), centerWidth: centerW, centerY: centerY)

        layoutShoulders(width: 84, height: 40, top: edgePad + safe.top, left: edgePad + safe.left, right: w - edgePad - safe.right)

        let menuSize: CGFloat = 44
        menuButton.frame = CGRect(x: (w - menuSize) / 2, y: edgePad + safe.top, width: menuSize, height: menuSize)
    }

    private func layoutFaces(faceX: CGFloat, faceY: CGFloat, faceSize: CGFloat) {
        switch layout {
        case .standard, .dualShock, .psp, .dreamcast:
            layoutDiamondFaces(faceX: faceX, faceY: faceY, faceSize: faceSize)
        case .pcEngine:
            layoutPCEFaces(faceX: faceX, faceY: faceY, faceSize: faceSize)
        case .genesis:
            layoutGenesisFaces(faceX: faceX, faceY: faceY, faceSize: faceSize)
        }
    }

    /// Select and Start side by side at the bottom centre. Without Select,
    /// Start stands alone and belongs in the middle.
    private func layoutCenterButtons(width: CGFloat, height: CGFloat, y: CGFloat) {
        let w = bounds.width
        let startX = face(.select) == nil ? (w - width) / 2 : w / 2 + 8
        face(.select)?.frame = CGRect(x: w / 2 - width - 8, y: y, width: width, height: height)
        face(.start)?.frame = CGRect(x: startX, y: y, width: width, height: height)
    }

    /// Sticks sit just above Select and Start, centred on their outer edges,
    /// where a thumb reaches them from the D-pad or the face buttons. Returns
    /// the top of the sticks, `nil` for a layout without any.
    private func layoutSticks(size: CGFloat, centerWidth: CGFloat, centerY: CGFloat) -> CGFloat? {
        guard !thumbsticks.isEmpty else { return nil }
        let top = centerY - 8 - size
        let offset = 8 + centerWidth
        for view in thumbsticks {
            let centerX = view.stick == .left ? bounds.width / 2 - offset : bounds.width / 2 + offset
            view.frame = CGRect(x: centerX - size / 2, y: top, width: size, height: size)
        }
        return top
    }

    /// Shoulder rows from the top down, left pair member against the left edge.
    private func layoutShoulders(width: CGFloat, height: CGFloat, top: CGFloat, left: CGFloat, right: CGFloat) {
        for (row, pair) in layout.shoulderRows.enumerated() {
            let y = top + CGFloat(row) * (height + 8)
            face(pair.left)?.frame = CGRect(x: left, y: y, width: width, height: height)
            face(pair.right)?.frame = CGRect(x: right - width, y: y, width: width, height: height)
        }
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

        if handleStick(touch: touch, at: point, ended: ended) { return }

        // D-Pad ownership: claimed by first touch that lands inside dpad.frame
        // (mit dpadSlop), released when that touch lifts (slide outside is allowed).
        // Ein Touch, der direkt auf einem Button liegt, gehoert diesem Button:
        // sonst verschluckt der dpadSlop-Rand angrenzende Buttons (z.B. Start).
        if dpadTouch == nil, !ended,
           dpad.frame.insetBy(dx: -dpadSlop, dy: -dpadSlop).contains(point),
           !faceButtons.contains(where: { $0.frame.contains(point) }),
           !thumbsticks.contains(where: { $0.frame.contains(point) }) {
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
                    onButton(prev.button, false)
                    fireReleaseHaptic()
                }
            }
            if let hit {
                hit.isPressed = true
                onButton(hit.button, true)
                haptic.impactOccurred(intensity: 1.0)
            }
        }
        if ended {
            faceTouchMap.removeValue(forKey: key)
        } else {
            faceTouchMap[key] = hit
        }
    }

    /// A stick belongs to the finger that first landed on it and follows that
    /// finger anywhere until it lifts. Only a new touch can take a stick, a
    /// finger sliding over from a button keeps pressing buttons. A touch right
    /// on a button or the dpad stays theirs, the slop must not swallow Start.
    private func handleStick(touch: UITouch, at point: CGPoint, ended: Bool) -> Bool {
        let key = ObjectIdentifier(touch)
        if stickTouchMap[key] == nil {
            guard touch.phase == .began, !ended,
                  !dpad.frame.contains(point),
                  !faceButtons.contains(where: { $0.frame.contains(point) }),
                  let free = thumbsticks.first(where: { view in
                      view.frame.insetBy(dx: -stickSlop, dy: -stickSlop).contains(point)
                          && !stickTouchMap.values.contains { $0 === view }
                  })
            else { return false }
            stickTouchMap[key] = free
            haptic.impactOccurred(intensity: 0.6)
        }
        guard let view = stickTouchMap[key] else { return false }
        if ended {
            stickTouchMap.removeValue(forKey: key)
            moveStick(view, to: .zero)
        } else {
            moveStick(view, to: Self.stickVector(for: convert(point, to: view), in: view.bounds))
        }
        return true
    }

    private func moveStick(_ view: ThumbstickView, to vector: CGVector) {
        view.show(vector)
        onStick(view.stick, Double(vector.dx), Double(vector.dy))
    }

    /// Lets go of every button and stick this view is holding.
    private func releaseAll() {
        applyDpad(.none)
        dpadTouch = nil
        for button in Set(faceTouchMap.values.map(\.button)) {
            onButton(button, false)
        }
        faceTouchMap.removeAll()
        for view in stickTouchMap.values {
            moveStick(view, to: .zero)
        }
        stickTouchMap.removeAll()
    }

    private var currentDpadButtons: Set<LibretroABI.JoypadButton> = []

    private func applyDpad(_ direction: DPadView.Direction) {
        let previous = dpad.currentDirection
        dpad.currentDirection = direction
        let target = Set(direction.buttons)
        for b in currentDpadButtons.subtracting(target) {
            onButton(b, false)
        }
        for b in target.subtracting(currentDpadButtons) {
            onButton(b, true)
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
