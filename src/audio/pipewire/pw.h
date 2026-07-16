#include <spa/param/audio/format-utils.h>

// #define SPA_AUDIO_MAX_CHANNELS	64u
// 
// #ifdef __GNUC__
// #define SPA_SENTINEL __attribute__((__sentinel__))
// #else
// #define SPA_SENTINEL
// #endif



#define pw_direction spa_direction
#define PW_DIRECTION_INPUT SPA_DIRECTION_INPUT
#define PW_DIRECTION_OUTPUT SPA_DIRECTION_OUTPUT

#define PW_ID_ANY		(uint32_t)(0xffffffff)

#define PW_KEY_MEDIA_TYPE		"media.type"		/**< Media type, one of
								  *  Audio, Video, Midi */
#define PW_KEY_MEDIA_CATEGORY		"media.category"	/**< Media Category:
								  *  Playback, Capture, Duplex, Monitor, Manager */
#define PW_KEY_MEDIA_ROLE		"media.role"		/**< Role: Movie, Music, Camera,
								  *  Screen, Communication, Game,
								  *  Notification, DSP, Production,
								  *  Accessibility, Test */

enum pw_stream_state {
	PW_STREAM_STATE_ERROR = -1,		/**< the stream is in error */
	PW_STREAM_STATE_UNCONNECTED = 0,	/**< unconnected */
	PW_STREAM_STATE_CONNECTING = 1,		/**< connection is in progress */
	PW_STREAM_STATE_PAUSED = 2,		/**< paused */
	PW_STREAM_STATE_STREAMING = 3		/**< streaming */
};

