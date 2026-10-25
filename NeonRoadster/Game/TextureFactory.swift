import RealityKit
import UIKit
import simd

struct FacadeTextures {
    let base: TextureResource
    let metallic: TextureResource
    let roughness: TextureResource
    let lit: TextureResource
}

struct FacadeStyle {
    let name: String
    let body: UIColor
    let base: UIColor
    let frame: UIColor
    let glass: UIColor
    let litWarm: [UIColor]
    let litCool: [UIColor]
    let columns: Int
    let rows: Int
    let windowInset: CGFloat
    let windowTopInset: CGFloat
    let metalness: Float
    let roughness: Float
}

/// All city/car textures are generated on the main actor at launch. Keeping
/// them procedural means the repo has no licensed image assets and the whole
/// look can be tuned from code.
@MainActor
enum TextureFactory {
    static let styles: [FacadeStyle] = [
        FacadeStyle(
            name: "glass",
            body: UIColor(red: 0.075, green: 0.11, blue: 0.15, alpha: 1),
            base: UIColor(red: 0.10, green: 0.17, blue: 0.22, alpha: 1),
            frame: UIColor(red: 0.16, green: 0.22, blue: 0.26, alpha: 1),
            glass: UIColor(red: 0.035, green: 0.075, blue: 0.11, alpha: 1),
            litWarm: [
                UIColor(red: 1.0, green: 0.82, blue: 0.53, alpha: 1),
                UIColor(red: 1.0, green: 0.68, blue: 0.35, alpha: 1)
            ],
            litCool: [
                UIColor(red: 0.62, green: 0.86, blue: 1.0, alpha: 1),
                UIColor(red: 0.40, green: 0.72, blue: 1.0, alpha: 1)
            ],
            columns: 8,
            rows: 16,
            windowInset: 2,
            windowTopInset: 2,
            metalness: 0.72,
            roughness: 0.16
        ),
        FacadeStyle(
            name: "stone",
            body: UIColor(red: 0.29, green: 0.27, blue: 0.24, alpha: 1),
            base: UIColor(red: 0.42, green: 0.39, blue: 0.34, alpha: 1),
            frame: UIColor(red: 0.53, green: 0.48, blue: 0.40, alpha: 1),
            glass: UIColor(red: 0.06, green: 0.075, blue: 0.095, alpha: 1),
            litWarm: [
                UIColor(red: 1.0, green: 0.78, blue: 0.47, alpha: 1),
                UIColor(red: 1.0, green: 0.62, blue: 0.30, alpha: 1),
                UIColor(red: 1.0, green: 0.90, blue: 0.70, alpha: 1)
            ],
            litCool: [
                UIColor(red: 0.68, green: 0.86, blue: 1.0, alpha: 1),
                UIColor(red: 0.45, green: 0.68, blue: 0.95, alpha: 1)
            ],
            columns: 8,
            rows: 16,
            windowInset: 4,
            windowTopInset: 4,
            metalness: 0.0,
            roughness: 0.82
        ),
        FacadeStyle(
            name: "brick",
            body: UIColor(red: 0.26, green: 0.13, blue: 0.10, alpha: 1),
            base: UIColor(red: 0.40, green: 0.19, blue: 0.14, alpha: 1),
            frame: UIColor(red: 0.55, green: 0.29, blue: 0.20, alpha: 1),
            glass: UIColor(red: 0.055, green: 0.065, blue: 0.08, alpha: 1),
            litWarm: [
                UIColor(red: 1.0, green: 0.76, blue: 0.43, alpha: 1),
                UIColor(red: 1.0, green: 0.58, blue: 0.28, alpha: 1)
            ],
            litCool: [
                UIColor(red: 0.62, green: 0.82, blue: 1.0, alpha: 1)
            ],
            columns: 8,
            rows: 16,
            windowInset: 5,
            windowTopInset: 5,
            metalness: 0.0,
            roughness: 0.9
        ),
        FacadeStyle(
            name: "modern",
            body: UIColor(red: 0.46, green: 0.48, blue: 0.49, alpha: 1),
            base: UIColor(red: 0.62, green: 0.63, blue: 0.62, alpha: 1),
            frame: UIColor(red: 0.73, green: 0.72, blue: 0.69, alpha: 1),
            glass: UIColor(red: 0.04, green: 0.06, blue: 0.075, alpha: 1),
            litWarm: [
                UIColor(red: 1.0, green: 0.84, blue: 0.56, alpha: 1),
                UIColor(red: 1.0, green: 0.70, blue: 0.38, alpha: 1)
            ],
            litCool: [
                UIColor(red: 0.70, green: 0.88, blue: 1.0, alpha: 1),
                UIColor(red: 0.50, green: 0.74, blue: 1.0, alpha: 1)
            ],
            columns: 8,
            rows: 16,
            windowInset: 3,
            windowTopInset: 3,
            metalness: 0.05,
            roughness: 0.62
        )
    ]

