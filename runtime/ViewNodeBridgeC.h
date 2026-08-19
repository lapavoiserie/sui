#ifndef VIEWNODE_BRIDGE_H
#define VIEWNODE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Runtime bootstrap (dynamic renderer / hot reload) ---
// Boots the hxcpp runtime, instantiates the app, and registers it with
// ViewNodeBridge so the view tree can be traversed. The hxcpp boot runs once;
// subsequent calls just rebuild from the (re)loaded app. Implemented by the
// macro-generated SuiBootC.cpp, which alone knows the concrete app class.
void viewnode_boot(void);

// --- View tree lifecycle ---
void viewnode_rebuild(void);
void* viewnode_get_root(void);
// A declared surface root's view node by its stable id ("body" is the
// Primary). NULL when no such root is mounted - the caller draws nothing,
// which is the degradation contract.
void* viewnode_root_for(const char* id);
// Pump the app's poll delegate (e.g. drain a WebSocket queue) on the calling
// thread; returns non-zero if the view tree changed and should be re-rendered.
int32_t viewnode_poll(void);

// A native input changed: write `value` at data-model `path` back into the app.
void viewnode_set_data(const char* path, const char* value);

// The theme accent (primaryColor hex) to tint native controls with ("" = default).
const char* viewnode_theme_accent(void);

// Fire a named action with a JSON extra-context (e.g. a Board drop's payload).
void viewnode_fire_action(const char* name, const char* extraJson);

// --- Action dispatch (dynamic renderer) ---
// Invoke a registered action closure by its compile-time id. Routes to the
// same sui.state.Callbacks store the static bridge uses, so buttons built at
// runtime via body() dispatch identically.
void haxe_bridge_invoke_action(int32_t actionId);

// --- Node accessors ---
const char* viewnode_get_type(void* node);
int32_t viewnode_child_count(void* node);
void* viewnode_get_child(void* node, int32_t index);

// --- Properties ---
const char* viewnode_get_property(void* node, const char* key);

// --- Text ---
const char* viewnode_get_text(void* node);

// --- Button ---
const char* viewnode_get_button_label(void* node);
int32_t viewnode_get_button_action_id(void* node);
// Invoke a Button node's action closure directly (dynamic renderer path).
void viewnode_invoke_action(void* node);

// --- Tabs ---
// A TabView's contents are children; its labels and icons are here.
int32_t viewnode_tab_count(void* node);
const char* viewnode_tab_title(void* node, int32_t index);
const char* viewnode_tab_icon(void* node, int32_t index);

// --- Fine-grained updates ---
// Which cells a node displays, comma-joined; and whether a write to a cell
// changes the tree's shape (1) or only a value (0).
const char* viewnode_value_deps(void* node);
int32_t viewnode_is_structural(const char* name);

// --- Named state ---
// A sui control binds by name; these resolve it against the state registry.
const char* viewnode_state_value(const char* name);
int32_t viewnode_state_exists(const char* name);
void viewnode_set_state(const char* name, const char* value);

// --- State writes ---
// Called with (name, value) whenever the application writes a sui State.
typedef void (*viewnode_state_observer_t)(const char* key, const char* value);
// Register the observer. The renderer rebuilds the tree from it, since a
// dynamic build has no generated AppState for the write to land in.
void viewnode_observe_state(viewnode_state_observer_t observer);

// --- Modifiers ---
int32_t viewnode_modifier_count(void* node);
const char* viewnode_modifier_type(void* node, int32_t index);
double viewnode_modifier_float(void* node, int32_t index, int32_t paramIndex);
const char* viewnode_modifier_string(void* node, int32_t index, int32_t paramIndex);

#ifdef __cplusplus
}
#endif

#endif // VIEWNODE_BRIDGE_H
