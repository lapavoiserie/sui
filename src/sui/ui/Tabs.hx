package sui.ui;

import sui.View;

/**
    Pages behind labels, one shown at a time: a tab bar, or a sidebar.

    ```haxe
    ui(<Tabs selectedIndex={section_} style="sidebar">
        <Tab label="Aujourd'hui" icon="calendar"><TodayScreen/></Tab>
        <Tab label="Tâches" icon="list"><ChoresScreen/></Tab>
    </Tabs>)
    ```

    Canon: `Tabs` carries `selectedIndex` with `onSelect`, an optional
    `style`, and `Tab` children; **only the selected tab carries its page**.

    ## The page nobody chose is not built into the tree

    Markup writes every tab's page, and this constructor keeps only the
    selected one, so the rule holds structurally here too: a page that is
    not shown cannot be described, projected or leaked. The selection is read
    as a dependency (`State.readByName`), so choosing another tab rebuilds
    the tree and the new page exists by the time it is drawn.

    ## `style="sidebar"`

    A hint, like a `Picker`'s `segmented` (`nui.Presentation.SIDEBAR`): the
    tabs as the rows of a navigation sidebar, the page beside them -- a
    `NavigationSplitView` here. A backend without one draws its tab bar, and
    nothing is lost but the shape.
**/
@:node("Tabs")
@:content("content")
class Tabs extends View {
    @:cell("selectedIndex", "onSelect", "Int") public var selectionBinding:String;
    @:prop public var style:Null<String>;

    public function new(selectionBinding:String, ?style:String, content:Array<View>) {
        super();
        this.viewType = "Tabs";
        this.selectionBinding = selectionBinding;
        this.style = style;
        var tabs = content == null ? [] : content;
        var raw:Dynamic = sui.state.State.readByName(selectionBinding);
        var selected:Int = raw == null ? 0 : Std.int(Std.parseFloat(Std.string(raw)));
        for (i in 0...tabs.length) {
            if (i != selected && Std.isOfType(tabs[i], Tab)) tabs[i].children = [];
        }
        this.children = tabs;
    }
}
