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
 * sui View, or behind a nui Node when a received tree is drawing.
 *
 * GC note: each entry registers the stack top through `HaxeCall`, which counts
 * nesting so a re-entrant call does not detach the thread under the call that
 * is still running — see the comment on that struct. A returned string is
 * copied out of GC memory by `keep` and stays valid for the next few calls on
 * the same thread; a returned NODE pointer is still the caller's to copy
 * before the next GC.
 */

#include <hxcpp.h>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <sui/View.h>
#include <sui/runtime/ViewNodeBridge.h>
#include <sui/state/Callbacks.h>

// hxcpp's library entry (hx::Init, in StdLibs.o) references the generated app
// main (___hxcpp_lib_main). This weak stub was here because the CLI used to
// assemble the static library by hand and had to leave out __main__.o, whose
// C main() would clash with the Swift @main entry — leaving that reference
// with nothing to resolve it.
//
// **Vestigial since the CLI stopped doing that.** Every platform now builds
// under `static_link`, so hxcpp emits `__lib__.o` — the real library entry,
// with no `main()` — instead of `__main__.o`, and that defines this symbol
// properly. A strong definition beats a weak one, so what is below is no
// longer reached on any supported target.
//
// Kept rather than deleted, for one reason: it costs nothing, and removing it
// would make a build that somehow produced a library without `__lib__.o` fail
// at link time in a place that names neither the cause nor the fix.
extern "C" __attribute__((weak)) int __hxcpp_lib_main() { return 0; }

// Resolve an opaque node handle back into a Haxe object.
//
// The `void*` is NOT an address. It carries a small integer, and the node it
// names lives in a map on the Haxe side. That indirection is the whole point:
// hxcpp's Immix collector MOVES objects, so an address handed across this
// boundary is a promise nobody made -- and Swift's `ViewNode` is a struct that
// holds one for as long as SwiftUI keeps the closure it was captured into.
// Dragging a slider killed the app every few seconds, on a node that was alive
// and had simply been relocated: non-null, header zeroed, SIGSEGV on the first
// virtual call.
//
// A handle names a PLACE -- a root, or a parent handle and a child index -- and
// resolves against the current tree, so a closure SwiftUI kept from several
// rebuilds ago still reaches the control it was built for. `void*` rather
// than an int32 so the renderer's own code does not change: it passes the
// thing along opaquely, which is what it always did. Handles start at 1, so a
// null pointer still reads as "no node" on the Swift side.
// A handle is three things in one word:
//
//   low 32 bits   the PLACE, which is all the Haxe side resolves;
//   next 16       a SIGNATURE of the node it was issued for -- its type and the
//                 cell it edits -- so a place that now holds something else
//                 (a component was inserted before it) answers null instead
//                 of the wrong control. See `ViewNodeBridge.nodeOfChecked`;
//   top 16        the generation, there only so a rebuilt view is a different
//                 value to SwiftUI -- see `ViewNodeBridge.generation`. It
//                 wraps, which is fine: it has to differ, not to order.
//
// Sixty-four-bit pointers are assumed. Every target sui builds for has them;
// watchOS's arm64_32 would not.
static_assert(sizeof(void*) >= 8, "a sui node handle needs a 64-bit pointer");

static inline int _placeOf(void* handle) {
    return (int)((uintptr_t)handle & 0xffffffffu);
}

static inline void* _handle(int place) {
    if (place == 0) return nullptr;
    uintptr_t generation = (uintptr_t)(::sui::runtime::ViewNodeBridge_obj::generation() & 0xffff);
    uintptr_t signature = (uintptr_t)(::sui::runtime::ViewNodeBridge_obj::signatureOfPlace(place) & 0xffff);
    return (void*)((generation << 48) | (signature << 32) | (uintptr_t)(uint32_t)place);
}

static inline ::Dynamic _asView(void* node) {
    int signature = (int)(((uintptr_t)node >> 32) & 0xffff);
    return ::sui::runtime::ViewNodeBridge_obj::nodeOfChecked(_placeOf(node), signature);
}

// And the other way: a node leaving for the renderer becomes a handle, which
// names the PLACE it was reached from -- a root by id, or a parent handle and
// a child index -- so that it resolves against whatever tree is current when
// it is read. See `ViewNodeBridge.nodeOf`.
static inline void* _asRootHandle(const char* id, ::Dynamic node) {
    return _handle(::sui::runtime::ViewNodeBridge_obj::handleOfRoot(::String(id), node));
}

