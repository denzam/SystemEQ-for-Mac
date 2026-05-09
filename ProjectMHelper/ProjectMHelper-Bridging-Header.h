//
//  ProjectMHelper-Bridging-Header.h
//  ProjectMHelper
//
//  Bridging header for libprojectM 4.x C API
//

#ifndef ProjectMHelper_Bridging_Header_h
#define ProjectMHelper_Bridging_Header_h

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdatomic.h>
#include <OpenGL/gl3.h>

typedef struct { _Atomic(int32_t) value; } PMAtomicInt32;

static inline PMAtomicInt32 pm_atomic_make(int32_t v) {
    PMAtomicInt32 a;
    atomic_store_explicit(&a.value, v, memory_order_relaxed);
    return a;
}
static inline void pm_atomic_init(PMAtomicInt32 *a, int32_t v) {
    atomic_store_explicit(&a->value, v, memory_order_relaxed);
}
static inline int32_t pm_atomic_load(const PMAtomicInt32 *a) {
    return atomic_load_explicit(&a->value, memory_order_acquire);
}
static inline int32_t pm_atomic_fetch_add(PMAtomicInt32 *a, int32_t delta) {
    return atomic_fetch_add_explicit(&a->value, delta, memory_order_acq_rel);
}

// projectM handle types - use struct pointers for proper Swift interop
typedef struct projectm* projectm_handle;
typedef struct projectm_playlist* projectm_playlist_handle;

// Audio channel types
typedef enum {
    PROJECTM_MONO = 1,
    PROJECTM_STEREO = 2
} projectm_channels;

#pragma mark - Core Functions

extern projectm_handle projectm_create(void);
extern void projectm_destroy(projectm_handle instance);
extern void projectm_load_preset_file(projectm_handle instance, const char* filename, bool smooth_transition);
extern char* projectm_get_version_string(void);
extern void projectm_free_string(char* str);

#pragma mark - Rendering

extern void projectm_opengl_render_frame(projectm_handle instance);
extern void projectm_set_window_size(projectm_handle instance, size_t width, size_t height);

#pragma mark - Audio Input

extern void projectm_pcm_add_float(projectm_handle instance, const float* samples,
                                   unsigned int count, projectm_channels channels);

#pragma mark - Parameters

extern void projectm_set_preset_duration(projectm_handle instance, double seconds);
extern void projectm_set_soft_cut_duration(projectm_handle instance, double seconds);
extern void projectm_set_hard_cut_enabled(projectm_handle instance, bool enabled);
extern void projectm_set_hard_cut_sensitivity(projectm_handle instance, float sensitivity);
extern void projectm_set_preset_locked(projectm_handle instance, bool lock);
extern void projectm_set_mesh_size(projectm_handle instance, size_t width, size_t height);
extern void projectm_set_fps(projectm_handle instance, int32_t fps);
extern void projectm_set_aspect_correction(projectm_handle instance, bool enabled);
extern void projectm_set_texture_search_paths(projectm_handle instance, const char** paths, size_t count);

#pragma mark - Callbacks

typedef void (*projectm_preset_switch_failed_event)(const char* preset_filename, const char* message, void* user_data);
extern void projectm_set_preset_switch_failed_event_callback(projectm_handle instance,
                                                              projectm_preset_switch_failed_event callback,
                                                              void* user_data);

#pragma mark - Playlist

extern projectm_playlist_handle projectm_playlist_create(projectm_handle projectm_instance);
extern void projectm_playlist_destroy(projectm_playlist_handle instance);
extern size_t projectm_playlist_add_path(projectm_playlist_handle instance, const char* path,
                                         bool recurse_subdirs, bool allow_duplicates);
extern bool projectm_playlist_add_preset(projectm_playlist_handle instance, const char* filename, bool allow_duplicates);
extern void projectm_playlist_clear(projectm_playlist_handle instance);
extern void projectm_playlist_play_next(projectm_playlist_handle instance, bool hard_cut);
extern void projectm_playlist_play_previous(projectm_playlist_handle instance, bool hard_cut);
extern size_t projectm_playlist_get_position(projectm_playlist_handle instance);
extern void projectm_playlist_set_position(projectm_playlist_handle instance, size_t index, bool hard_cut);
extern void projectm_playlist_set_shuffle(projectm_playlist_handle instance, bool shuffle);
extern char* projectm_playlist_item(projectm_playlist_handle instance, size_t index);
extern size_t projectm_playlist_size(projectm_playlist_handle instance);

#endif /* ProjectMHelper_Bridging_Header_h */