// enum spa_audio_format {
// 	SPA_AUDIO_FORMAT_UNKNOWN,
// 	SPA_AUDIO_FORMAT_ENCODED,
// 
// 	/* interleaved formats */
// 	SPA_AUDIO_FORMAT_START_Interleaved	= 0x100,
// 	SPA_AUDIO_FORMAT_S8,
// 	SPA_AUDIO_FORMAT_U8,
// 	SPA_AUDIO_FORMAT_S16_LE,
// 	SPA_AUDIO_FORMAT_S16_BE,
// 	SPA_AUDIO_FORMAT_U16_LE,
// 	SPA_AUDIO_FORMAT_U16_BE,
// 	SPA_AUDIO_FORMAT_S24_32_LE,
// 	SPA_AUDIO_FORMAT_S24_32_BE,
// 	SPA_AUDIO_FORMAT_U24_32_LE,
// 	SPA_AUDIO_FORMAT_U24_32_BE,
// 	SPA_AUDIO_FORMAT_S32_LE,
// 	SPA_AUDIO_FORMAT_S32_BE,
// 	SPA_AUDIO_FORMAT_U32_LE,
// 	SPA_AUDIO_FORMAT_U32_BE,
// 	SPA_AUDIO_FORMAT_S24_LE,
// 	SPA_AUDIO_FORMAT_S24_BE,
// 	SPA_AUDIO_FORMAT_U24_LE,
// 	SPA_AUDIO_FORMAT_U24_BE,
// 	SPA_AUDIO_FORMAT_S20_LE,
// 	SPA_AUDIO_FORMAT_S20_BE,
// 	SPA_AUDIO_FORMAT_U20_LE,
// 	SPA_AUDIO_FORMAT_U20_BE,
// 	SPA_AUDIO_FORMAT_S18_LE,
// 	SPA_AUDIO_FORMAT_S18_BE,
// 	SPA_AUDIO_FORMAT_U18_LE,
// 	SPA_AUDIO_FORMAT_U18_BE,
// 	SPA_AUDIO_FORMAT_F32_LE,
// 	SPA_AUDIO_FORMAT_F32_BE,
// 	SPA_AUDIO_FORMAT_F64_LE,
// 	SPA_AUDIO_FORMAT_F64_BE,
// 
// 	SPA_AUDIO_FORMAT_ULAW,
// 	SPA_AUDIO_FORMAT_ALAW,
// 
// 	/* planar formats */
// 	SPA_AUDIO_FORMAT_START_Planar		= 0x200,
// 	SPA_AUDIO_FORMAT_U8P,
// 	SPA_AUDIO_FORMAT_S16P,
// 	SPA_AUDIO_FORMAT_S24_32P,
// 	SPA_AUDIO_FORMAT_S32P,
// 	SPA_AUDIO_FORMAT_S24P,
// 	SPA_AUDIO_FORMAT_F32P,
// 	SPA_AUDIO_FORMAT_F64P,
// 	SPA_AUDIO_FORMAT_S8P,
// 
// 	/* other formats start here */
// 	SPA_AUDIO_FORMAT_START_Other		= 0x400,
// 
// 	/* Aliases */
// 
// 	/* DSP formats */
// 	SPA_AUDIO_FORMAT_DSP_S32 = SPA_AUDIO_FORMAT_S24_32P,
// 	SPA_AUDIO_FORMAT_DSP_F32 = SPA_AUDIO_FORMAT_F32P,
// 	SPA_AUDIO_FORMAT_DSP_F64 = SPA_AUDIO_FORMAT_F64P,
// 
// 	/* native endian */
// #if __BYTE_ORDER == __BIG_ENDIAN
// 	SPA_AUDIO_FORMAT_S16 = SPA_AUDIO_FORMAT_S16_BE,
// 	SPA_AUDIO_FORMAT_U16 = SPA_AUDIO_FORMAT_U16_BE,
// 	SPA_AUDIO_FORMAT_S24_32 = SPA_AUDIO_FORMAT_S24_32_BE,
// 	SPA_AUDIO_FORMAT_U24_32 = SPA_AUDIO_FORMAT_U24_32_BE,
// 	SPA_AUDIO_FORMAT_S32 = SPA_AUDIO_FORMAT_S32_BE,
// 	SPA_AUDIO_FORMAT_U32 = SPA_AUDIO_FORMAT_U32_BE,
// 	SPA_AUDIO_FORMAT_S24 = SPA_AUDIO_FORMAT_S24_BE,
// 	SPA_AUDIO_FORMAT_U24 = SPA_AUDIO_FORMAT_U24_BE,
// 	SPA_AUDIO_FORMAT_S20 = SPA_AUDIO_FORMAT_S20_BE,
// 	SPA_AUDIO_FORMAT_U20 = SPA_AUDIO_FORMAT_U20_BE,
// 	SPA_AUDIO_FORMAT_S18 = SPA_AUDIO_FORMAT_S18_BE,
// 	SPA_AUDIO_FORMAT_U18 = SPA_AUDIO_FORMAT_U18_BE,
// 	SPA_AUDIO_FORMAT_F32 = SPA_AUDIO_FORMAT_F32_BE,
// 	SPA_AUDIO_FORMAT_F64 = SPA_AUDIO_FORMAT_F64_BE,
// 	SPA_AUDIO_FORMAT_S16_OE = SPA_AUDIO_FORMAT_S16_LE,
// 	SPA_AUDIO_FORMAT_U16_OE = SPA_AUDIO_FORMAT_U16_LE,
// 	SPA_AUDIO_FORMAT_S24_32_OE = SPA_AUDIO_FORMAT_S24_32_LE,
// 	SPA_AUDIO_FORMAT_U24_32_OE = SPA_AUDIO_FORMAT_U24_32_LE,
// 	SPA_AUDIO_FORMAT_S32_OE = SPA_AUDIO_FORMAT_S32_LE,
// 	SPA_AUDIO_FORMAT_U32_OE = SPA_AUDIO_FORMAT_U32_LE,
// 	SPA_AUDIO_FORMAT_S24_OE = SPA_AUDIO_FORMAT_S24_LE,
// 	SPA_AUDIO_FORMAT_U24_OE = SPA_AUDIO_FORMAT_U24_LE,
// 	SPA_AUDIO_FORMAT_S20_OE = SPA_AUDIO_FORMAT_S20_LE,
// 	SPA_AUDIO_FORMAT_U20_OE = SPA_AUDIO_FORMAT_U20_LE,
// 	SPA_AUDIO_FORMAT_S18_OE = SPA_AUDIO_FORMAT_S18_LE,
// 	SPA_AUDIO_FORMAT_U18_OE = SPA_AUDIO_FORMAT_U18_LE,
// 	SPA_AUDIO_FORMAT_F32_OE = SPA_AUDIO_FORMAT_F32_LE,
// 	SPA_AUDIO_FORMAT_F64_OE = SPA_AUDIO_FORMAT_F64_LE,
// #elif __BYTE_ORDER == __LITTLE_ENDIAN
// 	SPA_AUDIO_FORMAT_S16 = SPA_AUDIO_FORMAT_S16_LE,
// 	SPA_AUDIO_FORMAT_U16 = SPA_AUDIO_FORMAT_U16_LE,
// 	SPA_AUDIO_FORMAT_S24_32 = SPA_AUDIO_FORMAT_S24_32_LE,
// 	SPA_AUDIO_FORMAT_U24_32 = SPA_AUDIO_FORMAT_U24_32_LE,
// 	SPA_AUDIO_FORMAT_S32 = SPA_AUDIO_FORMAT_S32_LE,
// 	SPA_AUDIO_FORMAT_U32 = SPA_AUDIO_FORMAT_U32_LE,
// 	SPA_AUDIO_FORMAT_S24 = SPA_AUDIO_FORMAT_S24_LE,
// 	SPA_AUDIO_FORMAT_U24 = SPA_AUDIO_FORMAT_U24_LE,
// 	SPA_AUDIO_FORMAT_S20 = SPA_AUDIO_FORMAT_S20_LE,
// 	SPA_AUDIO_FORMAT_U20 = SPA_AUDIO_FORMAT_U20_LE,
// 	SPA_AUDIO_FORMAT_S18 = SPA_AUDIO_FORMAT_S18_LE,
// 	SPA_AUDIO_FORMAT_U18 = SPA_AUDIO_FORMAT_U18_LE,
// 	SPA_AUDIO_FORMAT_F32 = SPA_AUDIO_FORMAT_F32_LE,
// 	SPA_AUDIO_FORMAT_F64 = SPA_AUDIO_FORMAT_F64_LE,
// 	SPA_AUDIO_FORMAT_S16_OE = SPA_AUDIO_FORMAT_S16_BE,
// 	SPA_AUDIO_FORMAT_U16_OE = SPA_AUDIO_FORMAT_U16_BE,
// 	SPA_AUDIO_FORMAT_S24_32_OE = SPA_AUDIO_FORMAT_S24_32_BE,
// 	SPA_AUDIO_FORMAT_U24_32_OE = SPA_AUDIO_FORMAT_U24_32_BE,
// 	SPA_AUDIO_FORMAT_S32_OE = SPA_AUDIO_FORMAT_S32_BE,
// 	SPA_AUDIO_FORMAT_U32_OE = SPA_AUDIO_FORMAT_U32_BE,
// 	SPA_AUDIO_FORMAT_S24_OE = SPA_AUDIO_FORMAT_S24_BE,
// 	SPA_AUDIO_FORMAT_U24_OE = SPA_AUDIO_FORMAT_U24_BE,
// 	SPA_AUDIO_FORMAT_S20_OE = SPA_AUDIO_FORMAT_S20_BE,
// 	SPA_AUDIO_FORMAT_U20_OE = SPA_AUDIO_FORMAT_U20_BE,
// 	SPA_AUDIO_FORMAT_S18_OE = SPA_AUDIO_FORMAT_S18_BE,
// 	SPA_AUDIO_FORMAT_U18_OE = SPA_AUDIO_FORMAT_U18_BE,
// 	SPA_AUDIO_FORMAT_F32_OE = SPA_AUDIO_FORMAT_F32_BE,
// 	SPA_AUDIO_FORMAT_F64_OE = SPA_AUDIO_FORMAT_F64_BE,
// #endif
// };
 