static inline void* _asChildHandle(void* parent, int32_t index, ::Dynamic node) {
    return _handle(::sui::runtime::ViewNodeBridge_obj::handleOfChild(_placeOf(parent), index, node));
}


// ---------------------------------------------------------------------------
// Entering Haxe from native code, RE-ENTRANTLY.
//
// Every entry used to do this, on its own:
//
//     int dummy = 0;
//     hx::SetTopOfStack(&dummy, true);
//     ... call Haxe ...
////
// which is right for one call and wrong for a nested one, and nested ones are
// the normal case here. Dragging a slider does this:
//
//     viewnode_set_state          <- native enters Haxe
//       State.set                 <- Haxe writes the cell
//         _hxsui_notify_swift     <- and tells Swift
//           SwiftUI re-evaluates SuiSlider.body, synchronously
//             viewnode_get_property   <- native enters Haxe AGAIN
//             ... and on the way out: SetTopOfStack(0, false)
//
// The inner exit DETACHED the thread while the outer call's Haxe frame was
// still live. Whatever that frame touched next went through a null stack
// context: EXC_BAD_ACCESS at 0x0, reported inside `getStringProperty` because
// that is simply where the thread happened to be. Reproduced by moving a
// slider; the app died and macOS relaunched it.
//
// So the attach is counted. Only the outermost entry registers a stack top,
// only the outermost exit gives it back, and the anchor is the outermost
// frame's -- the highest address, which is what hxcpp wants.
//
// Set `SUI_BRIDGE_TRACE` to have the deepest nesting reached printed when it
// grows, which is how the nesting above was measured rather than assumed.
// ---------------------------------------------------------------------------
namespace {

struct HaxeCall {
    int anchor;

    HaxeCall() {
        if (depth++ == 0) hx::SetTopOfStack(&anchor, true);
        if (depth > deepest) {
            deepest = depth;
            if (::getenv("SUI_BRIDGE_TRACE")) fprintf(stderr, "[sui] bridge nesting %d\n", depth);
        }
    }

    ~HaxeCall() {
        if (--depth == 0) hx::SetTopOfStack((int*)0, false);
    }

    static thread_local int depth;
    static thread_local int deepest;
};

thread_local int HaxeCall::depth = 0;
thread_local int HaxeCall::deepest = 0;

// A string handed back to native code, kept alive past the Haxe call.
//
// `::String::__CStr()` points INTO GC memory. The caller was told to copy it
// "before the next GC", which it cannot honour: by the time it holds the
// pointer the bridge has already returned and a collection may have moved or
// freed the string. So the bytes are copied here, into a small ring, so that a
// caller reading several properties in a row -- `bindingName` tries five --
// still holds valid memory for each.
const char* keep(::String value) {
    static thread_local std::string ring[8];
    static thread_local unsigned next = 0;

    std::string& slot = ring[next++ % 8];
    slot = value == null() ? std::string() : std::string(value.__CStr());
    return slot.c_str();
}

} // namespace

extern "C" {

// --- Action dispatch ---

// Invoke a registered action closure by id. Mirrors the static bridge's
// dispatch: both route through the sui.state.Callbacks store, so a Button
// built at runtime via body() fires the same closure it registered with
// Callbacks.reg().
void haxe_bridge_invoke_action(int32_t actionId) {
    HaxeCall _call;
    try {
        ::sui::state::Callbacks_obj::run(actionId);
    } catch (...) {}
}

// --- View tree lifecycle ---

// Rebuild the view tree (call App.body())
void viewnode_rebuild(void) {
    HaxeCall _call;
    try {
        ::sui::runtime::ViewNodeBridge_obj::rebuild();
    } catch (...) {}
}

// Pump the poll delegate on the calling thread; returns 1 if the tree changed.
int32_t viewnode_poll(void) {
    HaxeCall _call;
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::poll() ? 1 : 0;
    } catch (...) {}
    return result;
}

// Defined with sui.runtime.ViewNodeBridge, beside the flag poll() clears.
void sui_bridge_set_pump_requester(void (*requester)(void));

// Install the host's requester and start watching the main thread's event loop.
// Call on the main thread, after boot.
void viewnode_set_pump_requester(void (*requester)(void)) {
    sui_bridge_set_pump_requester(requester);
    HaxeCall _call;
    try {
        ::sui::runtime::ViewNodeBridge_obj::watchMainEvents();
    } catch (...) {}
}

// A native input changed: write value at data-model path back into the app.
void viewnode_set_data(const char* path, const char* value) {
    HaxeCall _call;
    try {
        ::sui::runtime::ViewNodeBridge_obj::setData(::String(path), ::String(value));
    } catch (...) {}
}

// The theme accent (primaryColor hex) to tint native controls with.
const char* viewnode_theme_accent(void) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getAccent());
    } catch (...) {}
    return result;
}

// Fire a named action with a JSON extra-context.
void viewnode_fire_action(const char* name, const char* extraJson) {
    HaxeCall _call;
    try {
        ::sui::runtime::ViewNodeBridge_obj::fireAction(::String(name), ::String(extraJson));
    } catch (...) {}
}

// Get root view node (returns opaque pointer)
void* viewnode_get_root(void) {
    HaxeCall _call;
    void* result = nullptr;
    try {
        ::Dynamic root = ::sui::runtime::ViewNodeBridge_obj::getRoot();
        result = _asRootHandle("body", root);
    } catch (...) {}
    return result;
}

// A declared surface root's view node by its stable id.
void* viewnode_root_for(const char* id) {
    HaxeCall _call;
    void* result = nullptr;
    try {
        ::Dynamic root = ::sui::runtime::ViewNodeBridge_obj::getRootFor(::String(id));
        result = _asRootHandle(id, root);
    } catch (...) {}
    return result;
}

// --- Command sets (the menu bar's data) ---

int32_t viewnode_command_set_count(void) {
    HaxeCall _call;
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::commandSetCount();
    } catch (...) {}
    return result;
}

const char* viewnode_command_set_id(int32_t set) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::commandSetId(set));
    } catch (...) {}
    return result;
}

int32_t viewnode_command_count(int32_t set) {
    HaxeCall _call;
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::commandCount(set);
    } catch (...) {}
    return result;
}

const char* viewnode_command_label(int32_t set, int32_t index) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::commandLabel(set, index));
    } catch (...) {}
    return result;
}

const char* viewnode_command_shortcut(int32_t set, int32_t index) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::commandShortcut(set, index));
    } catch (...) {}
    return result;
}

void viewnode_command_invoke(int32_t set, int32_t index) {
    HaxeCall _call;
    try {
        ::sui::runtime::ViewNodeBridge_obj::invokeCommand(set, index);
    } catch (...) {}
}

// --- Node accessors ---

const char* viewnode_get_type(void* node) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getViewType(_asView(node)));
    } catch (...) {}
    return result;
}

int32_t viewnode_child_count(void* node) {
    HaxeCall _call;
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getChildCount(_asView(node));
    } catch (...) {}
    return result;
}

void* viewnode_get_child(void* node, int32_t index) {
    HaxeCall _call;
    void* result = nullptr;
    try {
        ::Dynamic child = ::sui::runtime::ViewNodeBridge_obj::getChild(_asView(node), index);
        result = _asChildHandle(node, index, child);
    } catch (...) {}
    return result;
}

// --- Properties ---

const char* viewnode_get_property(void* node, const char* key) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getStringProperty(_asView(node), ::String(key)));
    } catch (...) {}
    return result;
}

// --- Text ---

const char* viewnode_get_text(void* node) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getTextContent(_asView(node)));
    } catch (...) {}
    return result;
}

// --- Button ---

const char* viewnode_get_button_label(void* node) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getButtonLabel(_asView(node)));
    } catch (...) {}
    return result;
}

int32_t viewnode_get_button_action_id(void* node) {
    HaxeCall _call;
    int32_t result = -1;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getButtonActionId(_asView(node));
    } catch (...) {}
    return result;
}

// Invoke a Button node's action closure directly — the dynamic renderer holds
// the live tree, so the closure on the node is GC-reachable and safe to call.
void viewnode_invoke_action(void* node) {
    HaxeCall _call;
    try {
        ::sui::runtime::ViewNodeBridge_obj::invokeButtonAction(_asView(node));
    } catch (...) {}
}

// --- Modifiers ---

int32_t viewnode_modifier_count(void* node) {
    HaxeCall _call;
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getModifierCount(_asView(node));
    } catch (...) {}
    return result;
}

