#pragma once
#include <stdint.h>
typedef struct LRAudio LRAudio;
typedef struct {
    const float *samples;
    uint32_t frames;
    uint64_t hostTime;
} LRPacket;
LRAudio *lr_audio_start(uint32_t device, int32_t left, int32_t right, double rate, int32_t *error);
int lr_audio_peek(LRAudio *audio, LRPacket *packet);
void lr_audio_pop(LRAudio *audio);
uint64_t lr_audio_dropped(LRAudio *audio);
int32_t lr_audio_error(LRAudio *audio);
void lr_audio_stop(LRAudio *audio);