enum pw_stream_flags {
	PW_STREAM_FLAG_NONE = 0,			/**< no flags */
	PW_STREAM_FLAG_AUTOCONNECT	= (1 << 0),	/**< try to automatically connect
							  *  this stream */
	PW_STREAM_FLAG_INACTIVE		= (1 << 1),	/**< start the stream inactive,
							  *  pw_stream_set_active() needs to be
							  *  called explicitly */
	PW_STREAM_FLAG_MAP_BUFFERS	= (1 << 2),	/**< mmap the buffers except DmaBuf that is not
							  *  explicitly marked as mappable. */
	PW_STREAM_FLAG_DRIVER		= (1 << 3),	/**< be a driver */
	PW_STREAM_FLAG_RT_PROCESS	= (1 << 4),	/**< call process from the realtime
							  *  thread. You MUST use RT safe functions
							  *  in the process callback. */
	PW_STREAM_FLAG_NO_CONVERT	= (1 << 5),	/**< don't convert format */
	PW_STREAM_FLAG_EXCLUSIVE	= (1 << 6),	/**< require exclusive access to the
							  *  device */
	PW_STREAM_FLAG_DONT_RECONNECT	= (1 << 7),	/**< don't try to reconnect this stream
							  *  when the sink/source is removed */
	PW_STREAM_FLAG_ALLOC_BUFFERS	= (1 << 8),	/**< the application will allocate buffer
							  *  memory. In the add_buffer event, the
							  *  data of the buffer should be set */
	PW_STREAM_FLAG_TRIGGER		= (1 << 9),	/**< the output stream will not be scheduled
							  *  automatically but _trigger_process()
							  *  needs to be called. This can be used
							  *  when the output of the stream depends
							  *  on input from other streams. */
	PW_STREAM_FLAG_ASYNC		= (1 << 10),	/**< Buffers will not be dequeued/queued from
							  *  the realtime process() function. This is
							  *  assumed when RT_PROCESS is unset but can
							  *  also be the case when the process() function
							  *  does a trigger_process() that will then
							  *  dequeue/queue a buffer from another process()
							  *  function. since 0.3.73 */
	PW_STREAM_FLAG_EARLY_PROCESS	= (1 << 11),	/**< Call process as soon as there is a buffer
							  *  to dequeue. This is only relevant for
							  *  playback and when not using RT_PROCESS. It
							  *  can be used to keep the maximum number of
							  *  buffers queued. Since 0.3.81 */
	PW_STREAM_FLAG_RT_TRIGGER_DONE	= (1 << 12),	/**< Call trigger_done from the realtime
							  *  thread. You MUST use RT safe functions
							  *  in the trigger_done callback. Since 1.1.0 */
};

