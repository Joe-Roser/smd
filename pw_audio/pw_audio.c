#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <stdbool.h>
#include <stdio.h>
#include <time.h>

#include "pw_audio.h"
#include "pipewire/stream.h"


struct pw_audio_internals {
    struct pw_main_loop* loop;
    struct pw_stream* stream;

    ring_buffer* rb;
    pw_audio_state state;
};

// TODO: Errorchecking
void on_process(void *userdata) {
    struct pw_audio_internals *internals = userdata;
    ring_buffer* rb = internals->rb;

    struct pw_buffer *b = pw_stream_dequeue_buffer(internals->stream);
    if (!b) return;


    struct spa_buffer *sb = b->buffer;

    float *dst = sb->datas[0].data;
    int size = sb->datas[0].maxsize / sizeof(float);

    if (internals->state == PW_AUDIO_STATE_ZEROED) {
        memset(dst, 0, sb->datas[0].maxsize);
        sb->datas[0].chunk->size = sb->datas[0].maxsize;
        pw_stream_queue_buffer(internals->stream, b);
        return;
    }

    u32 size_read = ring_read(rb, dst, size);

    sb->datas[0].chunk->size = size_read * sizeof(float);

    pw_stream_queue_buffer(internals->stream, b);
}

static const struct pw_stream_events stream_events = {
    .process = on_process,
};

pw_audio_internals* pw_audio_init(pw_audio_params params, ring_buffer* rb) {
    // Initialise pw
    pw_init(NULL, NULL);
    pw_audio_internals* internals = calloc(1, sizeof(pw_audio_internals));
    if (internals == NULL) goto fail;

    internals->rb = rb;

    // get a loop
    internals->loop = pw_main_loop_new(NULL);
    if (internals->loop == NULL) goto fail;

    // make a stream properties
    struct pw_properties* props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Playback",
        PW_KEY_MEDIA_ROLE, "Music",
        NULL
    );

    // make a new simple stream
    internals->stream = pw_stream_new_simple(pw_main_loop_get_loop(internals->loop), "smd", props, &stream_events, internals);
    if (internals->stream == NULL) goto fail;

    // register the stream
    struct spa_audio_info_raw audio_info = {
        .format = SPA_AUDIO_FORMAT_F32,
        .rate = params.sample_rate,
        .channels = params.channels,
    };

    uint8_t buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));

    const struct spa_pod *params_pod = spa_format_audio_raw_build(
        &b,
        SPA_PARAM_EnumFormat,
        &audio_info
    );
    if (params_pod == NULL) goto fail;

    int res = pw_stream_connect(
        internals->stream,
        PW_DIRECTION_OUTPUT,
        PW_ID_ANY,
        PW_STREAM_FLAG_AUTOCONNECT |
        PW_STREAM_FLAG_MAP_BUFFERS,
        &params_pod,
        1
    );
    if (res < 0) goto fail;

    return internals;

fail:
    pw_audio_deinit(internals);
    return NULL; 
}

void pw_audio_deinit(pw_audio_internals* internals) {
    if (internals == NULL) return;

    if (internals->stream != NULL) pw_stream_destroy(internals->stream);
    if (internals->loop != NULL )pw_main_loop_destroy(internals->loop);
    pw_deinit();

    free(internals);
}

void pw_audio_clear(pw_audio_internals* internals) {
    pw_stream_flush(internals->stream, false);
}

// TODO: Errorchecking
int pw_audio_get_fd(pw_audio_internals* internals) {
    return pw_loop_get_fd(pw_main_loop_get_loop(internals->loop));
}

void pw_audio_iterate(pw_audio_internals* internals) {
    pw_loop_iterate(pw_main_loop_get_loop(internals->loop), 0);
}

void pw_audio_main_loop_run(pw_audio_internals* internals) {
    pw_main_loop_run(internals->loop);
}

void pw_audio_zero(pw_audio_internals* internals) {
    if (!internals || internals->state == PW_AUDIO_STATE_ZEROED) return;
    if (internals->state == PW_AUDIO_STATE_PLAYING)
        pw_stream_set_active(internals->stream, true);

    internals->state = PW_AUDIO_STATE_ZEROED;
}
void pw_audio_play(pw_audio_internals* internals) {
    // TODO: State is getting fucked up???
        pw_stream_set_active(internals->stream, true);
    if (!internals || internals->state == PW_AUDIO_STATE_PLAYING) return;
    // if (internals->state == PW_AUDIO_STATE_ZEROED)

    internals->state = PW_AUDIO_STATE_PLAYING;
}
void pw_audio_pause(pw_audio_internals* internals) {
    if (!internals || internals->state == PW_AUDIO_STATE_PAUSED) return;

    internals->state = PW_AUDIO_STATE_PAUSED;
    pw_stream_set_active(internals->stream, false);
}
