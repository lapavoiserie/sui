# Views

sui provides 40+ built-in views that map directly to SwiftUI components.

## All Views

| View | Category | SwiftUI Equivalent | Description |
|------|----------|-------------------|-------------|
| `VStack` | Layout | `VStack` | Vertical stack |
| `HStack` | Layout | `HStack` | Horizontal stack |
| `ZStack` | Layout | `ZStack` | Overlay stack |
| `LazyVStack` | Layout | `LazyVStack` | Virtualized vertical stack |
| `LazyHStack` | Layout | `LazyHStack` | Virtualized horizontal stack |
| `LazyVGrid` | Layout | `LazyVGrid` | Vertical grid |
| `LazyHGrid` | Layout | `LazyHGrid` | Horizontal grid |
| `Spacer` | Layout | `Spacer` | Flexible space |
| `ScrollView` | Layout | `ScrollView` | Scrollable container |
| `Text` | Display | `Text` | Static text |
| `Text.bind` | Display | `Text("\(...)")` | Dynamic text from a typed Haxe expression |
| `Label` | Display | `Label` | Icon + text |
| `Image` | Display | `Image` | Image display |
| `ProgressView` | Display | `ProgressView` | Loading indicator |
| `Gauge` | Display | `Gauge` | Value indicator |
| `ContentUnavailableView` | Display | `ContentUnavailableView` | Empty state placeholder |
| `Button` | Control | `Button` | Tappable action |
| `TextField` | Control | `TextField` | Text input |
| `SecureField` | Control | `SecureField` | Password input |
| `TextEditor` | Control | `TextEditor` | Multi-line text input |
| `Toggle` | Control | `Toggle` | Boolean switch |
| `Slider` | Control | `Slider` | Range input |
| `Picker` | Control | `Picker` | Selection control |
| `Stepper` | Control | `Stepper` | Increment/decrement |
| `DatePicker` | Control | `DatePicker` | Date selection |
| `ColorPicker` | Control | `ColorPicker` | Color selection |
| `Link` | Control | `Link` | Open URL |
| `List` | Container | `List` | Row container |
| `Form` | Container | `Form` | Data entry container |
| `Section` | Container | `Section` | Grouped content |
| `GroupBox` | Container | `GroupBox` | Grouped box |
| `DisclosureGroup` | Container | `DisclosureGroup` | Expandable section |
| `ForEach` | Iteration | `ForEach` | Array iteration |
| `NavigationStack` | Navigation | `NavigationStack` | Navigation container |
| `NavigationLink` | Navigation | `NavigationLink` | Navigation trigger |
| `NavigationSplitView` | Navigation | `NavigationSplitView` | Split view (iPad) |
| `TabView` | Navigation | `TabView` | Tab-based navigation |
| `ConditionalView` | Logic | `if/else` | Conditional rendering |
| `AdaptiveStack` | Layout | Environment-based | Responsive sidebar/stack |

## Categories

- **[Layout](views/layout.md)** &mdash; VStack, HStack, ZStack, LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, Spacer, ScrollView
- **[Text & Labels](views/text-and-labels.md)** &mdash; Text, Text.bind, Label, Image
- **[Controls](views/controls.md)** &mdash; Button, TextField, SecureField, TextEditor, Toggle, Slider, Picker, Stepper, DatePicker, ColorPicker, Link
- **[Lists & Iteration](views/lists-and-iteration.md)** &mdash; List, ForEach, ScrollView, Section, Form, GroupBox, DisclosureGroup
- **[Navigation](views/navigation.md)** &mdash; NavigationStack, NavigationLink, NavigationSplitView, TabView