struct pw_main_loop;
struct pw_stream;
struct pw_audio_internals;
struct pw_buffer {
	struct spa_buffer *buffer;	/**< the spa buffer */
	void *user_data;		/**< user data attached to the buffer. The user of
					  *  the stream can set custom data associated with the
					  *  buffer, typically in the add_buffer event. Any
					  *  cleanup should be performed in the remove_buffer
					  *  event. The user data is returned unmodified each
					  *  time a buffer is dequeued. */
	uint64_t size;			/**< This field is set by the user and the sum of
					  *  all queued buffers is returned in the time info.
					  *  For audio, it is advised to use the number of
					  *  frames in the buffer for this field. */
	uint64_t requested;		/**< For playback streams, this field contains the
					  *  suggested amount of data to provide. For audio
					  *  streams this will be the amount of frames
					  *  required by the resampler. This field is 0
					  *  when no suggestion is provided. Since 0.3.50 */
	uint64_t time;			/**< For capture streams, this field contains the
					  *  cycle time in nanoseconds when this buffer was
					  *  queued in the stream. It can be compared against
					  *  the \ref pw_time values or pw_stream_get_nsec()
					  *  Since 1.0.5 */
};
struct spa_buffer {
	uint32_t n_metas;		/**< number of metadata */
	uint32_t n_datas;		/**< number of data members */
	struct spa_meta *metas;		/**< array of metadata */
	struct spa_data *datas;		/**< array of data members */
};
struct spa_data {
	uint32_t type;			/**< memory type, one of enum spa_data_type, when
					  *  allocating memory, the type contains a bitmask
					  *  of allowed types. SPA_ID_INVALID is a special
					  *  value for the allocator to indicate that the
					  *  other side did not explicitly specify any
					  *  supported data types. It should probably use
					  *  a memory type that does not require special
					  *  handling in addition to simple mmap/munmap. */
#define SPA_DATA_FLAG_NONE	 0
#define SPA_DATA_FLAG_READABLE	(1u<<0)	/**< data is readable */
#define SPA_DATA_FLAG_WRITABLE	(1u<<1)	/**< data is writable */
#define SPA_DATA_FLAG_DYNAMIC	(1u<<2)	/**< data pointer can be changed */
#define SPA_DATA_FLAG_READWRITE	(SPA_DATA_FLAG_READABLE|SPA_DATA_FLAG_WRITABLE)
#define SPA_DATA_FLAG_MAPPABLE	(1u<<3)	/**< data is mappable with simple mmap/munmap. Some memory
					  *  types are not simply mappable (DmaBuf) unless explicitly
					  *  specified with this flag. */
	uint32_t flags;			/**< data flags */
	int64_t fd;			/**< optional fd for data */
	uint32_t mapoffset;		/**< offset to map fd at, this is page aligned */
	uint32_t maxsize;		/**< max size of data */
	void *data;			/**< optional data pointer */
	struct spa_chunk *chunk;	/**< valid chunk of memory */
};
struct spa_chunk {
	uint32_t offset;		/**< offset of valid data. Should be taken
					  *  modulo the data maxsize to get the offset
					  *  in the data memory. */
	uint32_t size;			/**< size of valid data. Should be clamped to
					  *  maxsize. */
	int32_t stride;			/**< stride of valid data */
#define SPA_CHUNK_FLAG_NONE		0
#define SPA_CHUNK_FLAG_CORRUPTED	(1u<<0)	/**< chunk data is corrupted in some way */
#define SPA_CHUNK_FLAG_EMPTY		(1u<<1)	/**< chunk data is empty with media specific
						  *  neutral data such as silence or black. This
						  *  could be used to optimize processing. */
	int32_t flags;			/**< chunk flags */
};


