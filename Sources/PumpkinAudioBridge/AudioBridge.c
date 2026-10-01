// Adapted from baogli/able-recorder (MIT); see THIRD_PARTY_NOTICES.md.
#include "AudioBridge.h"
#include <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
#include <stdlib.h>

// The HAL thread never allocates, locks, touches Swift, or encodes media.
#define LR_SLOTS 256
#define LR_FRAMES 4096
typedef struct { float samples[LR_FRAMES * 2]; uint32_t frames; uint64_t hostTime; } Slot;
struct LRAudio {
    AudioUnit unit;
    Slot *slots;
    float discard[LR_FRAMES * 2];
    _Atomic uint32_t head, tail;
    _Atomic uint64_t dropped;
    _Atomic int32_t error;
};

static OSStatus capture(void *ctx, AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *ignored) {
    LRAudio *a = ctx;
    if (frames > LR_FRAMES) { atomic_store(&a->error, kAudioUnitErr_TooManyFramesToProcess); return kAudioUnitErr_TooManyFramesToProcess; }
    uint32_t head = atomic_load_explicit(&a->head, memory_order_relaxed);
    uint32_t next = (head + 1) % LR_SLOTS;
    int full = next == atomic_load_explicit(&a->tail, memory_order_acquire);
    Slot *s = &a->slots[head];
    AudioBufferList buffers = {.mNumberBuffers = 1,
        .mBuffers = {{.mNumberChannels = 2, .mDataByteSize = frames * 2 * sizeof(float),
                     .mData = full ? a->discard : s->samples}}};
    OSStatus status = AudioUnitRender(a->unit, flags, time, 1, frames, &buffers);
    if (status) { atomic_store(&a->error, status); return status; }
    if (!(time->mFlags & kAudioTimeStampHostTimeValid)) { atomic_store(&a->error, kAudio_ParamError); return noErr; }
    if (full) { atomic_fetch_add(&a->dropped, 1); return noErr; }
    s->frames = frames; s->hostTime = time->mHostTime;
    atomic_store_explicit(&a->head, next, memory_order_release);
    return noErr;
}

LRAudio *lr_audio_start(uint32_t device, int32_t left, int32_t right, double rate, int32_t *error) {
    LRAudio *a = calloc(1, sizeof(LRAudio));
    if (!a) { *error = -108; return NULL; }
    a->slots = calloc(LR_SLOTS, sizeof(Slot));
    if (!a->slots) { free(a); *error = -108; return NULL; }
    AudioComponentDescription desc = {.componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput, .componentManufacturer = kAudioUnitManufacturer_Apple};
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    OSStatus status = component ? AudioComponentInstanceNew(component, &a->unit) : -1;
    if (status) goto fail;
    UInt32 on = 1, off = 0, maximum = LR_FRAMES;
#define SET(prop, scope, bus, value) do { status = AudioUnitSetProperty(a->unit, prop, scope, bus, &(value), sizeof(value)); if (status) goto fail; } while (0)
    SET(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, on);
    SET(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, off);
    SET(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, device);
    AudioStreamBasicDescription format = {.mSampleRate = rate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
        .mBytesPerPacket = 8, .mFramesPerPacket = 1, .mBytesPerFrame = 8, .mChannelsPerFrame = 2, .mBitsPerChannel = 32};
    SET(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, format);
    SInt32 map[2] = {left, right}; // Zero-based hardware inputs -> stereo L/R.
    SET(kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1, map);
    SET(kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, maximum);
    AURenderCallbackStruct callback = {.inputProc = capture, .inputProcRefCon = a};
    SET(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, callback);
    status = AudioUnitInitialize(a->unit); if (status) goto fail;
    status = AudioOutputUnitStart(a->unit); if (status) goto fail;
    *error = 0; return a;
fail:
    *error = status; lr_audio_stop(a); return NULL;
}
int lr_audio_peek(LRAudio *a, LRPacket *packet) {
    uint32_t tail = atomic_load_explicit(&a->tail, memory_order_relaxed);
    if (tail == atomic_load_explicit(&a->head, memory_order_acquire)) return 0;
    Slot *s = &a->slots[tail];
    packet->samples = s->samples; packet->frames = s->frames; packet->hostTime = s->hostTime;
    return 1;
}
void lr_audio_pop(LRAudio *a) { uint32_t tail = atomic_load(&a->tail); atomic_store_explicit(&a->tail, (tail + 1) % LR_SLOTS, memory_order_release); }
uint64_t lr_audio_dropped(LRAudio *a) { return atomic_load(&a->dropped); }
int32_t lr_audio_error(LRAudio *a) { return atomic_load(&a->error); }
void lr_audio_stop(LRAudio *a) {
    if (!a) return;
    if (a->unit) { AudioOutputUnitStop(a->unit); AudioUnitUninitialize(a->unit); AudioComponentInstanceDispose(a->unit); }
    free(a->slots); free(a);
}
