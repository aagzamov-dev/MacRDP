import AppKit
import Metal
import QuartzCore

@MainActor
final class DesktopRenderer {
    enum Result { case presented, busy, warming, needsFullFrame, failed }
    let layer = CAMetalLayer()
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private var pipeline: (any MTLRenderPipelineState)?
    private var failed = false
    private let linear: any MTLSamplerState
    private let nearest: any MTLSamplerState
    private let slots = DispatchSemaphore(value: 2)
    private var texture: (any MTLTexture)?
    private var generation: UInt64 = 0
    private var sequence: UInt64 = 0

    init?(device: any MTLDevice, ready: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let queue = device.makeCommandQueue() else { return nil }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Vertex { float4 position [[position]]; float2 uv; };
        vertex Vertex desktopVertex(uint id [[vertex_id]], constant float4 &rect [[buffer(0)]]) {
            const float2 uv[4] = {float2(0,1),float2(1,1),float2(0,0),float2(1,0)};
            Vertex out;
            out.uv = uv[id];
            out.position = float4(rect.xy + float2(uv[id].x, 1.0-uv[id].y) * rect.zw, 0, 1);
            return out;
        }
        fragment float4 desktopFragment(Vertex in [[stage_in]], texture2d<float> desktop [[texture(0)]], sampler filtering [[sampler(0)]]) {
            return float4(desktop.sample(filtering, in.uv).rgb, 1.0);
        }
        """
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear; sampler.magFilter = .linear
        guard let linear = device.makeSamplerState(descriptor: sampler) else { return nil }
        sampler.minFilter = .nearest; sampler.magFilter = .nearest
        guard let nearest = device.makeSamplerState(descriptor: sampler) else { return nil }
        self.device = device; self.queue = queue; self.linear = linear; self.nearest = nearest
        layer.device = device; layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true; layer.maximumDrawableCount = 3
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = true; layer.backgroundColor = NSColor.black.cgColor
        layer.allowsNextDrawableTimeout = true
        layer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        device.makeLibrary(source: source, options: nil) { [weak self] library, _ in
            guard let library else {
                DispatchQueue.main.async { self?.failed = true; ready(false) }
                return
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "desktopVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "desktopFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            device.makeRenderPipelineState(descriptor: descriptor) { [weak self] pipeline, _ in
                DispatchQueue.main.async {
                    self?.pipeline = pipeline; self?.failed = pipeline == nil
                    ready(pipeline != nil)
                }
            }
        }
    }

    func clear() { texture = nil; generation = 0; sequence = 0; layer.isHidden = true }

    func render(_ frame: DesktopFrame?, bounds: CGRect, backing: CGSize, imageRect: CGRect,
                completion: @escaping @Sendable (Bool, Double) -> Void) -> Result {
        guard let pipeline else { return failed ? .failed : .warming }
        guard bounds.width > 0, bounds.height > 0, backing.width > 0, backing.height > 0 else { return .busy }
        guard slots.wait(timeout: .now()) == .success else { return .busy }
        var committed = false
        defer { if !committed { slots.signal() } }
        if layer.frame != bounds { layer.frame = bounds }
        if layer.drawableSize != backing { layer.drawableSize = backing }
        let scale = backing.width / bounds.width
        if layer.contentsScale != scale { layer.contentsScale = scale }
        if let frame, texture == nil || generation != frame.info.generation {
            guard frame.info.x == 0, frame.info.y == 0,
                  frame.info.dirty_width == frame.info.width, frame.info.dirty_height == frame.info.height else { return .needsFullFrame }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: Int(frame.info.width), height: Int(frame.info.height), mipmapped: false)
            descriptor.storageMode = .private; descriptor.usage = [.shaderRead]
            guard let next = device.makeTexture(descriptor: descriptor) else { return .failed }
            texture = next; generation = frame.info.generation; sequence = 0
        }
        guard let texture else { return .needsFullFrame }
        guard let drawable = layer.nextDrawable(), let command = queue.makeCommandBuffer() else { return .busy }
        if let frame {
            guard frame.info.sequence >= sequence, let buffer = frame.storage.metal,
                  let blit = command.makeBlitCommandEncoder() else { return .failed }
            blit.copy(from: buffer, sourceOffset: Int(frame.info.y * frame.info.stride + frame.info.x * 4),
                sourceBytesPerRow: Int(frame.info.stride), sourceBytesPerImage: 0,
                sourceSize: MTLSize(width: Int(frame.info.dirty_width), height: Int(frame.info.dirty_height), depth: 1),
                to: texture, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: Int(frame.info.x), y: Int(frame.info.y), z: 0))
            blit.endEncoding()
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return .failed }
        var rect = SIMD4<Float>(Float(2 * imageRect.minX / bounds.width - 1),
            Float(1 - 2 * imageRect.maxY / bounds.height),
            Float(2 * imageRect.width / bounds.width), Float(2 * imageRect.height / bounds.height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        let exact = abs(imageRect.width * backing.width / bounds.width - CGFloat(texture.width)) < 0.5
            && abs(imageRect.height * backing.height / bounds.height - CGFloat(texture.height)) < 0.5
        encoder.setFragmentSamplerState(exact ? nearest : linear, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        let started = ProcessInfo.processInfo.systemUptime
        let slots = slots
        command.addCompletedHandler { command in
            withExtendedLifetime(frame) {}
            slots.signal()
            completion(command.status == .completed, (ProcessInfo.processInfo.systemUptime - started) * 1000)
        }
        command.present(drawable); command.commit(); committed = true
        if let frame { sequence = frame.info.sequence }
        layer.isHidden = false
        return .presented
    }
}
