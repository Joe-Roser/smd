typedef unsigned int u32;

typedef struct ring_buffer ring_buffer;

u32 ring_read(ring_buffer* rb, float* dst, u32 len);
u32 ring_write(ring_buffer* rb, float* dst, u32 len);
