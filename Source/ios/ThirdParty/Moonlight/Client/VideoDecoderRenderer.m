// StormVR presentation adapter for the Moonlight connection, under the included GPL license.
#import "VideoDecoderRenderer.h"
#import <VideoToolbox/VideoToolbox.h>

static size_t nalStartLength(const uint8_t *bytes, size_t length) {
    if (length < 3 || bytes[0] != 0 || bytes[1] != 0) return 0;
    if (bytes[2] == 1) return 3;
    return length >= 4 && bytes[2] == 0 && bytes[3] == 1 ? 4 : 0;
}

@interface VideoDecoderRenderer ()
- (void)didDecode:(CVPixelBufferRef)frame;
@end

static void decoderOutput(void *context, void *source, OSStatus status, VTDecodeInfoFlags flags,
                          CVImageBufferRef image, CMTime pts, CMTime duration) {
    if (status == noErr && image != NULL && !(flags & kVTDecodeInfo_FrameDropped)) {
        [(__bridge VideoDecoderRenderer *)context didDecode:image];
    }
}

@implementation VideoDecoderRenderer {
    void (^_frameHandler)(CVPixelBufferRef);
    NSData *_sps;
    NSData *_pps;
    CMVideoFormatDescriptionRef _format;
    VTDecompressionSessionRef _decoder;
}

- (instancetype)initWithFrameHandler:(void (^)(CVPixelBufferRef))frameHandler {
    if ((self = [super init])) _frameHandler = [frameHandler copy];
    return self;
}

- (void)setupWithVideoFormat:(int)format width:(int)width height:(int)height frameRate:(int)fps {
    [self stop];
}

- (void)start { }
- (void)setHdrMode:(BOOL)enabled { }

- (void)resetDecoder {
    if (_decoder) {
        VTDecompressionSessionWaitForAsynchronousFrames(_decoder);
        VTDecompressionSessionInvalidate(_decoder);
        CFRelease(_decoder);
        _decoder = NULL;
    }
    if (_format) {
        CFRelease(_format);
        _format = NULL;
    }
}

- (void)stop {
    [self resetDecoder];
    _sps = nil;
    _pps = nil;
}

- (void)didDecode:(CVPixelBufferRef)frame { _frameHandler(frame); }

- (BOOL)createDecoder {
    if (!_sps || !_pps) return NO;
    const uint8_t *sets[] = { _sps.bytes, _pps.bytes };
    size_t sizes[] = { _sps.length, _pps.length };
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, sets, sizes, 4, &_format);
    if (status != noErr) return NO;

    NSDictionary *attributes = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    VTDecompressionOutputCallbackRecord callbacks = { decoderOutput, (__bridge void *)self };
    status = VTDecompressionSessionCreate(kCFAllocatorDefault, _format, NULL,
        (__bridge CFDictionaryRef)attributes, &callbacks, &_decoder);
    if (status != noErr) {
        [self resetDecoder];
        return NO;
    }
    VTSessionSetProperty(_decoder, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    return YES;
}

- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)type decodeUnit:(PDECODE_UNIT)unit {
    if (type != BUFFER_TYPE_PICDATA) {
        if (type != BUFFER_TYPE_SPS && type != BUFFER_TYPE_PPS) return DR_OK;
        size_t start = length > 0 ? nalStartLength(data, (size_t)length) : 0;
        if (!start || start >= (size_t)length) return DR_NEED_IDR;
        NSData *parameterSet = [NSData dataWithBytes:data + start length:(size_t)length - start];
        NSData *previous = type == BUFFER_TYPE_SPS ? _sps : _pps;
        if (![parameterSet isEqualToData:previous]) {
            [self resetDecoder];
            if (type == BUFFER_TYPE_SPS) _sps = parameterSet;
            else _pps = parameterSet;
        }
        return DR_OK;
    }

    NSMutableData *sampleData = [NSMutableData dataWithCapacity:length > 0 ? (NSUInteger)length : 0];
    size_t total = length > 0 ? (size_t)length : 0;
    for (size_t cursor = 0; cursor < total;) {
        size_t start = nalStartLength(data + cursor, total - cursor);
        if (!start) { [sampleData setLength:0]; break; }
        size_t firstByte = cursor + start;
        size_t next = firstByte;
        while (next < total && !nalStartLength(data + next, total - next)) ++next;
        size_t nalLength = next - firstByte;
        if (nalLength > 0) {
            uint32_t header = CFSwapInt32HostToBig((uint32_t)nalLength);
            [sampleData appendBytes:&header length:sizeof(header)];
            [sampleData appendBytes:data + firstByte length:nalLength];
        }
        cursor = next;
    }
    free(data);
    if (sampleData.length == 0 || (!_decoder && (unit->frameType != FRAME_TYPE_IDR || ![self createDecoder]))) {
        return DR_NEED_IDR;
    }

    size_t sampleSize = sampleData.length;
    CMBlockBufferRef block = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, sampleSize, kCFAllocatorDefault,
        NULL, 0, sampleSize, kCMBlockBufferAssureMemoryNowFlag, &block);
    if (status != noErr) return DR_NEED_IDR;
    status = CMBlockBufferReplaceDataBytes(sampleData.bytes, block, 0, sampleSize);
    CMSampleBufferRef sample = NULL;
    CMSampleTimingInfo timing = { kCMTimeInvalid, CMTimeMake((int64_t)unit->presentationTimeUs, 1000000), kCMTimeInvalid };
    if (status == noErr) {
        status = CMSampleBufferCreateReady(kCFAllocatorDefault, block, _format, 1, 1, &timing, 1, &sampleSize, &sample);
    }
    CFRelease(block);
    if (status != noErr) return DR_NEED_IDR;

    status = VTDecompressionSessionDecodeFrame(_decoder, sample, kVTDecodeFrame_EnableAsynchronousDecompression, NULL, NULL);
    CFRelease(sample);
    if (status != noErr) [self resetDecoder];
    return status == noErr ? DR_OK : DR_NEED_IDR;
}

- (void)dealloc { [self resetDecoder]; }
@end
