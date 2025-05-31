#ifndef LOCAL_PEER_SYNC_CORE_H
#define LOCAL_PEER_SYNC_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SyncHandle SyncHandle;

// Core functions
SyncHandle* sync_init(const char* device_name);
int32_t sync_start(SyncHandle* handle);
int32_t sync_stop(SyncHandle* handle);
void sync_cleanup(SyncHandle* handle);

// Device info
char* sync_get_device_id(SyncHandle* handle);
char* sync_get_device_name(SyncHandle* handle);
int32_t sync_is_running(SyncHandle* handle);

// Peer management
int32_t sync_get_peer_count(SyncHandle* handle);
char* sync_get_peers_json(SyncHandle* handle);

// Clipboard sync
int32_t sync_clipboard(SyncHandle* handle, const char* content);

// Memory management
void sync_free_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif
