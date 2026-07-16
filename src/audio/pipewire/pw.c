#include "pw.h"
#include <spa/param/audio/format-utils.h>

struct spa_pod* format_audio_raw_build_workaround(struct spa_pod_builder *builder, uint32_t id, const struct spa_audio_info_raw *info) {
    int size = sizeof(*info);

	struct spa_pod_frame f;
	uint32_t max_position = SPA_AUDIO_INFO_RAW_MAX_POSITION(size);

	if (!SPA_AUDIO_INFO_RAW_VALID_SIZE(size)) {
		errno = EINVAL;
		return NULL;
	}

	spa_pod_builder_push_object(builder, &f, SPA_TYPE_OBJECT_Format, id);
	spa_pod_builder_add(builder,
			SPA_FORMAT_mediaType,		SPA_POD_Id(SPA_MEDIA_TYPE_audio),
			SPA_FORMAT_mediaSubtype,	SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
			0);
	if (info->format != SPA_AUDIO_FORMAT_UNKNOWN)
		spa_pod_builder_add(builder,
			SPA_FORMAT_AUDIO_format,	SPA_POD_Id(info->format), 0);
	if (info->rate != 0)
		spa_pod_builder_add(builder,
			SPA_FORMAT_AUDIO_rate,		SPA_POD_Int(info->rate), 0);
	if (info->channels != 0) {
		spa_pod_builder_add(builder,
			SPA_FORMAT_AUDIO_channels,	SPA_POD_Int(info->channels), 0);
		/* we drop the positions here when we can't read all of them. This is
		 * really a malformed spa_audio_info structure. */
		if (!SPA_FLAG_IS_SET(info->flags, SPA_AUDIO_FLAG_UNPOSITIONED) &&
		    info->channels <= max_position) {
			spa_pod_builder_add(builder, SPA_FORMAT_AUDIO_position,
				SPA_POD_Array(sizeof(uint32_t), SPA_TYPE_Id,
					info->channels, info->position), 0);
		}
	}
	return (struct spa_pod*)spa_pod_builder_pop(builder, &f);
}
