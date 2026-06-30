
Because read and write only ever modify their respective indicies, they are safe to use together. However, for reset, this is not the case. Since it modifies both values, it could then be overwritten by a later store which loaded an old value.

When the Audio Ring Buffer is Full: Call epoll_wait with an infinite timeout (-1). The thread sleeps peacefully until a message arrives on your control eventfd or the PipeWire thread consumes enough audio to trigger a "need more data" signal.
When the Audio Ring Buffer Needs Data: Call epoll_wait with a timeout of 0 (non-blocking poll).
    If a message is waiting, process it instantly (e.g., if it's "Seek", flush FFmpeg buffers).
    If no message is waiting, decode exactly one chunk of audio (e.g., one FFmpeg AVFrame), write it to the SPSC ring buffer, and repeat the loop.

Look into sdbus in systemd/sd-bus.h
Look into eventfd instead of futex