const char* viewnode_modifier_type(void* node, int32_t index) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getModifierType(_asView(node), index));
    } catch (...) {}
    return result;
}

double viewnode_modifier_float(void* node, int32_t index, int32_t paramIndex) {
    HaxeCall _call;
    double result = 0.0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getModifierFloat(_asView(node), index, paramIndex);
    } catch (...) {}
    return result;
}

const char* viewnode_modifier_string(void* node, int32_t index, int32_t paramIndex) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getModifierString(_asView(node), index, paramIndex));
    } catch (...) {}
    return result;
}

/* --- Tabs ------------------------------------------------------------------ */
int32_t viewnode_tab_count(void* node) {
    HaxeCall _call;
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::getTabCount(_asView(node));
    } catch (...) {}
    return result;
}

const char* viewnode_tab_title(void* node, int32_t index) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getTabTitle(_asView(node), index));
    } catch (...) {}
    return result;
}

const char* viewnode_tab_icon(void* node, int32_t index) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getTabIcon(_asView(node), index));
    } catch (...) {}
    return result;
}

/* --- Fine-grained updates -------------------------------------------------
 *
 * SwiftUI cannot observe a state read that crosses this bridge, so it cannot
 * know which view depends on which cell. Haxe works that out and answers here:
 * which cells a node displays, and whether a write to a cell changes the tree's
 * shape or only a value.
 */
const char* viewnode_value_deps(void* node) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getValueDependencies(_asView(node)));
    } catch (...) {}
    return result;
}

int32_t viewnode_is_structural(const char* name) {
    HaxeCall _call;
    /* Rebuilding is the answer that cannot be wrong, so it is also the answer
     * when the call itself fails. */
    int32_t result = 1;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::isStructural(::String(name)) ? 1 : 0;
    } catch (...) {}
    return result;
}

/* --- Named state ------------------------------------------------------------
 *
 * A sui control's binding is a name, not a cell: the transpiler turned it into
 * `$appState.userName`. The dynamic renderer resolves the same name against the
 * registry every State joins on construction.
 */
const char* viewnode_state_value(const char* name) {
    HaxeCall _call;
    const char* result = "";
    try {
        result = keep(::sui::runtime::ViewNodeBridge_obj::getStateValue(::String(name)));
    } catch (...) {}
    return result;
}

int32_t viewnode_state_exists(const char* name) {
    HaxeCall _call;
    int32_t result = 0;
    try {
        result = ::sui::runtime::ViewNodeBridge_obj::hasStateValue(::String(name)) ? 1 : 0;
    } catch (...) {}
    return result;
}

void viewnode_set_state(const char* name, const char* value) {
    HaxeCall _call;
    try {
        ::sui::runtime::ViewNodeBridge_obj::setStateValue(::String(name), ::String(value));
    } catch (...) {}
}

/* --- State writes -----------------------------------------------------------
 *
 * `sui.state.State.set()` calls `_hxsui_notify_swift(key, value)` on every
 * application write, and that hook is compiled into libhaxe.a whatever the
 * render path. The *static* path used it to update the generated `AppState`,
 * an ObservableObject SwiftUI was already watching.
 *
 * The dynamic path has no AppState: the views are not generated, so there is no
 * published field to write. The tree itself carries the state -- `body()` reads
 * the Haxe cell -- so the answer to a write is to rebuild the tree and let the
 * host know. That is what the renderer registers here.
 *
 * Without it a dynamic app drew its first frame and then never changed: a tap
 * ran the Haxe closure, the state moved, and nothing on screen followed. The
 * poll timer was the only way back, and it only fires for an app that streams
 * its UI from somewhere else.
 */
extern "C" void haxe_bridge_register_state_fn(void (*cb)(const char*, const char*));

// Declared here as well as in ViewNodeBridgeC.h: this file is compiled with the
// hxcpp and generated-app include paths only, not with its own header's
// directory, so the header is not reachable from here.
typedef void (*viewnode_state_observer_t)(const char* key, const char* value);

static viewnode_state_observer_t _viewnode_state_observer = 0;

static void _viewnode_forward_state(const char* key, const char* value) {
    if (_viewnode_state_observer) _viewnode_state_observer(key, value);
}

void viewnode_observe_state(viewnode_state_observer_t observer) {
    _viewnode_state_observer = observer;
    haxe_bridge_register_state_fn(_viewnode_forward_state);
}

} // extern "C"
