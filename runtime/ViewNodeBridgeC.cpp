/**
 * C bridge for ViewNode tree traversal.
 * Called by native dynamic renderers (SwiftUI, Compose, WinUI)
 * to walk the Haxe view tree at runtime.
 *
 * Every function calls the sui.runtime.ViewNodeBridge statics through their
 * direct hxcpp symbols — the same style the static bridge uses for
 * Callbacks_obj::run. ViewNodeBridge is @:keep, so all its methods are present
 * in the generated header regardless of DCE. (An earlier draft used Type_obj
 * reflection, but Haxe's Type has no callStatic and DCE strips the rest, so the
 * direct-symbol path is both correct and more robust.)
 *
 * Nodes cross the boundary as opaque void* — the raw hx::Object* behind a
 * ::sui::View. GC note: each entry registers the stack top so allocations made
 * while building strings stay reachable; returned strings and pointers must be
 * copied by the caller before the next GC.
 */

#include <hxcpp.h>
#include <sui/View.h>
#include <sui/runtime/ViewNodeBridge.h>
#include <sui/state/Callbacks.h>

// hxcpp's library entry (hx::Init, in StdLibs.o) references the generated app
// main (___hxcpp_lib_main, from __main__.o). That object is left out of the
// static lib because its C main() would clash with the Swift @main entry — and
// we never call hx::Init anyway: the app is driven through viewnode_boot →
// hx::Boot → ViewNodeBridge. Provide a weak stub so the otherwise-dead
// reference resolves; a real definition, if ever linked, takes precedence.
extern "C" __attribute__((weak)) int __hxcpp_lib_main() { return 0; }

// Wrap an opaque node pointer back into a typed ::sui::View. Null-safe: a null
// pointer yields a null View, which every ViewNodeBridge method tolerates.
static inline ::sui::View _asView(void* node) {
    return ::sui::View((::sui::View_obj*)node);
}

extern "C" {

// --- Action dispatch ---

// Invoke a registered action closure by id. Mirrors the static bridge's
// dispatch: both route through the sui.state.Callbacks store, so a Button
// built at runtime via body() fires the same closure it registered with
// Callbacks.reg().
void haxe_bridge_invoke_action(int32_t actionId) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    try {
        ::sui::state::Callbacks_obj::run(actionId);
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
}

// --- View tree lifecycle ---

// Rebuild the view tree (call App.body())
void viewnode_rebuild(void) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    try {
        ::sui::runtime::ViewNodeBridge_obj::rebuild();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
}

// Pump the poll delegate on the calling thread; returns 1 if the tree changed.
int32_t viewnode_poll(void) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::poll() ? 1 : 0;
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

// A native input changed: write value at data-model path back into the app.
void viewnode_set_data(const char* path, const char* value) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    try {
        ::sui::runtime::ViewNodeBridge_obj::setData(::String(path), ::String(value));
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
}

// Get root view node (returns opaque pointer)
void* viewnode_get_root(void) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    void* result = nullptr;
    try {
        ::sui::View root = ::sui::runtime::ViewNodeBridge_obj::getRoot();
        result = root.GetPtr();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

// --- Node accessors ---

const char* viewnode_get_type(void* node) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    const char* result = "";
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getViewType(_asView(node)).__CStr();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

int32_t viewnode_child_count(void* node) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getChildCount(_asView(node));
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

void* viewnode_get_child(void* node, int32_t index) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    void* result = nullptr;
    try {
        ::sui::View child = ::sui::runtime::ViewNodeBridge_obj::getChild(_asView(node), index);
        result = child.GetPtr();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

// --- Properties ---

const char* viewnode_get_property(void* node, const char* key) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    const char* result = "";
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getStringProperty(_asView(node), ::String(key)).__CStr();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

// --- Text ---

const char* viewnode_get_text(void* node) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    const char* result = "";
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getTextContent(_asView(node)).__CStr();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

// --- Button ---

const char* viewnode_get_button_label(void* node) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    const char* result = "";
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getButtonLabel(_asView(node)).__CStr();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

int32_t viewnode_get_button_action_id(void* node) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    int32_t result = -1;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getButtonActionId(_asView(node));
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

// Invoke a Button node's action closure directly — the dynamic renderer holds
// the live tree, so the closure on the node is GC-reachable and safe to call.
void viewnode_invoke_action(void* node) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    try {
        ::sui::runtime::ViewNodeBridge_obj::invokeButtonAction(_asView(node));
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
}

// --- Modifiers ---

int32_t viewnode_modifier_count(void* node) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getModifierCount(_asView(node));
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

const char* viewnode_modifier_type(void* node, int32_t index) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    const char* result = "";
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getModifierType(_asView(node), index).__CStr();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

double viewnode_modifier_float(void* node, int32_t index, int32_t paramIndex) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    double result = 0.0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getModifierFloat(_asView(node), index, paramIndex);
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

const char* viewnode_modifier_string(void* node, int32_t index, int32_t paramIndex) {
    int dummy = 0;
    hx::SetTopOfStack(&dummy, true);
    const char* result = "";
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getModifierString(_asView(node), index, paramIndex).__CStr();
    } catch (...) {}
    hx::SetTopOfStack((int*)0, false);
    return result;
}

} // extern "C"