struct pw_stream_events {
#define PW_VERSION_STREAM_EVENTS	2
	uint32_t version;

	void (*destroy) (void *data);
	/** when the stream state changes. Since 1.4 this also sets errno when the
	 * new state is PW_STREAM_STATE_ERROR */
	void (*state_changed) (void *data, enum pw_stream_state old,
				enum pw_stream_state state, const char *error);

	/** Notify information about a control.  */
	void (*control_info) (void *data, uint32_t id, const struct pw_stream_control *control);

	/** when io changed on the stream. */
	void (*io_changed) (void *data, uint32_t id, void *area, uint32_t size);
	/** when a parameter changed */
	void (*param_changed) (void *data, uint32_t id, const struct spa_pod *param);

        /** when a new buffer was created for this stream */
        void (*add_buffer) (void *data, struct pw_buffer *buffer);
        /** when a buffer was destroyed for this stream */
        void (*remove_buffer) (void *data, struct pw_buffer *buffer);

        /** when a buffer can be queued (for playback streams) or
         *  dequeued (for capture streams). This is normally called from the
	 *  mainloop but can also be called directly from the realtime data
	 *  thread if the user is prepared to deal with this. */
        void (*process) (void *data);

	/** The stream is drained */
        void (*drained) (void *data);

	/** A command notify, Since 0.3.39:1 */
	void (*command) (void *data, const struct spa_command *command);

