#if !APP_STORE
import SwiftUI

/// Keeps the menu clear of a division region reported by its presentation.
struct DuoMenuRegion<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            let region = menuFrame(in: geometry)
            content
                .frame(width: region.width, height: region.height)
                .position(x: region.midX, y: region.midY)
        }
    }

    private func menuFrame(in geometry: GeometryProxy) -> CGRect {
        if #available(iOS 27.1, *) {
            return DuoMenuLayout.frame(
                in: geometry.size,
                division: geometry.reservedRegions(kind: .division).first?.frame
            )
        }
        return CGRect(origin: .zero, size: geometry.size)
    }
}

enum DuoMenuLayout {
    static func frame(in size: CGSize, division: CGRect?) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size)
        guard let division, !division.isNull, !division.isInfinite,
              division.maxX >= 0, division.minX <= size.width,
              division.maxY >= 0, division.minY <= size.height else { return bounds }

        let region: CGRect
        if division.width >= division.height {
            let y = min(size.height, max(0, division.maxY))
            region = CGRect(x: 0, y: y, width: size.width, height: size.height - y)
        } else {
            let x = min(size.width, max(0, division.maxX))
            region = CGRect(x: x, y: 0, width: size.width - x, height: size.height)
        }
        return region.isEmpty ? bounds : region
    }
}
#endif
