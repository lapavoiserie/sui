package sui.mui;

import mui.surface.SurfaceDecl;
import mui.surface.SurfaceRole;
import nui.Snapshot;
import nui.Snapshot.ActionTable;

/**
	The `Glance` surface, sampled for a WidgetKit widget.

	## The same corner, a wider gap

	Android's widget is drawn by the launcher from `RemoteViews` our process
	built; WidgetKit's is drawn by a **separate binary** — an app extension,
	its own process, its own sandbox — which cannot call into this application
	at all. So where `aui` hands Kotlin a JSON string in memory, here the
	string has to *land somewhere both binaries can read*: the App Group
	container both targets are entitled to.

	That is the only difference, and it is worth stating plainly because the
	rest is identical: the content thunk runs, `sui.nui.Describe` turns the
	tree into `nui` nodes, and `nui.Snapshot.project` turns those into pure
	data — the same shape a Companion frame carries over the network and the
	same shape the Android widget stores. One contract, three distances.

	## What crosses, and what cannot

	Not the closures. `project` registers them in an `ActionTable` and writes
	their ids into the tree; the table stays here, in the application's
	process, which the extension will never share. A widget that only displays
	needs nothing more, and that is this slice. Interaction across an app
	extension is an `AppIntent`, and the intent runs where the closures are
	not — that is the piece still to build, and it is a different problem from
	Android's, where the tap already lands in our own process.
**/
@:keep
class GlanceBridge {
	static var _table:Null<ActionTable> = null;
	static var _sampled:Null<sui.mui.App> = null;

	/**
		Sample the running application's Glance surface as snapshot JSON, or
		`null` when it declares none.

		Unlike aui's, this has one application to ask and no cold-process case:
		nothing samples here but the application itself, in answer to its own
		`Resample.request`. The extension reads what was left for it, and never
		asks us for anything.
	**/
	public static function sample(app:sui.mui.App):Null<String> {
		var decl = pickGlance(app.surfaces());
		if (decl == null) return null;

		var content = switch (decl) {
			case Tree(_, _, c): c;
			case _: null;
		}
		if (content == null) return null;

		_sampled = app;
		if (_table == null) _table = new ActionTable();
		var node = sui.nui.Describe.describe(content());
		return haxe.Json.stringify(Snapshot.project(node, _table));
	}

	/**
		Remember the application without sampling it.

		Called from `sui.mui.App`'s constructor, where sampling would be fatal
		— the subclass has not initialised its `@:state` fields yet, so the
		declaration's thunk would read a null cell and take the boot down with
		it. Holding the reference costs nothing and is what lets the scene-phase
		observer ask for a sample later, when the application is whole.
	**/
	public static function attach(app:sui.mui.App):Void {
		_sampled = app;
	}

	/** The application this bridge last sampled, for a resample that names no
		application of its own. **/
	public static function sampleAgain():Null<String> {
		var mine = _sampled;
		return mine == null ? null : sample(mine);
	}

	/**
		Same rule `qui` applies to the cover and `aui` to the widget: the
		declaration whose id is the role's default if there is one, else the
		first declared. Stated rather than left to iteration order, which is
		not identity.
	**/
	static function pickGlance(decls:Array<SurfaceDecl>):Null<SurfaceDecl> {
		var first:Null<SurfaceDecl> = null;
		for (d in decls) switch (d) {
			case Tree(SurfaceRole.Glance, id, _):
				if (id == "glance") return d;
				if (first == null) first = d;
			case _:
		}
		return first;
	}
}