	/** a trigger_process completed. Since version 0.3.40:2.
	 *  This is normally called from the mainloop but since 1.1.0 it
	 *  can also be called directly from the realtime data
	 *  thread if the user is prepared to deal with this. */
	void (*trigger_done) (void *data);
};

// struct spa_audio_info_raw {
// 	enum spa_audio_format format;		/*< format, one of enum spa_audio_format */
// 	uint32_t flags;				/*< extra flags */
// 	uint32_t rate;				/*< sample rate */
// 	uint32_t channels;			/*< number of channels. This can be more than SPA_AUDIO_MAX_CHANNELS
// 						 *  and you may assume there is enough padding for the extra
// 						 *  channel positions. */
// 	uint32_t position[SPA_AUDIO_MAX_CHANNELS];	/*< channel position from enum spa_audio_channel */
// 	/* padding follows here when channels > SPA_AUDIO_MAX_CHANNELS */
// };
// 
// struct spa_pod {
// 	uint32_t size;		/* size of the body */
// 	uint32_t type;		/* a basic id of enum spa_type */
// };
// 
void pw_init(int *argc, char **argv[]);
int pw_stream_queue_buffer(struct pw_stream *stream, struct pw_buffer *buffer);
struct pw_buffer *pw_stream_dequeue_buffer(struct pw_stream *stream);
struct pw_main_loop* pw_main_loop_new(const struct spa_dict *props);
struct pw_loop * pw_main_loop_get_loop(struct pw_main_loop *loop);
struct pw_properties * pw_properties_new(const char *key, ...) SPA_SENTINEL;
// static inline struct spa_pod * spa_format_audio_raw_build(struct spa_pod_builder *builder, uint32_t id, const struct spa_audio_info_raw *info);

int pw_stream_connect(struct pw_stream *stream,		/**< a \ref pw_stream */

		  enum pw_direction direction,		/**< the stream direction */
		  uint32_t target_id,			/**< should have the value PW_ID_ANY.
							  * To select a specific target
							  * node, specify the
							  * PW_KEY_OBJECT_SERIAL or the
							  * PW_KEY_NODE_NAME value of the target
							  * node in the PW_KEY_TARGET_OBJECT
							  * property of the stream.
							  * Specifying target nodes by
							  * their id is deprecated.
							  */
		  enum pw_stream_flags flags,		/**< stream flags */
		  const struct spa_pod **params,	/**< an array with params. The params
							  *  should ideally contain supported
							  *  formats. */
		  uint32_t n_params			/**< number of items in \a params */);

struct pw_stream * pw_stream_new_simple(struct pw_loop *loop,	/**< a \ref pw_loop to use as the main loop */
		     const char *name,		/**< a stream media name */
		     struct pw_properties *props,/**< stream properties, ownership is taken */
		     const struct pw_stream_events *events,	/**< stream events */
		     void *data					/**< data passed to events */);

void pw_stream_destroy(struct pw_stream *stream);
void pw_main_loop_destroy(struct pw_main_loop *loop);
void pw_deinit(void);
int pw_stream_flush(struct pw_stream *stream, bool drain);
static inline int pw_loop_get_fd(struct pw_loop *object);
static inline int pw_loop_iterate(struct pw_loop *object, int timeout);
int pw_main_loop_run(struct pw_main_loop *loop);
int pw_stream_set_active(struct pw_stream *stream, bool active);

struct spa_pod* format_audio_raw_build_workaround(struct spa_pod_builder *builder, uint32_t id, const struct spa_audio_info_raw *info);
