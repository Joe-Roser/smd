#include "ring_buffer.h"

typedef unsigned int u32;

typedef struct {
    u32 sample_rate;
    u32 channels;
} pw_audio_params;

typedef enum {
    PW_AUDIO_STATE_ZEROED,
    PW_AUDIO_STATE_PLAYING,
    PW_AUDIO_STATE_PAUSED,
} pw_audio_state;

typedef struct pw_audio_internals pw_audio_internals;

pw_audio_internals* pw_audio_init(pw_audio_params params, ring_buffer* rb);
void pw_audio_deinit(pw_audio_internals*);

void pw_audio_clear(pw_audio_internals* internals);

void pw_audio_zero(pw_audio_internals* internals);
void pw_audio_play(pw_audio_internals* internals);
void pw_audio_pause(pw_audio_internals* internals);

int pw_audio_get_fd(pw_audio_internals* internals);
void pw_audio_iterate(pw_audio_internals* internals);
void pw_audio_main_loop_run(pw_audio_internals* internals);