    // MARK: - Sky

    static func skyEnvironment() -> EnvironmentResource? {
        let width = 2_048
        let height = 1_024
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor(red: 0.025, green: 0.045, blue: 0.12, alpha: 1).cgColor,
                UIColor(red: 0.10, green: 0.12, blue: 0.26, alpha: 1).cgColor,
                UIColor(red: 0.36, green: 0.22, blue: 0.34, alpha: 1).cgColor,
                UIColor(red: 0.82, green: 0.38, blue: 0.29, alpha: 1).cgColor,
                UIColor(red: 1.0, green: 0.62, blue: 0.32, alpha: 1).cgColor,
                UIColor(red: 1.0, green: 0.82, blue: 0.52, alpha: 1).cgColor,
                UIColor(red: 0.95, green: 0.55, blue: 0.34, alpha: 1).cgColor,
                UIColor(red: 0.28, green: 0.20, blue: 0.28, alpha: 1).cgColor,
                UIColor(red: 0.035, green: 0.035, blue: 0.075, alpha: 1).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 0.18, 0.34, 0.44, 0.49, 0.515, 0.55, 0.68, 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: CGFloat(height)),
                    options: []
                )
            }

            let sunCenter = CGPoint(
                x: CGFloat(width) * 0.245,
                y: CGFloat(height) * 0.515
            )

            // Broad atmospheric glow around the low sun.
            for step in stride(from: 1.0, through: 0.0, by: -0.08) {
                let radius = CGFloat(520 * step)
                let alpha = 0.018 + 0.014 * (1 - step)
                cg.setFillColor(
                    UIColor(red: 1.0, green: 0.68, blue: 0.34, alpha: alpha).cgColor
                )
                cg.fillEllipse(
                    in: CGRect(
                        x: sunCenter.x - radius,
                        y: sunCenter.y - radius * 0.62,
                        width: radius * 2,
                        height: radius * 1.24
                    )
                )
            }

            // Sun disk with a hot core.
            let sunRadius: CGFloat = 28
            cg.setFillColor(UIColor(red: 1.0, green: 0.93, blue: 0.72, alpha: 0.98).cgColor)
            cg.fillEllipse(
                in: CGRect(
                    x: sunCenter.x - sunRadius,
                    y: sunCenter.y - sunRadius,
                    width: sunRadius * 2,
                    height: sunRadius * 2
                )
            )
            cg.setFillColor(UIColor(red: 1.0, green: 1.0, blue: 0.92, alpha: 0.95).cgColor)
            cg.fillEllipse(
                in: CGRect(
                    x: sunCenter.x - sunRadius * 0.48,
                    y: sunCenter.y - sunRadius * 0.48,
                    width: sunRadius * 0.96,
                    height: sunRadius * 0.96
                )
            )

            var rng = SeededGenerator(seed: 0x5E7_5E7)

            // Long, soft dusk cloud bands. Warm rims and cool undersides.
            for index in 0..<34 {
                let band = CGFloat(index) / 34
                let y = CGFloat(height) * (0.22 + band * 0.32)
                let width = CGFloat.random(in: 220...760, using: &rng)
                let height = CGFloat.random(in: 9...32, using: &rng)
                let x = CGFloat.random(in: -120...CGFloat(width), using: &rng)
                let warm = 0.06 + (1 - band) * 0.10
                let color = UIColor(
                    red: 1.0,
                    green: 0.58 + band * 0.18,
                    blue: 0.38 + band * 0.12,
                    alpha: warm
                )
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(
                    in: CGRect(x: x, y: y, width: width, height: height)
                )
                cg.setFillColor(
                    UIColor(red: 0.18, green: 0.20, blue: 0.34, alpha: 0.045).cgColor
                )
                cg.fillEllipse(
                    in: CGRect(
                        x: x + width * 0.08,
                        y: y + height * 0.35,
                        width: width * 0.84,
                        height: height * 0.55
                    )
                )
            }

            // Faint stars high in the indigo.
            for _ in 0..<260 {
                let x = CGFloat.random(in: 0...CGFloat(width), using: &rng)
                let y = CGFloat.random(in: 0...CGFloat(height) * 0.28, using: &rng)
                let radius = CGFloat.random(in: 0.4...1.35, using: &rng)
                let alpha = CGFloat.random(in: 0.12...0.55, using: &rng)
                cg.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                cg.fillEllipse(
                    in: CGRect(x: x, y: y, width: radius, height: radius)
                )
            }

            // Warm city haze along the horizon.
            for _ in 0..<18 {
                let x = CGFloat.random(in: 0...CGFloat(width), using: &rng)
                let w = CGFloat.random(in: 130...420, using: &rng)
                let y = CGFloat(height) * CGFloat.random(in: 0.50...0.55, using: &rng)
                cg.setFillColor(
                    UIColor(red: 1.0, green: 0.48, blue: 0.26, alpha: 0.035).cgColor
                )
                cg.fillEllipse(
                    in: CGRect(x: x - w * 0.5, y: y, width: w, height: w * 0.15)
                )
            }
        }

        guard let cgImage = image.cgImage else { return nil }
        if #available(iOS 27.0, *) {
            var options = EnvironmentResource.CreateOptions(
                samplingQuality: .normal,
                specularCubeDimension: 256
            )
            options.compression = .default
            return try? EnvironmentResource(
                equirectangular: cgImage,
                options: options
            )
        }
        return try? EnvironmentResource(
            equirectangular: cgImage,
            withName: "sunset-sky"
        )
    }

    // MARK: - Facades

    static func facades() -> [FacadeTextures] {
        styles.enumerated().compactMap { index, style in
            makeFacade(style: style, seed: UInt64(3_000 + index))
        }
    }

    private static func makeFacade(style: FacadeStyle, seed: UInt64) -> FacadeTextures? {
        let width = 256
        let height = 512
        let size = CGSize(width: width, height: height)

        let baseRenderer = UIGraphicsImageRenderer(
            size: size,
            format: opaqueFormat()
        )
        let metalRenderer = UIGraphicsImageRenderer(
            size: size,
            format: opaqueFormat()
        )
        let roughRenderer = UIGraphicsImageRenderer(
            size: size,
            format: opaqueFormat()
        )
        let litRenderer = UIGraphicsImageRenderer(
            size: size,
            format: clearFormat()
        )

        var rng = SeededGenerator(seed: seed)
        let cellW = size.width / CGFloat(style.columns)
        let cellH = size.height / CGFloat(style.rows)

        struct Window {
            let rect: CGRect
            let lit: Bool
            let color: UIColor
            let glass: UIColor
        }

        var windows: [Window] = []
        for row in 0..<style.rows {
            for column in 0..<style.columns {
                let rect = CGRect(
                    x: CGFloat(column) * cellW + style.windowInset,
                    y: CGFloat(row) * cellH + style.windowTopInset,
                    width: cellW - style.windowInset * 2,
                    height: cellH - style.windowTopInset - 3
                )
                let isLit = Int.random(in: 0..<100, using: &rng) < 56
                let warm = Int.random(in: 0..<100, using: &rng) < 62
                let palette = warm ? style.litWarm : style.litCool
                let color = palette[Int.random(in: 0..<palette.count, using: &rng)]
                    .withAlphaComponent(CGFloat.random(in: 0.55...1.0, using: &rng))
                let glass = style.glass.withAlphaComponent(
                    CGFloat.random(in: 0.65...1.0, using: &rng)
                )
                windows.append(
                    Window(rect: rect, lit: isLit, color: color, glass: glass)
                )
            }
        }

        let baseImage = baseRenderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(style.base.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Stone / brick grain.
            for _ in 0..<2_400 {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let w = CGFloat.random(in: 0.4...2.2, using: &rng)
                let h = CGFloat.random(in: 0.4...1.5, using: &rng)
                let light = Bool.random(using: &rng)
                cg.setFillColor(
                    (light
                        ? UIColor.white.withAlphaComponent(0.018)
                        : UIColor.black.withAlphaComponent(0.022)).cgColor
                )
                cg.fill(CGRect(x: x, y: y, width: w, height: h))
            }

            // Horizontal floor bands and vertical mullions.
            for row in 0...style.rows {
                let y = CGFloat(row) * cellH
                cg.setFillColor(style.frame.withAlphaComponent(0.34).cgColor)
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: 1.2))
            }
            for column in 0...style.columns {
                let x = CGFloat(column) * cellW
                cg.setFillColor(style.frame.withAlphaComponent(0.22).cgColor)
                cg.fill(CGRect(x: x, y: 0, width: 1.1, height: size.height))
            }

            // Window recess shadow + glass.
            for window in windows {
                cg.setFillColor(UIColor.black.withAlphaComponent(0.30).cgColor)
                cg.fill(window.rect.insetBy(dx: -1.4, dy: -1.4))
                cg.setFillColor(window.glass.cgColor)
                cg.fill(window.rect)

                // A cool reflected sky stripe on the upper half of the glass.
                cg.setFillColor(
                    UIColor(red: 0.55, green: 0.72, blue: 0.90, alpha: 0.075).cgColor
                )
                cg.fill(
                    CGRect(
                        x: window.rect.minX,
                        y: window.rect.minY,
                        width: window.rect.width,
                        height: window.rect.height * 0.42
                    )
                )

                // Thin highlight on the sill.
                cg.setFillColor(style.frame.withAlphaComponent(0.55).cgColor)
                cg.fill(
                    CGRect(
                        x: window.rect.minX,
                        y: window.rect.maxY,
                        width: window.rect.width,
                        height: 1
                    )
                )
            }

            // Ground-floor storefront band.
            cg.setFillColor(UIColor(red: 0.035, green: 0.035, blue: 0.045, alpha: 1).cgColor)
            cg.fill(
                CGRect(
                    x: 0,
                    y: size.height - cellH * 0.9,
                    width: size.width,
                    height: cellH * 0.9
                )
            )
            cg.setFillColor(UIColor(red: 1.0, green: 0.62, blue: 0.28, alpha: 0.55).cgColor)
            for column in 0..<style.columns {
                let x = CGFloat(column) * cellW + 3
                cg.fill(
                    CGRect(
                        x: x,
                        y: size.height - cellH * 0.62,
                        width: cellW - 6,
                        height: cellH * 0.36
                    )
                )
            }
        }

        let metalImage = metalRenderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(white: 0.02, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            for window in windows {
                cg.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)
                cg.fill(window.rect)
            }
        }

        let roughImage = roughRenderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(white: CGFloat(style.roughness), alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            for window in windows {
                cg.setFillColor(UIColor(white: 0.07, alpha: 1).cgColor)
                cg.fill(window.rect)
            }
        }

        let litImage = litRenderer.image { context in
            let cg = context.cgContext
            cg.clear(CGRect(origin: .zero, size: size))
            for window in windows where window.lit {
                cg.setFillColor(window.color.cgColor)
                cg.fill(window.rect)
                cg.setFillColor(UIColor.white.withAlphaComponent(0.22).cgColor)
                cg.fill(
                    CGRect(
                        x: window.rect.minX,
                        y: window.rect.minY,
                        width: window.rect.width,
                        height: 1.2
                    )
                )
            }
        }

        guard
            let baseCG = baseImage.cgImage,
            let metalCG = metalImage.cgImage,
            let roughCG = roughImage.cgImage,
            let litCG = litImage.cgImage,
            let base = try? TextureResource(
                image: baseCG,
                withName: "facade-\(style.name)-base",
                options: .init(semantic: .color)
            ),
            let metallic = try? TextureResource(
                image: metalCG,
                withName: "facade-\(style.name)-metal",
                options: .init(semantic: .raw)
            ),
            let roughness = try? TextureResource(
                image: roughCG,
                withName: "facade-\(style.name)-rough",
                options: .init(semantic: .raw)
            ),
            let lit = try? TextureResource(
                image: litCG,
                withName: "facade-\(style.name)-lit",
                options: .init(semantic: .color)
            )
        else { return nil }

        return FacadeTextures(
            base: base,
            metallic: metallic,
            roughness: roughness,
            lit: lit
        )
    }

    // MARK: - Ground / water / light textures

    static func asphalt() -> TextureResource? {
        makeNoiseTexture(
            name: "asphalt",
            size: 512,
            base: UIColor(red: 0.055, green: 0.058, blue: 0.065, alpha: 1),
            grain: 0.06
        )
    }

    static func concrete() -> TextureResource? {
        makeNoiseTexture(
            name: "concrete",
            size: 512,
            base: UIColor(red: 0.24, green: 0.235, blue: 0.225, alpha: 1),
            grain: 0.10
        )
    }

    static func waterNormal() -> TextureResource? {
        let width = 512
        let height = 512
        let size = CGSize(width: width, height: height)
        let format = opaqueFormat()
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(
                UIColor(red: 0.50, green: 0.50, blue: 1.0, alpha: 1).cgColor
            )
            cg.fill(CGRect(origin: .zero, size: size))
            var rng = SeededGenerator(seed: 0x77A7E)
            for _ in 0..<180 {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let w = CGFloat.random(in: 20...110, using: &rng)
                let h = CGFloat.random(in: 4...18, using: &rng)
                let dx = CGFloat.random(in: -0.16...0.16, using: &rng)
                let dy = CGFloat.random(in: -0.06...0.06, using: &rng)
                cg.setFillColor(
                    UIColor(
                        red: 0.5 + dx,
                        green: 0.5 + dy,
                        blue: 1.0,
                        alpha: 1
                    ).cgColor
                )
                cg.fillEllipse(
                    in: CGRect(x: x, y: y, width: w, height: h)
                )
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(
            image: cgImage,
            withName: "water-normal",
            options: .init(semantic: .normal)
        )
    }

    static func glow() -> TextureResource? {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size, format: clearFormat())
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.clear(CGRect(origin: .zero, size: size))
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let colors = [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0.55).cgColor,
                UIColor(white: 1, alpha: 0.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.28, 1]
            ) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: size.width * 0.5,
                    options: []
                )
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(
            image: cgImage,
            withName: "glow",
            options: .init(semantic: .color)
        )
    }

    static func haze() -> TextureResource? {
        let size = CGSize(width: 512, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size, format: clearFormat())
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.clear(CGRect(origin: .zero, size: size))
            let colors = [
                UIColor(red: 1.0, green: 0.63, blue: 0.40, alpha: 0.0).cgColor,
                UIColor(red: 1.0, green: 0.63, blue: 0.40, alpha: 0.42).cgColor,
                UIColor(red: 1.0, green: 0.72, blue: 0.54, alpha: 0.22).cgColor,
                UIColor(red: 1.0, green: 0.80, blue: 0.66, alpha: 0.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.54, 0.68, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
            var rng = SeededGenerator(seed: 0xA1E)
            for _ in 0..<80 {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: size.height * 0.48...size.height * 0.72, using: &rng)
                let w = CGFloat.random(in: 40...160, using: &rng)
                cg.setFillColor(
                    UIColor(red: 1.0, green: 0.75, blue: 0.55, alpha: 0.02).cgColor
                )
                cg.fillEllipse(
                    in: CGRect(x: x, y: y, width: w, height: w * 0.12)
                )
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(
            image: cgImage,
            withName: "haze",
            options: .init(semantic: .color)
        )
    }

    static func carbon() -> TextureResource? {
        let size = 256
        let format = opaqueFormat()
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size),
            format: format
        )
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(red: 0.025, green: 0.027, blue: 0.032, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for row in 0..<16 {
                for column in 0..<16 {
                    let light = (row + column).isMultiple(of: 2)
                    cg.setFillColor(
                        (light
                            ? UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.45)
                            : UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 0.35)).cgColor
                    )
                    cg.fill(
                        CGRect(
                            x: CGFloat(column) * 16,
                            y: CGFloat(row) * 16,
                            width: 16,
                            height: 16
                        )
                    )
                }
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(
            image: cgImage,
            withName: "carbon",
            options: .init(semantic: .color)
        )
    }

    static func label(text: String, accent: UIColor, wide: Bool = false) -> TextureResource? {
        let size = CGSize(width: wide ? 512 : 384, height: 96)
        let renderer = UIGraphicsImageRenderer(size: size, format: clearFormat())
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.clear(CGRect(origin: .zero, size: size))
            let rect = CGRect(
                x: 4,
                y: 4,
                width: size.width - 8,
                height: size.height - 8
            )
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 18)
            cg.addPath(path.cgPath)
            cg.setFillColor(UIColor(red: 0.015, green: 0.02, blue: 0.03, alpha: 0.78).cgColor)
            cg.fillPath()
            cg.addPath(path.cgPath)
            cg.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(1.5)
            cg.strokePath()

            let font = UIFont.monospacedSystemFont(ofSize: 31, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.92)
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let textSize = string.size()
            string.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) * 0.5,
                    y: (size.height - textSize.height) * 0.5
                )
            )
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(
            image: cgImage,
            withName: "label-\(text)",
            options: .init(semantic: .color)
        )
    }

    static func billboard(text: String, accent: UIColor, background: UIColor) -> TextureResource? {
        let size = CGSize(width: 512, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size, format: opaqueFormat())
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(background.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            for index in 0..<8 {
                cg.setFillColor(accent.withAlphaComponent(0.10).cgColor)
                cg.fill(
                    CGRect(
                        x: 0,
                        y: CGFloat(index) * 32,
                        width: size.width,
                        height: 10
                    )
                )
            }
            let font = UIFont.systemFont(ofSize: 74, weight: .black)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: accent
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let textSize = string.size()
            string.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) * 0.5,
                    y: (size.height - textSize.height) * 0.5
                )
            )
            cg.setStrokeColor(accent.withAlphaComponent(0.7).cgColor)
            cg.setLineWidth(3)
            cg.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6))
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(
            image: cgImage,
            withName: "billboard-\(text)",
            options: .init(semantic: .color)
        )
    }

    // MARK: - Helpers

    private static func opaqueFormat() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return format
    }

    private static func clearFormat() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return format
    }

    private static func makeNoiseTexture(
        name: String,
        size: Int,
        base: UIColor,
        grain: CGFloat
    ) -> TextureResource? {
        let format = opaqueFormat()
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size),
            format: format
        )
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(base.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var rng = SeededGenerator(seed: UInt64(size) &+ 0x51A7)
            for _ in 0..<(size * 12) {
                let x = CGFloat.random(in: 0...CGFloat(size), using: &rng)
                let y = CGFloat.random(in: 0...CGFloat(size), using: &rng)
                let w = CGFloat.random(in: 0.5...2.4, using: &rng)
                let alpha = CGFloat.random(in: 0.01...grain, using: &rng)
                cg.setFillColor(UIColor(white: Bool.random(using: &rng) ? 1 : 0, alpha: alpha).cgColor)
                cg.fill(CGRect(x: x, y: y, width: w, height: w))
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(
            image: cgImage,
            withName: name,
            options: .init(semantic: .color)
        )
    }
}

