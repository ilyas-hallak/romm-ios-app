//
//  BigRomCardView.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//

import SwiftUI

// Custom shape for top-only rounded corners
struct TopRoundedRectangle: Shape {
    let radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: width - radius, y: 0))
        path.addArc(center: CGPoint(x: width - radius, y: radius), radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        
        return path
    }
}

struct BigRomCardView: View {
    let rom: Rom
    let platform: Platform?

    private var store: FavouritesStore { FavouritesStore.shared }

    // N64 covers are typically taller/narrower, so we use .fit to prevent overflow
    private var coverContentMode: ContentMode {
        rom.platformSlug?.lowercased() == "n64" ? .fit : .fill
    }

    init(rom: Rom, platform: Platform? = nil) {
        self.rom = rom
        self.platform = platform
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover Image Section
            ZStack(alignment: .topTrailing) {
                CachedKFImage(urlString: rom.urlCover) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: coverContentMode)
                } placeholder: {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "gamecontroller")
                                    .foregroundColor(.secondary)
                                    .font(.title)
                                Text("No Cover")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                // Clip wide covers to the card bounds so a `.fill` cover can't
                // overflow its frame and bleed into neighbouring grid cards.
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                // Favorite badge - top right
                if store.isFavourite(romId: rom.id) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(.red)
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                        )
                        .offset(x: -12, y: 12)
                }
            }
            
            // Information Section - Fixed height for consistency
            VStack(alignment: .leading, spacing: 4) {
                // Title - Extended to 3 lines
                VStack(alignment: .leading) {
                    Text(rom.name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                }
                .frame(height: 66, alignment: .top)

                Spacer()

                // Compact metadata row
                HStack(spacing: 8) {
                    // Platform Slug
                    if let platformSlug = rom.platformSlug {
                        Text(platformSlug)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // Release Year
                    if let year = rom.releaseYear {
                        Text(year.description)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Rating
                    if let rating = rom.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Bottom Row - Status Icons
                HStack {
                    RomStatusIcons(rom: rom)
                    Spacer()
                }
            }
            .frame(height: 100)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(
                    color: Color.primary.opacity(0.15),
                    radius: 8, x: 0, y: 4
                )
        )
        // Subtle border so each card reads as a distinct frame and wide
        // covers stay visually contained within their own card.
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
