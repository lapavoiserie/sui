package sui.mui;

import mui.surface.SurfaceDecl.SurfaceDeclTools;
import mui.surface.SurfaceRole;

/**
    `sui`'s `mui.surface.Present`: bring a declared surface forward.

    `Primary` is the main window -- raised, restored from the Dock, or opened
    again if it was closed. `Preferences` is the Settings scene. `Auxiliary`
    is one declared window, by its id, or the first. The app comes forward
    with it.

    The request is queued (`ViewNodeBridge.requestPresentation`) and the host
    acts on it once the closure that made it has returned.
**/
class Present {
    /** Whether there was something to bring forward: `false` for a role that
        is not a place to go, or a declaration that does not exist. **/
    public static function show(role:SurfaceRole, ?id:String):Bool {
        var app = App.current;
        var declared = app == null ? [] : app.surfaces();
        switch (role) {
            case Primary:
                sui.runtime.ViewNodeBridge.requestPresentation("primary", "");
                return true;
            case Preferences:
                var prefs = SurfaceDeclTools.pickOne(declared, Preferences, "preferences");
                if (prefs == null) return false;
                sui.runtime.ViewNodeBridge.requestPresentation("preferences", prefs.id);
                return true;
            case Auxiliary:
                for (w in SurfaceDeclTools.treesOf(declared, Auxiliary)) {
                    if (id != null && w.id != id) continue;
                    sui.runtime.ViewNodeBridge.requestPresentation("window", w.id);
                    return true;
                }
                return false;
            case _:
                return false;
        }
    }
}
