//
//  ProjectMBridge.h
//  SystemEQ for Mac
//
//  Bridging header for libprojectM 4.x C API
//  Enables Swift integration with MilkDrop visualizations
//

#ifndef ProjectMBridge_h
#define ProjectMBridge_h

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// projectM handle type
typedef void* projectm_handle;

// Audio channel types
typedef enum {
    PROJECTM_MONO = 1,
    PROJECTM_STEREO = 2
} projectm_channels;

// Preset switch callback type
typedef void (*projectm_preset_switch_requested_event)(bool is_hard_cut, void* user_data);
typedef void (*projectm_preset_switch_failed_event)(const char* preset_filename, const char* message, void* user_data);

#pragma mark - Core Functions

// Create and destroy
extern projectm_handle projectm_create(void);
extern void projectm_destroy(projectm_handle instance);

// Preset loading
extern void projectm_load_preset_file(projectm_handle instance, const char* filename, bool smooth_transition);
extern void projectm_load_preset_data(projectm_handle instance, const char* data, bool smooth_transition);

// Version info
extern void projectm_get_version_components(int* major, int* minor, int* patch);
extern char* projectm_get_version_string(void);
extern void projectm_free_string(char* str);

#pragma mark - Rendering

// OpenGL rendering
extern void projectm_opengl_render_frame(projectm_handle instance);

// Window/viewport size
extern void projectm_set_window_size(projectm_handle instance, size_t width, size_t height);
extern void projectm_get_window_size(projectm_handle instance, size_t* width, size_t* height);

#pragma mark - Audio Input

// Get max samples
extern unsigned int projectm_pcm_get_max_samples(void);

// Add audio samples
extern void projectm_pcm_add_float(projectm_handle instance, const float* samples,
                                   unsigned int count, projectm_channels channels);
extern void projectm_pcm_add_int16(projectm_handle instance, const int16_t* samples,
                                   unsigned int count, projectm_channels channels);

#pragma mark - Parameters

// Preset duration and transitions
extern void projectm_set_preset_duration(projectm_handle instance, double seconds);
extern double projectm_get_preset_duration(projectm_handle instance);

extern void projectm_set_soft_cut_duration(projectm_handle instance, double seconds);
extern double projectm_get_soft_cut_duration(projectm_handle instance);

extern void projectm_set_hard_cut_enabled(projectm_handle instance, bool enabled);
extern bool projectm_get_hard_cut_enabled(projectm_handle instance);

extern void projectm_set_hard_cut_sensitivity(projectm_handle instance, float sensitivity);
extern float projectm_get_hard_cut_sensitivity(projectm_handle instance);

// Preset lock
extern void projectm_set_preset_locked(projectm_handle instance, bool lock);
extern bool projectm_get_preset_locked(projectm_handle instance);

// Mesh size
extern void projectm_set_mesh_size(projectm_handle instance, size_t width, size_t height);
extern void projectm_get_mesh_size(projectm_handle instance, size_t* width, size_t* height);

// FPS
extern void projectm_set_fps(projectm_handle instance, int32_t fps);
extern int32_t projectm_get_fps(projectm_handle instance);

// Aspect correction
extern void projectm_set_aspect_correction(projectm_handle instance, bool enabled);
extern bool projectm_get_aspect_correction(projectm_handle instance);

// Texture paths
extern void projectm_set_texture_search_paths(projectm_handle instance, const char** paths, size_t count);

#pragma mark - Callbacks

// Set callbacks for preset events
extern void projectm_set_preset_switch_requested_event_callback(projectm_handle instance,
                                                                 projectm_preset_switch_requested_event callback,
                                                                 void* user_data);
extern void projectm_set_preset_switch_failed_event_callback(projectm_handle instance,
                                                              projectm_preset_switch_failed_event callback,
                                                              void* user_data);

#pragma mark - Playlist Library (optional)

typedef void* projectm_playlist_handle;

// Playlist creation
extern projectm_playlist_handle projectm_playlist_create(projectm_handle projectm_instance);
extern void projectm_playlist_destroy(projectm_playlist_handle instance);

// Playlist management
extern size_t projectm_playlist_size(projectm_playlist_handle instance);
extern size_t projectm_playlist_add_path(projectm_playlist_handle instance, const char* path,
                                         bool recurse_subdirs, bool allow_duplicates);
extern void projectm_playlist_clear(projectm_playlist_handle instance);

// Playlist playback
extern void projectm_playlist_play_next(projectm_playlist_handle instance, bool hard_cut);
extern void projectm_playlist_play_previous(projectm_playlist_handle instance, bool hard_cut);
extern size_t projectm_playlist_get_position(projectm_playlist_handle instance);
extern void projectm_playlist_set_position(projectm_playlist_handle instance, size_t index, bool hard_cut);

// Shuffle
extern void projectm_playlist_set_shuffle(projectm_playlist_handle instance, bool shuffle);
extern bool projectm_playlist_get_shuffle(projectm_playlist_handle instance);

// Get preset info
extern char* projectm_playlist_item(projectm_playlist_handle instance, size_t index);

#endif /* ProjectMBridge_h */
