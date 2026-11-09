import AppKit
import Libmpv
import OpenGL.GL3
import os

/// Draws mpv's video with the render API (OpenGL) in a CAOpenGLLayer (D22).
nonisolated final class MPVVideoLayer: CAOpenGLLayer, @unchecked Sendable {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "MPV")

    private let mpv: MPVHandle
    private var renderContext: OpaquePointer?
    /// True once the render context exists (set on the main thread).
    private(set) var isReady = false
    /// Called on the main thread when the render context is created. `replacedContext` (M7h 13g): a render context was
    /// freed since the last one was created, which turns mpv's video off until the next loadfile (render.h).
    var onReady: (@Sendable (_ replacedContext: Bool) -> Void)?
    /// M7h 13g: set when a render context is freed, cleared when the next one is created (Core Animation's GL callbacks).
    private var renderContextFreed = false

    init(mpv: MPVHandle) {
        self.mpv = mpv
        super.init()
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        backgroundColor = NSColor.black.cgColor
    }

    /// CA copies layers for presentation.
    override init(layer: Any) {
        guard let other = layer as? MPVVideoLayer else { fatalError("Unexpected layer type") }
        mpv = other.mpv
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFADoubleBuffer,
            kCGLPFAAccelerated,
            kCGLPFAAllowOfflineRenderers,
            CGLPixelFormatAttribute(0),
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        let error = CGLChoosePixelFormat(attributes, &pixelFormat, &count)
        guard error == kCGLNoError, let pixelFormat else {
            Self.logger.error("CGLChoosePixelFormat failed: \(error.rawValue)")
            return super.copyCGLPixelFormat(forDisplayMask: mask)
        }
        return pixelFormat
    }

    override func copyCGLContext(forPixelFormat pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        let context = super.copyCGLContext(forPixelFormat: pixelFormat)
        // M7c: a new context means a new render context, i.e. black until mpv draws again (the flicker on Select).
        Self.logger.notice("Video GL context created")
        CGLSetCurrentContext(context)
        // Only one render context can exist per mpv core.
        if let renderContext {
            mpv_render_context_free(renderContext)
            self.renderContext = nil
            renderContextFreed = true
        }
        createRenderContext()
        return context
    }

    override func releaseCGLContext(_ context: CGLContextObj) {
        Self.logger.notice("Video GL context released")
        CGLSetCurrentContext(context)
        if let renderContext {
            mpv_render_context_free(renderContext)
            self.renderContext = nil
            renderContextFreed = true
        }
        let ref = LayerRef(layer: self)
        DispatchQueue.main.async { ref.layer.isReady = false }
        super.releaseCGLContext(context)
    }

    override func canDraw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                          forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        true
    }

    override func draw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                       forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        guard let renderContext else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            glFlush()
            return
        }
        var fboBinding: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &fboBinding)
        var viewport: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)

        var fbo = mpv_opengl_fbo(fbo: Int32(fboBinding), w: Int32(viewport[2]), h: Int32(viewport[3]), internal_format: 0)
        var flipY: Int32 = 1
        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                _ = mpv_render_context_render(renderContext, &params)
            }
        }
        glFlush()
    }

    /// With the layer's GL context current.
    private func createRenderContext() {
        var initParams = mpv_opengl_init_params(get_proc_address: { _, name in
            guard let name else { return nil }
            let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
            let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
            return CFBundleGetFunctionPointerForName(bundle, symbol)
        }, get_proc_address_ctx: nil)

        var context: OpaquePointer?
        let status = MPV_RENDER_API_TYPE_OPENGL.withCString { apiType in
            withUnsafeMutablePointer(to: &initParams) { initPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiType)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return mpv_render_context_create(&context, mpv.handle, &params)
            }
        }
        guard status >= 0, let context else {
            Self.logger.error("mpv_render_context_create failed: \(String(cString: mpv_error_string(status)), privacy: .public)")
            return
        }
        renderContext = context
        mpv_render_context_set_update_callback(context, { layerContext in
            guard let layerContext else { return }
            let ref = LayerRef(layer: Unmanaged<MPVVideoLayer>.fromOpaque(layerContext).takeUnretainedValue())
            DispatchQueue.main.async { ref.layer.setNeedsDisplay() }
        }, Unmanaged.passUnretained(self).toOpaque())
        let replaced = renderContextFreed
        renderContextFreed = false
        let ref = LayerRef(layer: self)
        DispatchQueue.main.async {
            ref.layer.isReady = true
            ref.layer.onReady?(replaced)
        }
    }
}

/// Hands the layer to the main queue. The region checker reports capturing the layer itself as a data race, though it is
/// `@unchecked Sendable`; it is only touched on main and in Core Animation's GL callbacks.
private nonisolated struct LayerRef: @unchecked Sendable {
    let layer: MPVVideoLayer
}

/// Layer-hosting view for `MPVVideoLayer`.
final class MPVVideoView: NSView {
    let videoLayer: MPVVideoLayer

    init(mpv: MPVHandle) {
        videoLayer = MPVVideoLayer(mpv: mpv)
        super.init(frame: .zero)
        // Layer-hosting: set the layer before wantsLayer.
        layer = videoLayer
        wantsLayer = true
        videoLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
}