@MainActor
enum MaterialFactory {
    static func pbr(
        color: UIColor,
        roughness: Float,
        metallic: Float,
        texture: TextureResource? = nil,
        metallicTexture: TextureResource? = nil,
        roughnessTexture: TextureResource? = nil,
        normal: TextureResource? = nil,
        emissive: UIColor? = nil,
        emissiveIntensity: Float = 1,
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.1
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(
            tint: color,
            texture: texture.map { repeatTexture($0) }
        )
        material.metallic = .init(
            scale: metallic,
            texture: metallicTexture.map { repeatTexture($0) }
        )
        material.roughness = .init(
            scale: roughness,
            texture: roughnessTexture.map { repeatTexture($0) }
        )
        if let normal {
            material.normal = .init(texture: repeatTexture(normal))
        }
        if let emissive {
            material.emissiveColor = .init(color: emissive)
            material.emissiveIntensity = emissiveIntensity
        }
        material.clearcoat = .init(floatLiteral: clearcoat)
        material.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
        return material
    }

    static func unlit(
        color: UIColor = .white,
        texture: TextureResource? = nil,
        transparent: Bool = false
    ) -> UnlitMaterial {
        var material: UnlitMaterial
        if let texture {
            material = UnlitMaterial(texture: texture)
        } else {
            material = UnlitMaterial(color: color)
        }
        material.color = .init(tint: color)
        if let texture {
            var parameter = MaterialParameters.Texture(texture)
            var sampler = MaterialParameters.Texture.Sampler()
            sampler.modify { descriptor in
                descriptor.sAddressMode = .repeat
                descriptor.tAddressMode = .repeat
                descriptor.minFilter = .linear
                descriptor.magFilter = .linear
                descriptor.mipFilter = .linear
            }
            parameter.sampler = sampler
            material.color = .init(tint: color, texture: parameter)
        }
        if transparent {
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            material.readsDepth = true
            material.writesDepth = false
        }
        return material
    }

    static func repeatTexture(_ texture: TextureResource) -> MaterialParameters.Texture {
        var parameter = MaterialParameters.Texture(texture)
        var sampler = MaterialParameters.Texture.Sampler()
        sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
        }
        parameter.sampler = sampler
        return parameter
    }
}
